import Foundation
import Observation

@MainActor
@Observable
final class AgentFilesStore {
  private(set) var configuration: AppConfiguration
  private(set) var templates: [UUID: InstructionTemplate] = [:]
  private(set) var files: [String: FileAvailability] = [:]

  var selection: SidebarItem?
  var notice: AppNotice?

  var syncState: InstructionSyncState
  var syncConflicts: [InstructionSyncConflict] = []
  var syncError: String?
  var syncArchiveNeedsRestore = false
  var isSyncing = false
  var isSigningIn = false
  var syncSignInCode: String?
  var showsSync = false
  let syncRemote: any InstructionSyncRemote
  let syncStateStore: InstructionSyncStateStore
  var syncTimerTask: Task<Void, Never>?
  var syncDebounceTask: Task<Void, Never>?

  // Skill state is written by AgentFilesStore+Skills.swift.
  var skillLocations: [SkillLocation] = []
  var skills: [SkillRecord] = []
  var skillConflicts: Set<String> = []
  var isScanningSkills = false
  var isApplyingSkillSync = false
  var selectedSkillName: String?

  private let configurationStore: ConfigurationStore
  private let templateStore: TemplateStore
  private let fileAccess: FileAccessService
  private let backupService: BackupService
  private let observationService = FileObservationService()
  let skillLibrary: SkillLibraryService
  let homeDirectory: URL

  var skillWatcher: RecursiveDirectoryWatcher?
  var skillScanTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var hasStarted = false

  init(
    configurationStore: ConfigurationStore = ConfigurationStore(),
    templateStore: TemplateStore = TemplateStore(),
    fileAccess: FileAccessService = FileAccessService(),
    backupService: BackupService = BackupService(),
    skillLibrary: SkillLibraryService = SkillLibraryService(),
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    syncRemote: any InstructionSyncRemote = GitHubInstructionSync()
  ) {
    self.configurationStore = configurationStore
    self.templateStore = templateStore
    self.fileAccess = fileAccess
    self.backupService = backupService
    self.skillLibrary = skillLibrary
    self.homeDirectory = homeDirectory
    self.syncRemote = syncRemote
    syncStateStore = InstructionSyncStateStore(
      fileURL: configurationStore.fileURL.deletingLastPathComponent()
        .appendingPathComponent("instruction-sync.json")
    )
    do {
      syncState = try syncStateStore.load()
    } catch {
      syncState = .init()
      syncError = "Sync settings could not be loaded: \(error.localizedDescription)"
    }
    skillLocations = SkillLocation.defaultLocations(home: homeDirectory)

    do {
      configuration = try configurationStore.load()
    } catch {
      configuration = AppConfiguration()
      notice = AppNotice(
        title: "Configuration could not be loaded",
        message: error.localizedDescription
      )
    }

    ensureGlobalWorkspace()
    for workspace in configuration.workspaces {
      templates[workspace.id] = try? templateStore.load(workspaceID: workspace.id)
    }
    selection = globalWorkspace.map { .workspace($0.id) }
    refreshFiles()
  }

  // MARK: Queries

  var workspaces: [Workspace] {
    configuration.workspaces
  }

  var globalWorkspace: Workspace? {
    configuration.workspaces.first { $0.kind == .global }
  }

  var projects: [Workspace] {
    configuration.workspaces.filter { $0.kind == .project }
  }

  var installedHarnesses: [AgentTool] {
    AgentTool.harnesses.filter { $0.isInstalled(in: homeDirectory) }
  }

  func workspace(id: UUID?) -> Workspace? {
    configuration.workspaces.first { $0.id == id }
  }

  func template(for workspaceID: UUID) -> InstructionTemplate? {
    templates[workspaceID]
  }

  func content(of target: WorkspaceTarget) -> String? {
    files[target.path]?.content
  }

  func status(of target: WorkspaceTarget, in workspace: Workspace) -> TargetStatus {
    guard target.writesFile else {
      return .copyOnly
    }
    switch files[target.path] {
    case .available(let content):
      guard let template = templates[workspace.id] else {
        return .synced
      }
      return content == template.render(for: target.key) ? .synced : .changedOutside
    case .missing, nil:
      return .willBeCreated
    case .unreadable(let message):
      return .unreadable(message)
    }
  }

  func needsAttention(_ workspace: Workspace) -> Bool {
    guard templates[workspace.id] != nil else {
      return false
    }
    return workspace.targets.contains { status(of: $0, in: workspace) == .changedOutside }
  }

  // MARK: Lifecycle

  func start() {
    guard !hasStarted else {
      return
    }
    hasStarted = true
    refreshFiles()
    watchFiles()
    startSkillLibrary()
    startInstructionSync()
  }

  func refreshFiles() {
    var updated: [String: FileAvailability] = [:]
    for target in configuration.workspaces.flatMap(\.targets) where target.writesFile {
      updated[target.path] = read(target.url)
    }
    if updated != files {
      files = updated
    }
  }

  private func read(_ url: URL) -> FileAvailability {
    do {
      return .available(try fileAccess.read(url).content)
    } catch FileAccessError.missing {
      return .missing
    } catch {
      return .unreadable(error.localizedDescription)
    }
  }

  private func watchFiles() {
    let targets = configuration.workspaces.flatMap(\.targets).filter(\.writesFile)
    let directories = Set(
      targets.map { $0.url.deletingLastPathComponent().path }
        .filter { FileManager.default.fileExists(atPath: $0) }
    )
    let existingFiles = Set(
      targets.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
    )
    observationService.watch(directories: directories, files: existingFiles) { [weak self] in
      self?.scheduleRefresh()
    }
  }

  private func scheduleRefresh() {
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else {
        return
      }
      self?.refreshFiles()
      self?.watchFiles()
    }
  }

  // MARK: Workspaces

  func addProject(at folder: URL) {
    let root = folder.standardizedFileURL.path
    if let existing = projects.first(where: { $0.rootPath == root }) {
      selection = .workspace(existing.id)
      return
    }

    let managedPaths = Set(
      configuration.workspaces.flatMap(\.targets).filter(\.writesFile).map(\.path)
    )
    let workspace = Workspace.project(at: folder)
    if let shared = workspace.targets.first(where: { managedPaths.contains($0.path) }) {
      notice = AppNotice(
        title: "Already managed",
        message: "\(shared.path) already belongs to another workspace."
      )
      return
    }

    configuration.workspaces.append(workspace)
    persistConfiguration()
    refreshFiles()
    watchFiles()
    selection = .workspace(workspace.id)
  }

  func removeProject(id: UUID) {
    guard workspace(id: id)?.kind == .project else {
      return
    }
    configuration.workspaces.removeAll { $0.id == id }
    templates[id] = nil
    templateStore.remove(workspaceID: id)
    persistConfiguration()
    refreshFiles()
    watchFiles()
    if selection == .workspace(id) {
      selection = globalWorkspace.map { .workspace($0.id) }
    }
  }

  /// Creates the Global workspace and adds agents installed since the last launch.
  private func ensureGlobalWorkspace() {
    let detected = Workspace.globalTargets(home: homeDirectory)
    if let index = configuration.workspaces.firstIndex(where: { $0.kind == .global }) {
      let known = Set(configuration.workspaces[index].keys)
      let added = detected.filter { !known.contains($0.key) }
      guard !added.isEmpty else {
        return
      }
      configuration.workspaces[index].targets += added
    } else {
      var global = Workspace.global(home: homeDirectory)
      global.targets = detected
      configuration.workspaces.insert(global, at: 0)
    }
    persistConfiguration()
  }

  // MARK: Editing

  /// Creates the workspace template from the existing files. The base file becomes the
  /// shared text, and each other file keeps its differences as file-specific lines.
  func setUp(workspaceID: UUID, baseKey: String?) {
    guard let workspace = workspace(id: workspaceID) else {
      return
    }
    refreshFiles()

    let base = workspace.target(key: baseKey).flatMap { content(of: $0) } ?? ""
    let others = workspace.targets
      .filter { $0.key != baseKey }
      .compactMap { target in content(of: target).map { (key: target.key, content: $0) } }
    let template = InstructionTemplate.importing(base: base, others: others)
      .pruned(keys: templateKeys(for: workspace))
    commit(template, to: workspace, previous: nil)
  }

  /// Saves an edited copy of one file. Shared edits reach every file that has those lines.
  @discardableResult
  func save(
    _ content: String,
    for key: String,
    in workspaceID: UUID,
    scope: EditScope
  ) -> Bool {
    guard let workspace = workspace(id: workspaceID),
      let target = workspace.target(key: key),
      let template = templates[workspaceID]
    else {
      return false
    }

    refreshFiles()
    guard status(of: target, in: workspace) != .changedOutside else {
      notice = AppNotice(
        title: "Review the outside change first",
        message:
          "\(target.title) changed outside Agent Files. Keep or discard that change before saving."
      )
      return false
    }

    let updated = template.applying(edited: content, from: key, scope: scope)
      .pruned(keys: templateKeys(for: workspace))
    return commit(updated, to: workspace, previous: template)
  }

  /// Brings an edit made in another app into the template.
  func acceptOutsideChange(key: String, in workspaceID: UUID, scope: EditScope) {
    guard let workspace = workspace(id: workspaceID),
      let target = workspace.target(key: key),
      let template = templates[workspaceID],
      let content = read(target.url).content
    else {
      return
    }

    let updated = template.applying(edited: content, from: key, scope: scope)
      .pruned(keys: templateKeys(for: workspace))
    commit(updated, to: workspace, previous: template)
  }

  /// Restores a file changed in another app to the template version, after a backup.
  func discardOutsideChange(key: String, in workspaceID: UUID) {
    guard let workspace = workspace(id: workspaceID),
      let target = workspace.target(key: key),
      let template = templates[workspaceID]
    else {
      return
    }

    do {
      try backupService.backup(fileAt: target.url, workspaceID: workspaceID, key: key)
      _ = try fileAccess.write(template.render(for: key), to: target.url)
    } catch {
      notice = AppNotice(title: "File could not be restored", message: error.localizedDescription)
    }
    refreshFiles()
  }

  /// Uses one version of a difference for every file.
  func resolve(_ variation: TemplateVariation, with lines: [String], in workspaceID: UUID) {
    guard let workspace = workspace(id: workspaceID),
      let template = templates[workspaceID]
    else {
      return
    }
    let updated = template.resolving(variation, with: lines).pruned(keys: templateKeys(for: workspace))
    commit(updated, to: workspace, previous: template)
  }

  /// Saves the template and writes every file that still matches the previous version.
  /// Files changed in another app are left untouched until the user reviews them.
  @discardableResult
  private func commit(
    _ template: InstructionTemplate,
    to workspace: Workspace,
    previous: InstructionTemplate?
  ) -> Bool {
    do {
      try templateStore.save(template, workspaceID: workspace.id)
    } catch {
      notice = AppNotice(title: "Template could not be saved", message: error.localizedDescription)
      return false
    }
    templates[workspace.id] = template

    var skipped: [String] = []
    var failures: [String] = []

    for target in workspace.targets where target.writesFile {
      let desired = template.render(for: target.key)
      do {
        switch read(target.url) {
        case .missing:
          try FileManager.default.createDirectory(
            at: target.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          _ = try fileAccess.write(desired, to: target.url)
        case .available(let current):
          guard current != desired else {
            continue
          }
          guard current == previous?.render(for: target.key) else {
            skipped.append(target.title)
            continue
          }
          try backupService.backup(fileAt: target.url, workspaceID: workspace.id, key: target.key)
          _ = try fileAccess.write(desired, to: target.url)
        case .unreadable:
          skipped.append(target.title)
        }
      } catch {
        failures.append("\(target.title): \(error.localizedDescription)")
      }
    }

    refreshFiles()
    watchFiles()

    scheduleInstructionSync()

    if !failures.isEmpty {
      notice = AppNotice(
        title: "Some files could not be written",
        message: failures.joined(separator: "\n")
      )
    } else if !skipped.isEmpty {
      notice = AppNotice(
        title: "Some files were not updated",
        message:
          "\(skipped.joined(separator: ", ")) changed outside Agent Files. Review them to keep or discard those changes."
      )
    }
    return failures.isEmpty
  }

  // MARK: Persistence

  func updateTrackedSkills(_ update: (inout [TrackedSkill]) -> Void) {
    update(&configuration.trackedSkills)
    persistConfiguration()
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

  /// Keep variants for agents installed on other computers when pruning shared templates.
  private func templateKeys(for workspace: Workspace) -> [String] {
    workspace.kind == .global ? AgentTool.harnesses.map(\.templateKey) : workspace.keys
  }

  func localSyncDocument() -> InstructionSyncDocument {
    InstructionSyncDocument(workspaces: workspaces.compactMap { workspace in
      guard let template = templates[workspace.id] else { return nil }
      let id = workspace.kind == .global ? "global"
        : syncState.projectBindings.first(where: { $0.value == workspace.id })?.key
          ?? workspace.id.uuidString
      return SyncedWorkspace(id: id, name: workspace.name, kind: workspace.kind,
        keys: templateKeys(for: workspace).sorted(), template: template.text)
    }.sorted { $0.id < $1.id })
  }

  /// Import existing instructions for sync without creating or changing any managed files.
  func prepareInstructionsForSync() throws {
    refreshFiles()
    for workspace in workspaces where templates[workspace.id] == nil && !workspace.targets.isEmpty {
      let available = workspace.targets.compactMap { target in
        content(of: target).map { (key: target.key, content: $0) }
      }
      guard let first = available.first else { continue }
      let template = InstructionTemplate.importing(base: first.content, others: Array(available.dropFirst()))
        .pruned(keys: templateKeys(for: workspace))
      try templateStore.save(template, workspaceID: workspace.id)
      templates[workspace.id] = template
    }
  }

  func localWorkspace(for synced: SyncedWorkspace) -> Workspace? {
    if synced.kind == .global { return globalWorkspace }
    return workspace(id: syncState.projectBindings[synced.id] ?? UUID(uuidString: synced.id))
  }

  @discardableResult
  func applySyncedWorkspace(_ synced: SyncedWorkspace) throws -> Bool {
    guard let workspace = localWorkspace(for: synced) else { return false }
    let incoming = synced.instructions
    let previous = templates[workspace.id]
    let hasMissingFiles = workspace.targets.contains { $0.writesFile && read($0.url) == .missing }
    guard previous != incoming || hasMissingFiles else { return true }
    // A local template also needs a backup, including copy-only variants.
    if previous != incoming {
      try backupService.backup(
        fileAt: templateStore.directory.appendingPathComponent("\(workspace.id.uuidString).md"),
        workspaceID: workspace.id, key: "template"
      )
    }
    guard commit(incoming, to: workspace, previous: previous) else {
      throw InstructionSyncError.message("Some instruction files could not be updated. Fix the file access error and sync again.")
    }
    return true
  }

  /// A synced project is mapped explicitly because its location differs on each computer.
  func linkSyncedProject(_ synced: SyncedWorkspace, at folder: URL) {
    guard !isSyncing, synced.kind == .project else { return }
    addProject(at: folder)
    guard let project = projects.first(where: { $0.rootPath == folder.standardizedFileURL.path }) else { return }
    if syncState.projectBindings.contains(where: { $0.value == project.id && $0.key != synced.id }) {
      syncError = "This folder is already connected to another synced project."
      return
    }
    // Preserve existing local instructions. Different content becomes a sync conflict.
    do {
      try prepareInstructionsForSync()
      syncState.projectBindings[synced.id] = project.id
      if let index = configuration.workspaces.firstIndex(where: { $0.id == project.id }) {
        configuration.workspaces[index].name = synced.name
        persistConfiguration()
      }
      // First linking is an import, even if this computer has already seen the cloud record.
      syncState.base.workspaces.removeAll { $0.id == synced.id }
      try saveSyncState()
      Task { await syncInstructions() }
    } catch { syncError = error.localizedDescription }
  }
}
