import Foundation

extension AgentFilesStore {
  var isSyncConnected: Bool { syncState.repository != nil }

  var pendingSyncedProjects: [SyncedWorkspace] {
    syncState.base.workspaces.filter { $0.kind == .project && localWorkspace(for: $0) == nil }
  }

  var syncStatus: String {
    if isSigningIn { return "Signing in" }
    if isSyncing { return "Syncing instructions" }
    if !syncConflicts.isEmpty {
      return syncConflicts.count == 1 ? "1 conflict to review" : "\(syncConflicts.count) conflicts to review"
    }
    if syncError != nil { return "Sync needs attention" }
    if !isSyncConnected { return "Connect your computers" }
    return syncState.automatic ? "Automatic sync is on" : "Automatic sync is paused"
  }

  func startInstructionSync() {
    syncTimerTask = Task { [weak self] in
      if self?.syncState.automatic == true { await self?.syncInstructions() }
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(60)) } catch { return }
        guard let self else { return }
        if self.syncState.automatic { await self.syncInstructions() }
      }
    }
  }

  func scheduleInstructionSync() {
    guard isSyncConnected, syncState.automatic else { return }
    syncDebounceTask?.cancel()
    syncDebounceTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      await self?.syncInstructions()
    }
  }

  func saveSyncState() throws { try syncStateStore.save(syncState) }

  func setAutomaticInstructionSync(_ automatic: Bool) {
    guard !isSyncing else { return }
    syncState.automatic = automatic
    do { try saveSyncState() } catch { syncError = error.localizedDescription }
    if automatic { scheduleInstructionSync() }
  }

  func signInToGitHub() async {
    guard !isSigningIn, !isSyncing else { return }
    isSigningIn = true
    syncSignInCode = nil
    syncError = nil
    defer { isSigningIn = false; syncSignInCode = nil }
    do {
      try await GitHubCLI.signIn { [weak self] code in
        Task { @MainActor in self?.syncSignInCode = code }
      }
    } catch { syncError = error.localizedDescription }
  }

  func connectInstructionSync(repositoryName: String = "agent-files-sync") async {
    guard !isSyncing, !isSigningIn, !isSyncConnected else { return }
    isSyncing = true
    syncError = nil
    do {
      let repository = try await syncRemote.connect(repositoryName: repositoryName)
      try prepareInstructionsForSync()
      syncState.repository = repository
      try saveSyncState()
    } catch {
      syncError = error.localizedDescription
    }
    isSyncing = false
    if isSyncConnected { await syncInstructions() }
  }

  func disconnectInstructionSync() {
    guard !isSyncing else { return }
    syncDebounceTask?.cancel()
    syncState.repository = nil
    syncState.lastSyncedAt = nil
    syncConflicts = []
    syncArchiveNeedsRestore = false
    syncError = nil
    do { try saveSyncState() } catch { syncError = error.localizedDescription }
  }

  func syncInstructions() async {
    guard let repository = syncState.repository, !isSyncing, !isSigningIn else { return }
    isSyncing = true
    syncError = nil
    syncArchiveNeedsRestore = false
    defer { isSyncing = false }
    do {
      let snapshot = try await syncRemote.fetch(repository: repository)
      // A missing archive or record is never interpreted as permission to delete local instructions.
      guard !snapshot.missingArchive,
        syncState.base.workspaces.allSatisfy({ snapshot.document.workspace(id: $0.id) != nil })
      else {
        syncArchiveNeedsRestore = true
        throw InstructionSyncError.message("The synced archive is incomplete. Your local files are safe. Restore the saved archive here to continue syncing.")
      }
      let local = localSyncDocument()
      let merge = InstructionSyncMerge.merge(base: syncState.base, local: local, cloud: snapshot.document)
      syncConflicts = merge.conflicts
      guard syncConflicts.isEmpty else { return }

      if merge.document != snapshot.document {
        try await syncRemote.push(merge.document, repository: repository, after: snapshot)
      }
      // Awaiting the network lets the editor run. Apply only to templates that still match
      // the captured local version, so an edit made during upload survives.
      let latest = localSyncDocument()
      for synced in merge.document.workspaces {
        guard latest.workspace(id: synced.id) == local.workspace(id: synced.id) else { continue }
        try applySyncedWorkspace(synced)
      }
      syncState.base = merge.document
      syncState.lastSyncedAt = Date()
      try saveSyncState()
      if latest != local { scheduleInstructionSync() }
    } catch {
      syncError = error.localizedDescription
    }
  }

  /// Restore missing records through the app. Present cloud records keep their current content.
  func restoreInstructionSyncArchive() async {
    guard let repository = syncState.repository, !isSyncing, syncArchiveNeedsRestore else { return }
    isSyncing = true
    syncError = nil
    do {
      let snapshot = try await syncRemote.fetch(repository: repository)
      var restored = snapshot.document
      for saved in syncState.base.workspaces + localSyncDocument().workspaces {
        if restored.workspace(id: saved.id) == nil { restored.workspaces.append(saved) }
      }
      restored.workspaces.sort { $0.id < $1.id }
      try await syncRemote.push(restored, repository: repository, after: snapshot)
      syncArchiveNeedsRestore = false
    } catch { syncError = error.localizedDescription }
    isSyncing = false
    if !syncArchiveNeedsRestore { await syncInstructions() }
  }

  /// Review uses a fresh local version and the exact cloud version shown in the sheet.
  /// Any subsequent cloud edit is compared against that version on the next sync.
  func resolveInstructionSyncConflict(_ conflict: InstructionSyncConflict, useCloud: Bool) async {
    guard !isSyncing else { return }
    do {
      guard localSyncDocument().workspace(id: conflict.id) == conflict.local else {
        await syncInstructions()
        return
      }
      if useCloud { try applySyncedWorkspace(conflict.cloud) }
      syncState.base.workspaces.removeAll { $0.id == conflict.id }
      syncState.base.workspaces.append(conflict.cloud)
      try saveSyncState()
      syncConflicts.removeAll { $0.id == conflict.id }
      await syncInstructions()
    } catch { syncError = error.localizedDescription }
  }
}
