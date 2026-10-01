import Foundation
import Testing
@testable import AgentFiles

@MainActor
struct InstructionSyncTests {
  @Test
  func independentWorkspaceEditsMergeAndConcurrentEditsNeedReview() {
    let projectID = UUID().uuidString
    let global = record("global", "base")
    let project = record(projectID, "project base")
    let base = document(global, project)
    let merged = InstructionSyncMerge.merge(base: base,
      local: document(record("global", "local"), project),
      cloud: document(global, record(projectID, "remote")))
    #expect(merged.conflicts.isEmpty)
    #expect(merged.document.workspace(id: "global")?.template == "local")
    #expect(merged.document.workspace(id: projectID)?.template == "remote")

    let conflict = InstructionSyncMerge.merge(base: document(global),
      local: document(record("global", "local")), cloud: document(record("global", "remote")))
    #expect(conflict.conflicts.count == 1)
    #expect(conflict.conflicts.first?.local.template == "local")
    #expect(conflict.conflicts.first?.cloud.template == "remote")
  }

  @Test
  func firstConnectionWithDifferentInstructionsNeedsReview() {
    let merge = InstructionSyncMerge.merge(base: .init(),
      local: document(record("global", "first computer")),
      cloud: document(record("global", "other computer")))
    #expect(merge.conflicts.count == 1)
  }

  @Test
  func archiveContainsPlainMarkdownWithoutPathsOrSkills() throws {
    let archive = document(SyncedWorkspace(id: "global", name: "Global", kind: .global,
      keys: ["codex", "claude"], template: "shared\n<!-- only: codex -->\ncodex only\n<!-- end -->"))
    let files = try archive.repositoryFiles()
    #expect(files["instructions/global/codex/AGENTS.md"] == "shared\ncodex only")
    #expect(files["instructions/global/claude/CLAUDE.md"] == "shared")
    let json = try #require(files["agent-files.json"])
    #expect(!json.contains("rootPath"))
    #expect(!json.contains("trackedSkills"))
    #expect(!json.contains("/Users/"))
    #expect(throws: InstructionSyncError.self) {
      try document(SyncedWorkspace(id: "../../escape", name: "Invalid", kind: .project,
        keys: ["agents"], template: "test")).validated()
    }
    #expect(throws: InstructionSyncError.self) {
      try document(record("global", "a"), record("global", "b")).validated()
    }
  }

  @Test
  func twoComputersSyncAndResolveConflictsInsideTheApp() async throws {
    let remote = MemoryInstructionRemote()
    let first = try SyncFixture()
    let second = try SyncFixture()
    defer { first.remove(); second.remove() }
    let a = first.makeStore(remote: remote)
    let b = second.makeStore(remote: remote)
    await a.connectInstructionSync()
    await b.connectInstructionSync()
    #expect(a.syncError == nil)
    #expect(b.syncError == nil)
    let aid = try #require(a.globalWorkspace?.id)
    let bid = try #require(b.globalWorkspace?.id)
    a.save("shared\nfrom first\n", for: "codex", in: aid, scope: .shared)
    await a.syncInstructions()
    await b.syncInstructions()
    #expect(try second.read(".codex/AGENTS.md") == "shared\nfrom first\n")

    a.save("shared\nfirst choice\n", for: "codex", in: aid, scope: .shared)
    b.save("shared\nsecond choice\n", for: "codex", in: bid, scope: .shared)
    await a.syncInstructions()
    await b.syncInstructions()
    let conflict = try #require(b.syncConflicts.first)
    #expect(try second.read(".codex/AGENTS.md") == "shared\nsecond choice\n")
    await b.resolveInstructionSyncConflict(conflict, useCloud: true)
    #expect(b.syncConflicts.isEmpty)
    #expect(try second.read(".codex/AGENTS.md") == "shared\nfirst choice\n")
    #expect(FileManager.default.fileExists(atPath: second.backups.path))
  }

  @Test
  func keepingLocalConflictUpdatesOtherComputer() async throws {
    let remote = MemoryInstructionRemote()
    let first = try SyncFixture()
    let second = try SyncFixture()
    defer { first.remove(); second.remove() }
    let a = first.makeStore(remote: remote)
    let b = second.makeStore(remote: remote)
    await a.connectInstructionSync()
    await b.connectInstructionSync()
    a.save("first\n", for: "codex", in: a.globalWorkspace!.id, scope: .shared)
    b.save("second\n", for: "codex", in: b.globalWorkspace!.id, scope: .shared)
    await a.syncInstructions()
    await b.syncInstructions()
    await b.resolveInstructionSyncConflict(try #require(b.syncConflicts.first), useCloud: false)
    await a.syncInstructions()
    #expect(try first.read(".codex/AGENTS.md") == "second\n")
    #expect(b.syncConflicts.isEmpty)
  }

  @Test
  func remoteUpdatePreservesAnOutsideEdit() async throws {
    let remote = MemoryInstructionRemote()
    let first = try SyncFixture()
    let second = try SyncFixture()
    defer { first.remove(); second.remove() }
    let a = first.makeStore(remote: remote)
    let b = second.makeStore(remote: remote)
    await a.connectInstructionSync()
    await b.connectInstructionSync()
    try second.write("outside edit\n", to: ".codex/AGENTS.md")
    a.save("cloud edit\n", for: "codex", in: a.globalWorkspace!.id, scope: .shared)
    await a.syncInstructions()
    await b.syncInstructions()
    #expect(try second.read(".codex/AGENTS.md") == "outside edit\n")
    #expect(b.needsAttention(b.globalWorkspace!))
    #expect(b.template(for: b.globalWorkspace!.id)?.render(for: "codex") == "cloud edit\n")
  }

  @Test
  func offlineEditsAndFailedConcurrentUploadsKeepTheirBase() async throws {
    let remote = MemoryInstructionRemote()
    let fixture = try SyncFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore(remote: remote)
    await store.connectInstructionSync()
    let base = store.syncState.base
    store.save("offline edit\n", for: "codex", in: store.globalWorkspace!.id, scope: .shared)
    await remote.setFailure(.concurrentUpdate)
    await store.syncInstructions()
    #expect(store.syncState.base == base)
    #expect(store.syncError != nil)
    #expect(try fixture.read(".codex/AGENTS.md") == "offline edit\n")
    await remote.setFailure(nil)
    await store.syncInstructions()
    #expect(store.syncError == nil)
    #expect(await remote.current().workspace(id: "global")?.instructions.render(for: "codex") == "offline edit\n")
    let relaunched = fixture.makeStore(remote: remote)
    #expect(relaunched.syncState == store.syncState)
  }

  @Test
  func editsMadeDuringUploadSurvive() async throws {
    let remote = MemoryInstructionRemote()
    let fixture = try SyncFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore(remote: remote)
    await store.connectInstructionSync()
    let id = store.globalWorkspace!.id
    store.save("uploading\n", for: "codex", in: id, scope: .shared)
    await remote.setUploadDelay(true)
    let upload = Task { await store.syncInstructions() }
    while !(await remote.isWaiting()) { await Task.yield() }
    store.save("newer edit\n", for: "codex", in: id, scope: .shared)
    await remote.releaseUpload()
    await upload.value
    #expect(try fixture.read(".codex/AGENTS.md") == "newer edit\n")
    #expect(store.syncState.base.workspace(id: "global")?.instructions.render(for: "codex") == "uploading\n")
    await store.syncInstructions()
    #expect(await remote.current().workspace(id: "global")?.instructions.render(for: "codex") == "newer edit\n")
  }

  @Test
  func globalEditsPreserveVariantsForAgentsOnAnotherComputer() async throws {
    let remote = MemoryInstructionRemote()
    let fixture = try SyncFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore(remote: remote)
    await store.connectInstructionSync()
    var cloud = await remote.current()
    cloud.workspaces[0].template = cloud.workspaces[0].instructions
      .applying(edited: "cursor only\n", from: "cursor", scope: .only("cursor")).text
    await remote.replace(cloud)
    await store.syncInstructions()
    store.save("shared\nnew shared line\n", for: "codex", in: store.globalWorkspace!.id, scope: .shared)
    #expect(store.template(for: store.globalWorkspace!.id)?.render(for: "cursor").contains("cursor only") == true)
  }

  @Test
  func linkingAnExistingFolderReviewsDifferencesAndRemovalKeepsCloudCopy() async throws {
    let remote = MemoryInstructionRemote()
    let fixture = try SyncFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore(remote: remote)
    await store.connectInstructionSync()
    let project = record(UUID().uuidString, "cloud project\n")
    var cloud = await remote.current()
    cloud.workspaces.append(project)
    await remote.replace(cloud)
    await store.syncInstructions()
    #expect(store.pendingSyncedProjects.count == 1)
    let folder = fixture.home.appendingPathComponent("local-project")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try fixture.write("local project\n", to: "local-project/AGENTS.md")
    store.linkSyncedProject(project, at: folder)
    await store.syncInstructions()
    // link schedules a sync on the main actor; either this call or that task performs it.
    while store.isSyncing { await Task.yield() }
    #expect(store.syncConflicts.count == 1)
    #expect(try fixture.read("local-project/AGENTS.md") == "local project\n")
    await store.resolveInstructionSyncConflict(try #require(store.syncConflicts.first), useCloud: true)
    #expect(try fixture.read("local-project/AGENTS.md") == "cloud project\n")
    let id = try #require(store.projects.first?.id)
    store.removeProject(id: id)
    await store.syncInstructions()
    #expect(await remote.current().workspace(id: project.id) != nil)
    #expect(try fixture.read("local-project/AGENTS.md") == "cloud project\n")
  }

  @Test
  func newlyInstalledAgentsReceiveTheExistingSyncedTemplate() async throws {
    let remote = MemoryInstructionRemote()
    let fixture = try SyncFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore(remote: remote)
    await store.connectInstructionSync()
    try FileManager.default.createDirectory(
      at: fixture.home.appendingPathComponent(".factory"), withIntermediateDirectories: true)
    let relaunched = fixture.makeStore(remote: remote)
    await relaunched.syncInstructions()
    #expect(try fixture.read(".factory/AGENTS.md") == "shared\n")
  }

  @Test
  func missingCloudArchiveNeverDeletesLocalInstructions() async throws {
    let remote = MemoryInstructionRemote()
    let fixture = try SyncFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore(remote: remote)
    await store.connectInstructionSync()
    let base = store.syncState.base
    await remote.replace(.init())
    await store.syncInstructions()
    #expect(store.syncError != nil)
    #expect(store.syncState.base == base)
    #expect(try fixture.read(".codex/AGENTS.md") == "shared\n")
    #expect(store.syncArchiveNeedsRestore)
    await store.restoreInstructionSyncArchive()
    #expect(!store.syncArchiveNeedsRestore)
    #expect(store.syncError == nil)
    #expect(await remote.current() == base)
  }

  private func record(_ id: String, _ content: String) -> SyncedWorkspace {
    let global = id == "global"
    return .init(id: id, name: global ? "Global" : "Project", kind: global ? .global : .project,
      keys: global ? AgentTool.harnesses.map(\.templateKey).sorted() : ["agents", "claude"], template: content)
  }

  private func document(_ records: SyncedWorkspace...) -> InstructionSyncDocument {
    .init(workspaces: records.sorted { $0.id < $1.id })
  }
}

private actor MemoryInstructionRemote: InstructionSyncRemote {
  private var document = InstructionSyncDocument()
  private var generation = 0
  private var failure: InstructionSyncError?
  private var delaysUpload = false
  private var uploadContinuation: CheckedContinuation<Void, Never>?

  func connect(repositoryName: String) async throws -> String { "test/\(repositoryName)" }

  func fetch(repository: String) async throws -> InstructionSyncSnapshot {
    .init(document: document, branch: "main", headSHA: String(generation), treeSHA: "tree")
  }

  func push(_ document: InstructionSyncDocument, repository: String, after snapshot: InstructionSyncSnapshot) async throws {
    if let failure { throw failure }
    if delaysUpload { await withCheckedContinuation { uploadContinuation = $0 } }
    guard snapshot.headSHA == String(generation) else { throw InstructionSyncError.concurrentUpdate }
    self.document = document
    generation += 1
  }

  func current() -> InstructionSyncDocument { document }
  func replace(_ value: InstructionSyncDocument) { document = value; generation += 1 }
  func setFailure(_ value: InstructionSyncError?) { failure = value }
  func setUploadDelay(_ value: Bool) { delaysUpload = value }
  func isWaiting() -> Bool { uploadContinuation != nil }
  func releaseUpload() {
    delaysUpload = false
    uploadContinuation?.resume()
    uploadContinuation = nil
  }
}

private struct SyncFixture {
  let home: URL
  var backups: URL { home.appendingPathComponent("Support/Backups") }

  init() throws {
    home = FileManager.default.temporaryDirectory.appendingPathComponent("AgentFilesSync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    try write("shared\n", to: ".codex/AGENTS.md")
  }

  @MainActor
  func makeStore(remote: any InstructionSyncRemote) -> AgentFilesStore {
    let support = home.appendingPathComponent("Support")
    return AgentFilesStore(
      configurationStore: ConfigurationStore(fileURL: support.appendingPathComponent("configuration.json")),
      templateStore: TemplateStore(directory: support.appendingPathComponent("Templates")),
      backupService: BackupService(rootURL: backups),
      skillLibrary: SkillLibraryService(backupRootURL: backups.appendingPathComponent("Skills")),
      homeDirectory: home, syncRemote: remote)
  }

  func read(_ path: String) throws -> String { try String(contentsOf: home.appendingPathComponent(path), encoding: .utf8) }
  func write(_ content: String, to path: String) throws {
    try content.write(to: home.appendingPathComponent(path), atomically: true, encoding: .utf8)
  }
  func remove() { try? FileManager.default.removeItem(at: home) }
}
