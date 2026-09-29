import Foundation
import Testing

@testable import AgentFiles

@Suite("Tracked skills")
struct SkillTrackingTests {
  @Test
  @MainActor
  func editToOneCopyPropagatesToTheOthers() async throws {
    let fixture = try TrackingFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()

    await store.rescanSkills()
    store.setSkillTracking(true, for: "review")
    #expect(store.trackedSkill(named: "review")?.locationIDs == ["claudeCode", "codex"])

    try fixture.write("edited", to: "claudeCode")
    await store.rescanSkills()

    try await waitUntil { try fixture.read("codex") == "edited" }
    #expect(try fixture.read("codex") == "edited")
    #expect(store.skillConflicts.isEmpty)
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.backupURL.appendingPathComponent("review/codex").path
      )
    )
  }

  @Test
  @MainActor
  func independentEditsPauseTheSkill() async throws {
    let fixture = try TrackingFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()

    await store.rescanSkills()
    store.setSkillTracking(true, for: "review")

    try fixture.write("claude edit", to: "claudeCode")
    try fixture.write("codex edit", to: "codex")
    await store.rescanSkills()

    #expect(store.skillConflicts.contains("review"))
    #expect(try fixture.read("claudeCode") == "claude edit")
    #expect(try fixture.read("codex") == "codex edit")
  }

  @MainActor
  private func waitUntil(_ condition: () throws -> Bool) async throws {
    for _ in 0..<40 where !(try condition()) {
      try await Task.sleep(for: .milliseconds(50))
    }
  }
}

private struct TrackingFixture {
  let home: URL
  let configurationURL: URL
  let backupURL: URL

  init() throws {
    home = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentFilesTracking-\(UUID().uuidString)", isDirectory: true)
      .resolvingSymlinksInPath()
    configurationURL = home.appendingPathComponent("configuration.json")
    backupURL = home.appendingPathComponent("Backups", isDirectory: true)

    try write("original", to: "claudeCode")
    try write("original", to: "codex")
  }

  @MainActor
  func makeStore() -> AgentFilesStore {
    AgentFilesStore(
      configurationStore: ConfigurationStore(fileURL: configurationURL),
      templateStore: TemplateStore(directory: home.appendingPathComponent("Templates")),
      backupService: BackupService(rootURL: backupURL),
      skillLibrary: SkillLibraryService(backupRootURL: backupURL),
      homeDirectory: home
    )
  }

  func skillFile(_ locationID: String) -> URL {
    let tool = AgentTool(rawValue: locationID)!
    return tool.skillsDirectory(in: home)!
      .appendingPathComponent("review/SKILL.md")
  }

  func write(_ content: String, to locationID: String) throws {
    let url = skillFile(locationID)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  func read(_ locationID: String) throws -> String {
    try String(contentsOf: skillFile(locationID), encoding: .utf8)
  }

  func remove() {
    try? FileManager.default.removeItem(at: home)
  }
}
