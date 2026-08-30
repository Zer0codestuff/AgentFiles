import Foundation
import Observation

@MainActor
@Observable
final class AgentFilesStore {
  private(set) var configuration: AppConfiguration
  private(set) var snapshots: [UUID: FileSnapshot] = [:]
  private(set) var groupIssues: [UUID: SyncIssue] = [:]
  private(set) var lastSyncDates: [UUID: Date] = [:]

  var selectedGroupID: UUID?
  var selectedFileID: UUID?
  var notice: AppNotice?

  private let configurationStore: ConfigurationStore
  private let fileAccess: FileAccessService
  private let backupService: BackupService
  private let strategyResolver: SynchronizationStrategyResolver
  private let synchronizationEngine: SynchronizationEngine
  private let observationService: FileObservationService

  private var refreshTasks: [UUID: Task<Void, Never>] = [:]
  private var hasStarted = false

  init(
    configurationStore: ConfigurationStore = ConfigurationStore(),
    fileAccess: FileAccessService = FileAccessService(),
    backupService: BackupService = BackupService(),
    strategyResolver: SynchronizationStrategyResolver = SynchronizationStrategyResolver(),
    synchronizationEngine: SynchronizationEngine = SynchronizationEngine(),
    observationService: FileObservationService = FileObservationService()
  ) {
    self.configurationStore = configurationStore
    self.fileAccess = fileAccess
    self.backupService = backupService
    self.strategyResolver = strategyResolver
    self.synchronizationEngine = synchronizationEngine
    self.observationService = observationService

    do {
      configuration = try configurationStore.load()
    } catch {
      configuration = AppConfiguration()
      notice = AppNotice(
        title: "Configuration could not be loaded",
        message: error.localizedDescription
      )
    }

    selectedGroupID = configuration.groups.first?.id
    selectedFileID = configuration.groups.first?.files.first?.id
  }

  var groups: [SyncGroup] {
    configuration.groups
  }

  var automaticSyncEnabled: Bool {
    configuration.automaticSyncEnabled
  }

  var managedFileCount: Int {
    configuration.groups.reduce(0) { $0 + $1.files.count }
  }

  var hasBlockingIssue: Bool {
    groupIssues.values.contains { $0.kind == .conflict || $0.kind == .fileError }
  }

  func start() {
    guard !hasStarted else {
      return
    }
    hasStarted = true

    for group in configuration.groups {
      for file in group.files {
        refreshSnapshot(for: file)
        beginWatching(file)
      }
      markDifferentContentsIfNeeded(groupID: group.id)
    }
  }

  func group(id: UUID?) -> SyncGroup? {
    guard let id else {
      return nil
    }
    return configuration.groups.first { $0.id == id }
  }

  func file(id: UUID?) -> ManagedInstructionFile? {
    guard let id else {
      return nil
    }
    return configuration.groups.lazy.flatMap(\.files).first { $0.id == id }
  }

  func group(containing fileID: UUID) -> SyncGroup? {
    configuration.groups.first { group in
      group.files.contains { $0.id == fileID }
    }
  }

  func snapshot(for fileID: UUID) -> FileSnapshot? {
    snapshots[fileID]
  }

  func selectGroup(_ groupID: UUID?) {
    selectedGroupID = groupID
    guard let group = group(id: groupID) else {
      selectedFileID = nil
      return
    }

    if !group.files.contains(where: { $0.id == selectedFileID }) {
      selectedFileID = group.files.first?.id
    }
  }

  func selectFile(_ fileID: UUID?) {
    selectedFileID = fileID
    if let fileID, let group = group(containing: fileID) {
      selectedGroupID = group.id
    }
  }

  func issue(for groupID: UUID) -> SyncIssue? {
    groupIssues[groupID]
  }

  func state(for group: SyncGroup) -> GroupSyncState {
    if let issue = groupIssues[group.id] {
      switch issue.kind {
      case .conflict:
        return .conflict
      case .fileError:
        return .error
      case .differentContents:
        if !automaticSyncEnabled || !group.automaticSyncEnabled {
          return .disabled
        }
        return .needsSource
      }
    }

    if group.files.contains(where: { file in
      guard let snapshot = snapshots[file.id] else {
        return true
      }
      return snapshot.availability != .available
    }) {
      return .missingFiles
    }

    guard group.files.count >= 2 else {
      return .empty
    }

    if !automaticSyncEnabled || !group.automaticSyncEnabled {
      return .disabled
    }

    let digests = Set(group.files.compactMap { snapshots[$0.id]?.digest })
    return digests.count <= 1 ? .synchronized : .needsSource
  }

  @discardableResult
  func createGroup(named rawName: String) -> UUID? {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      notice = AppNotice(
        title: "Group name required",
        message: "Enter a name before creating the sync group."
      )
      return nil
    }

    let group = SyncGroup(name: name)
    configuration.groups.append(group)
    persistConfiguration()
    selectedGroupID = group.id
    selectedFileID = nil
    return group.id
  }

  func renameGroup(id: UUID, to rawName: String) {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, let index = indexOfGroup(id) else {
      return
    }
    configuration.groups[index].name = name
    persistConfiguration()
  }

  func removeGroup(id: UUID) {
    guard let index = indexOfGroup(id) else {
      return
    }

    let removedFiles = configuration.groups[index].files
    for file in removedFiles {
      refreshTasks[file.id]?.cancel()
      refreshTasks[file.id] = nil
      observationService.stopWatching(fileID: file.id)
      snapshots[file.id] = nil
    }

    configuration.groups.remove(at: index)
    groupIssues[id] = nil
    lastSyncDates[id] = nil
    persistConfiguration()

    if selectedGroupID == id {
      selectedGroupID = configuration.groups.first?.id
      selectedFileID = group(id: selectedGroupID)?.files.first?.id
    }
  }

  func addFiles(_ urls: [URL], to groupID: UUID) {
    guard let groupIndex = indexOfGroup(groupID) else {
      return
    }

    let existingPaths = Set(
      configuration.groups
        .flatMap(\.files)
        .map { $0.url.standardizedFileURL.path }
    )

    var addedFiles: [ManagedInstructionFile] = []
    var skippedNames: [String] = []
    var invalidNames: [String] = []

    for url in urls {
      let standardizedURL = url.standardizedFileURL
      guard !existingPaths.contains(standardizedURL.path),
        !addedFiles.contains(where: { $0.path == standardizedURL.path })
      else {
        skippedNames.append(standardizedURL.lastPathComponent)
        continue
      }

      do {
        _ = try fileAccess.read(standardizedURL)
        addedFiles.append(ManagedInstructionFile(url: standardizedURL))
      } catch {
        invalidNames.append(standardizedURL.lastPathComponent)
      }
    }

    configuration.groups[groupIndex].files.append(contentsOf: addedFiles)
    persistConfiguration()

    for file in addedFiles {
      refreshSnapshot(for: file)
      beginWatching(file)
    }

    if let firstAdded = addedFiles.first {
      selectedGroupID = groupID
      selectedFileID = firstAdded.id
    }

    markDifferentContentsIfNeeded(groupID: groupID)

    let messages = [
      skippedNames.isEmpty ? nil : "Already managed: \(skippedNames.joined(separator: ", ")).",
      invalidNames.isEmpty
        ? nil : "Not readable as UTF-8: \(invalidNames.joined(separator: ", ")).",
    ].compactMap { $0 }

    if !messages.isEmpty {
      notice = AppNotice(
        title: addedFiles.isEmpty ? "No files added" : "Some files were skipped",
        message: messages.joined(separator: "\n")
      )
    }
  }

  func removeFile(id fileID: UUID) {
    guard let group = group(containing: fileID),
      let groupIndex = indexOfGroup(group.id)
    else {
      return
    }

    configuration.groups[groupIndex].files.removeAll { $0.id == fileID }
    refreshTasks[fileID]?.cancel()
    refreshTasks[fileID] = nil
    observationService.stopWatching(fileID: fileID)
    snapshots[fileID] = nil
    persistConfiguration()

    if selectedFileID == fileID {
      selectedFileID = configuration.groups[groupIndex].files.first?.id
    }
    markDifferentContentsIfNeeded(groupID: group.id)
  }

  func setTool(_ tool: AgentTool, for fileID: UUID) {
    guard let location = locationOfFile(fileID) else {
      return
    }
    configuration.groups[location.groupIndex].files[location.fileIndex].tool = tool
    persistConfiguration()
  }

  func setAutomaticSyncEnabled(_ enabled: Bool) {
    configuration.automaticSyncEnabled = enabled
    persistConfiguration()

    if enabled {
      for group in configuration.groups {
        markDifferentContentsIfNeeded(groupID: group.id)
      }
    }
  }

  func setAutomaticSyncEnabled(_ enabled: Bool, for groupID: UUID) {
    guard let index = indexOfGroup(groupID) else {
      return
    }
    configuration.groups[index].automaticSyncEnabled = enabled
    persistConfiguration()

    if enabled {
      markDifferentContentsIfNeeded(groupID: groupID)
    }
  }

  @discardableResult
  func saveEditorContent(
    _ content: String,
    fileID: UUID,
    expectedDigest: String?,
    force: Bool = false
  ) -> Bool {
    guard let group = group(containing: fileID),
      let sourceFile = group.files.first(where: { $0.id == fileID })
    else {
      return false
    }

    if !force, groupIssues[group.id]?.kind == .conflict {
      notice = AppNotice(
        title: "Choose the source version",
        message: "Select the file to keep and use Sync from This File before saving more edits."
      )
      return false
    }

    do {
      let currentSource = try fileAccess.read(sourceFile.url)
      if let expectedDigest,
        currentSource.digest != expectedDigest,
        currentSource.content != content,
        !force
      {
        recordConflict(
          group: group,
          affectedFileIDs: [fileID],
          message: "\(sourceFile.displayName) changed on disk while it had unsaved edits."
        )
        return false
      }

      let shouldSync = automaticSyncEnabled && group.automaticSyncEnabled
      let plan =
        try shouldSync
        ? preparePlan(
          sourceFileID: fileID,
          sourceContent: content,
          group: group,
          allowConcurrentOverwrite: force
        )
        : SyncPlan(sourceFileID: fileID, operations: [])

      var writes = plan.operations
      if currentSource.content != content {
        writes.insert(
          SyncWriteOperation(fileID: fileID, content: content),
          at: 0
        )
      }

      try apply(writes: writes, in: group)
      groupIssues[group.id] = nil
      lastSyncDates[group.id] = Date()
      return true
    } catch let error as SyncPlanningError {
      handlePlanningError(error, sourceFileID: fileID, group: group)
      return false
    } catch {
      recordFileError(
        group: group,
        affectedFileIDs: [fileID],
        message: error.localizedDescription
      )
      return false
    }
  }

  func synchronizeFrom(fileID: UUID, force: Bool = true) {
    guard let group = group(containing: fileID),
      let sourceFile = group.files.first(where: { $0.id == fileID })
    else {
      return
    }

    do {
      let sourceSnapshot = try fileAccess.read(sourceFile.url)
      setSnapshot(sourceSnapshot, for: sourceFile)
      let plan = try preparePlan(
        sourceFileID: fileID,
        sourceContent: sourceSnapshot.content,
        group: group,
        allowConcurrentOverwrite: force
      )
      try apply(writes: plan.operations, in: group)
      groupIssues[group.id] = nil
      lastSyncDates[group.id] = Date()
    } catch let error as SyncPlanningError {
      handlePlanningError(error, sourceFileID: fileID, group: group)
    } catch {
      recordFileError(
        group: group,
        affectedFileIDs: [fileID],
        message: error.localizedDescription
      )
    }
  }

  func synchronizeAllSafeGroups() {
    var skippedGroups: [String] = []

    for group in configuration.groups where group.files.count >= 2 {
      if groupIssues[group.id] != nil {
        skippedGroups.append(group.name)
        continue
      }

      let source = group.files.max { lhs, rhs in
        let leftDate = snapshots[lhs.id]?.modificationDate ?? .distantPast
        let rightDate = snapshots[rhs.id]?.modificationDate ?? .distantPast
        return leftDate < rightDate
      }

      if let source {
        synchronizeFrom(fileID: source.id, force: false)
      }
    }

    if !skippedGroups.isEmpty {
      notice = AppNotice(
        title: "Some groups need attention",
        message: "Choose a source file in: \(skippedGroups.joined(separator: ", "))."
      )
    }
  }

  func reload(fileID: UUID) {
    guard let file = file(id: fileID) else {
      return
    }
    refreshSnapshot(for: file)
  }

  private func beginWatching(_ file: ManagedInstructionFile) {
    do {
      try observationService.watch(file: file) { [weak self] fileID in
        self?.scheduleRefresh(fileID: fileID)
      }
    } catch {
      if let group = group(containing: file.id) {
        recordFileError(
          group: group,
          affectedFileIDs: [file.id],
          message: error.localizedDescription
        )
      }
    }
  }

  private func scheduleRefresh(fileID: UUID) {
    refreshTasks[fileID]?.cancel()
    refreshTasks[fileID] = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else {
        return
      }
      self?.handleDiskChange(fileID: fileID)
    }
  }

  private func handleDiskChange(fileID: UUID) {
    guard let file = file(id: fileID),
      let group = group(containing: fileID)
    else {
      return
    }

    do {
      let diskSnapshot = try fileAccess.read(file.url)
      let previousDigest = snapshots[fileID]?.digest
      guard previousDigest != diskSnapshot.digest else {
        return
      }

      setSnapshot(diskSnapshot, for: file)

      guard automaticSyncEnabled, group.automaticSyncEnabled else {
        markDifferentContentsIfNeeded(groupID: group.id)
        return
      }

      if let issue = groupIssues[group.id],
        issue.kind == .conflict || issue.kind == .differentContents
      {
        markDifferentContentsIfNeeded(groupID: group.id)
        return
      }

      let plan = try preparePlan(
        sourceFileID: fileID,
        sourceContent: diskSnapshot.content,
        group: group,
        allowConcurrentOverwrite: false
      )
      try apply(writes: plan.operations, in: group)
      groupIssues[group.id] = nil
      lastSyncDates[group.id] = Date()
    } catch let error as SyncPlanningError {
      handlePlanningError(error, sourceFileID: fileID, group: group)
    } catch {
      recordFileError(
        group: group,
        affectedFileIDs: [fileID],
        message: error.localizedDescription
      )
    }
  }

  private func preparePlan(
    sourceFileID: UUID,
    sourceContent: String,
    group: SyncGroup,
    allowConcurrentOverwrite: Bool
  ) throws -> SyncPlan {
    var targets: [SyncTargetState] = []

    for target in group.files where target.id != sourceFileID {
      let baselineDigest = snapshots[target.id]?.digest
      let current = try fileAccess.read(target.url)
      setSnapshot(current, for: target)
      targets.append(
        SyncTargetState(
          fileID: target.id,
          currentContent: current.content,
          baselineDigest: baselineDigest
        )
      )
    }

    let strategy = strategyResolver.strategy(for: group.synchronizationMode)
    return try synchronizationEngine.makePlan(
      sourceFileID: sourceFileID,
      sourceContent: sourceContent,
      targets: targets,
      strategy: strategy,
      allowConcurrentOverwrite: allowConcurrentOverwrite
    )
  }

  private func apply(
    writes: [SyncWriteOperation],
    in group: SyncGroup
  ) throws {
    guard !writes.isEmpty else {
      return
    }

    let fileByID = Dictionary(uniqueKeysWithValues: group.files.map { ($0.id, $0) })
    let resolvedWrites = try writes.map { operation -> (ManagedInstructionFile, String) in
      guard let file = fileByID[operation.fileID] else {
        throw CocoaError(.fileNoSuchFile)
      }
      return (file, operation.content)
    }

    for (file, _) in resolvedWrites {
      try backupService.backup(file: file, groupID: group.id)
    }

    for (file, content) in resolvedWrites {
      let writtenSnapshot = try fileAccess.write(content, to: file.url)
      setSnapshot(writtenSnapshot, for: file)
    }
  }

  private func refreshSnapshot(for file: ManagedInstructionFile) {
    do {
      setSnapshot(try fileAccess.read(file.url), for: file)
    } catch let error as FileAccessError {
      let revision = (snapshots[file.id]?.revision ?? 0) + 1
      switch error {
      case .missing:
        snapshots[file.id] = .missing(revision: revision)
      case .notUTF8:
        snapshots[file.id] = FileSnapshot(
          content: nil,
          digest: nil,
          modificationDate: nil,
          availability: .unreadable(error.localizedDescription),
          revision: revision
        )
      }
    } catch {
      snapshots[file.id] = FileSnapshot(
        content: nil,
        digest: nil,
        modificationDate: nil,
        availability: .unreadable(error.localizedDescription),
        revision: (snapshots[file.id]?.revision ?? 0) + 1
      )
    }
  }

  private func setSnapshot(
    _ diskSnapshot: DiskFileSnapshot,
    for file: ManagedInstructionFile
  ) {
    let previous = snapshots[file.id]
    let changed =
      previous?.digest != diskSnapshot.digest
      || previous?.availability != .available
    let revision = (previous?.revision ?? 0) + (changed ? 1 : 0)

    snapshots[file.id] = FileSnapshot(
      content: diskSnapshot.content,
      digest: diskSnapshot.digest,
      modificationDate: diskSnapshot.modificationDate,
      availability: .available,
      revision: revision
    )
  }

  private func markDifferentContentsIfNeeded(groupID: UUID) {
    guard let group = group(id: groupID) else {
      return
    }

    let unavailableFiles = group.files.filter { file in
      snapshots[file.id]?.availability != .available
    }
    if !unavailableFiles.isEmpty {
      groupIssues[groupID] = SyncIssue(
        groupID: groupID,
        kind: .fileError,
        title: "File unavailable",
        message: "Restore or remove unavailable files before synchronizing.",
        affectedFileIDs: unavailableFiles.map(\.id)
      )
      return
    }

    let digests = Set(group.files.compactMap { snapshots[$0.id]?.digest })
    if group.files.count >= 2, digests.count > 1 {
      if groupIssues[groupID]?.kind != .conflict {
        groupIssues[groupID] = SyncIssue(
          groupID: groupID,
          kind: .differentContents,
          title: "Choose a source file",
          message: "The files differ. Select the version to copy, then use Sync from This File.",
          affectedFileIDs: group.files.map(\.id)
        )
      }
    } else if groupIssues[groupID]?.kind == .differentContents {
      groupIssues[groupID] = nil
    }
  }

  private func handlePlanningError(
    _ error: SyncPlanningError,
    sourceFileID: UUID,
    group: SyncGroup
  ) {
    switch error {
    case .concurrentChanges(let fileIDs):
      let affected = [sourceFileID] + fileIDs
      recordConflict(
        group: group,
        affectedFileIDs: affected,
        message:
          "Several files changed before Agent Files could synchronize them. Select the version to keep."
      )
    }
  }

  private func recordConflict(
    group: SyncGroup,
    affectedFileIDs: [UUID],
    message: String
  ) {
    groupIssues[group.id] = SyncIssue(
      groupID: group.id,
      kind: .conflict,
      title: "Sync paused",
      message: message,
      affectedFileIDs: affectedFileIDs
    )
    notice = AppNotice(title: "Sync paused", message: message)
  }

  private func recordFileError(
    group: SyncGroup,
    affectedFileIDs: [UUID],
    message: String
  ) {
    groupIssues[group.id] = SyncIssue(
      groupID: group.id,
      kind: .fileError,
      title: "File error",
      message: message,
      affectedFileIDs: affectedFileIDs
    )
    notice = AppNotice(title: "File error", message: message)
  }

  private func persistConfiguration() {
    do {
      try configurationStore.save(configuration)
    } catch {
      notice = AppNotice(
        title: "Configuration could not be saved",
        message: error.localizedDescription
      )
    }
  }

  private func indexOfGroup(_ id: UUID) -> Int? {
    configuration.groups.firstIndex { $0.id == id }
  }

  private func locationOfFile(_ id: UUID) -> (groupIndex: Int, fileIndex: Int)? {
    for groupIndex in configuration.groups.indices {
      if let fileIndex = configuration.groups[groupIndex].files.firstIndex(where: {
        $0.id == id
      }) {
        return (groupIndex, fileIndex)
      }
    }
    return nil
  }
}
