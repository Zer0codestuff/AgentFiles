import Foundation
import Testing

@testable import AgentFiles

@Suite("Workspace store")
@MainActor
struct WorkspaceStoreTests {
  @Test
  func globalWorkspaceListsInstalledAgents() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }

    let global = try #require(fixture.makeStore().globalWorkspace)

    #expect(global.keys == ["claude", "codex", "factory"])
  }

  @Test
  func setUpKeepsExistingFilesAndCreatesMissingOnes() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let global = try #require(store.globalWorkspace)

    store.setUp(workspaceID: global.id, baseKey: "codex")

    #expect(try fixture.read(".codex/AGENTS.md") == "# Codex\nshared\n")
    #expect(try fixture.read(".factory/AGENTS.md") == "# Droid\nshared\n")
    #expect(try fixture.read(".claude/CLAUDE.md") == "# Codex\nshared\n")
    #expect(!FileManager.default.fileExists(atPath: fixture.backups.path))
    for target in global.targets {
      #expect(store.status(of: target, in: global) == .synced)
    }
  }

  @Test
  func sharedSaveUpdatesOtherFilesWithBackups() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let global = try #require(store.globalWorkspace)
    store.setUp(workspaceID: global.id, baseKey: "codex")

    let saved = store.save(
      "# Codex\nshared\nnew rule\n",
      for: "codex",
      in: global.id,
      scope: .shared
    )

    #expect(saved)
    #expect(try fixture.read(".factory/AGENTS.md") == "# Droid\nshared\nnew rule\n")
    #expect(try fixture.read(".claude/CLAUDE.md") == "# Codex\nshared\nnew rule\n")
    #expect(FileManager.default.fileExists(atPath: fixture.backups.path))
  }

  @Test
  func privateSaveOnlyWritesOneFile() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let global = try #require(store.globalWorkspace)
    store.setUp(workspaceID: global.id, baseKey: "codex")

    store.save("# Droid\nshared\ndroid rule\n", for: "factory", in: global.id, scope: .only("factory"))

    #expect(try fixture.read(".factory/AGENTS.md") == "# Droid\nshared\ndroid rule\n")
    #expect(try fixture.read(".codex/AGENTS.md") == "# Codex\nshared\n")
  }

  @Test
  func fileChangedOutsideIsNeverOverwritten() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let global = try #require(store.globalWorkspace)
    store.setUp(workspaceID: global.id, baseKey: "codex")

    try fixture.write("# Droid\nshared\nedited elsewhere\n", to: ".factory/AGENTS.md")
    store.save("# Codex\nshared\nnew rule\n", for: "codex", in: global.id, scope: .shared)

    #expect(try fixture.read(".factory/AGENTS.md") == "# Droid\nshared\nedited elsewhere\n")
    #expect(try fixture.read(".claude/CLAUDE.md") == "# Codex\nshared\nnew rule\n")
    let factory = try #require(global.target(key: "factory"))
    #expect(store.status(of: factory, in: global) == .changedOutside)
    #expect(store.notice?.title == "Some files were not updated")
  }

  @Test
  func acceptingAnOutsideChangeCanShareIt() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let global = try #require(store.globalWorkspace)
    store.setUp(workspaceID: global.id, baseKey: "codex")

    try fixture.write("# Droid\nshared\nfrom droid\n", to: ".factory/AGENTS.md")
    store.refreshFiles()
    store.acceptOutsideChange(key: "factory", in: global.id, scope: .shared)

    #expect(try fixture.read(".codex/AGENTS.md") == "# Codex\nshared\nfrom droid\n")
    #expect(try fixture.read(".factory/AGENTS.md") == "# Droid\nshared\nfrom droid\n")
  }

  @Test
  func discardingAnOutsideChangeRestoresTheFile() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let global = try #require(store.globalWorkspace)
    store.setUp(workspaceID: global.id, baseKey: "codex")

    try fixture.write("oops", to: ".codex/AGENTS.md")
    store.discardOutsideChange(key: "codex", in: global.id)

    #expect(try fixture.read(".codex/AGENTS.md") == "# Codex\nshared\n")
    #expect(FileManager.default.fileExists(atPath: fixture.backups.path))
  }

  @Test
  func projectWorkspaceUsesAgentsAndClaudeFiles() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let project = fixture.home.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try "project rules\n".write(
      to: project.appendingPathComponent("AGENTS.md"),
      atomically: true,
      encoding: .utf8
    )

    store.addProject(at: project)
    let workspace = try #require(store.projects.first)
    store.setUp(workspaceID: workspace.id, baseKey: "agents")

    #expect(workspace.keys == ["agents", "claude"])
    #expect(try fixture.read("project/CLAUDE.md") == "project rules\n")
  }

  @Test
  func cursorGetsACopyOnlyVariantWithoutAFile() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.home.appendingPathComponent(".cursor"),
      withIntermediateDirectories: true
    )
    let store = fixture.makeStore()
    let global = try #require(store.globalWorkspace)
    let cursor = try #require(global.target(key: "cursor"))
    store.setUp(workspaceID: global.id, baseKey: "codex")

    store.save("# Cursor\nshared\n", for: "cursor", in: global.id, scope: .only("cursor"))

    #expect(!cursor.writesFile)
    #expect(store.status(of: cursor, in: global) == .copyOnly)
    #expect(store.template(for: global.id)?.render(for: "cursor") == "# Cursor\nshared\n")
    #expect(try fixture.read(".codex/AGENTS.md") == "# Codex\nshared\n")
    #expect(
      try FileManager.default.contentsOfDirectory(
        atPath: fixture.home.appendingPathComponent(".cursor").path
      ).isEmpty
    )
  }

  @Test
  func templatesPersistAcrossLaunches() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let global = try #require(store.globalWorkspace)
    store.setUp(workspaceID: global.id, baseKey: "codex")

    let relaunched = fixture.makeStore()

    #expect(relaunched.template(for: global.id) == store.template(for: global.id))
  }
}

private struct WorkspaceFixture {
  let home: URL

  init() throws {
    home = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentFilesWorkspace-\(UUID().uuidString)", isDirectory: true)
      .resolvingSymlinksInPath()
    for directory in [".claude", ".codex", ".factory"] {
      try FileManager.default.createDirectory(
        at: home.appendingPathComponent(directory),
        withIntermediateDirectories: true
      )
    }
    try write("# Codex\nshared\n", to: ".codex/AGENTS.md")
    try write("# Droid\nshared\n", to: ".factory/AGENTS.md")
  }

  var backups: URL {
    home.appendingPathComponent("Support/Backups", isDirectory: true)
  }

  @MainActor
  func makeStore() -> AgentFilesStore {
    let support = home.appendingPathComponent("Support", isDirectory: true)
    return AgentFilesStore(
      configurationStore: ConfigurationStore(
        fileURL: support.appendingPathComponent("configuration.json")
      ),
      templateStore: TemplateStore(directory: support.appendingPathComponent("Templates")),
      backupService: BackupService(rootURL: backups),
      skillLibrary: SkillLibraryService(backupRootURL: backups.appendingPathComponent("Skills")),
      homeDirectory: home
    )
  }

  func write(_ content: String, to path: String) throws {
    try content.write(to: home.appendingPathComponent(path), atomically: true, encoding: .utf8)
  }

  func read(_ path: String) throws -> String {
    try String(contentsOf: home.appendingPathComponent(path), encoding: .utf8)
  }

  func remove() {
    try? FileManager.default.removeItem(at: home)
  }
}
