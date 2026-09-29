import Foundation
import Testing

@testable import AgentFiles

@Suite("Skill library")
struct SkillLibraryTests {
  @Test
  func scanGroupsCopiesByNameAndDetectsVariants() throws {
    let fixture = try SkillFixture()
    defer { fixture.remove() }

    try fixture.writeSkill("review", in: "claudeCode", files: ["SKILL.md": "v1"])
    try fixture.writeSkill("review", in: "codex", files: ["SKILL.md": "v2"])
    try fixture.writeSkill("deploy", in: "codex", files: ["SKILL.md": "deploy"])
    try FileManager.default.createDirectory(
      at: fixture.directory(for: "codex").appendingPathComponent("not-a-skill"),
      withIntermediateDirectories: true
    )

    let skills = fixture.service.scan(locations: fixture.locations)

    #expect(skills.map(\.name) == ["deploy", "review"])
    #expect(skills[1].installations.keys.sorted() == ["claudeCode", "codex"])
    #expect(skills[1].variantCount == 2)
    #expect(skills[0].variantCount == 1)
  }

  @Test
  func applyMirrorsSourceAndBacksUpTarget() throws {
    let fixture = try SkillFixture()
    defer { fixture.remove() }

    try fixture.writeSkill(
      "review",
      in: "claudeCode",
      files: ["SKILL.md": "new", "scripts/run.sh": "echo hi"]
    )
    try fixture.writeSkill("review", in: "codex", files: ["SKILL.md": "old", "stale.txt": "x"])

    let skill = try #require(fixture.service.scan(locations: fixture.locations).first)
    let plan = try fixture.service.makePlan(
      for: skill,
      from: "claudeCode",
      to: fixture.locations
    )
    let target = try #require(plan.targets.first { $0.locationID == "codex" })
    #expect(
      Set(target.changes) == [
        SkillFileChange(path: "SKILL.md", kind: .modified),
        SkillFileChange(path: "scripts/run.sh", kind: .added),
        SkillFileChange(path: "stale.txt", kind: .removed),
      ]
    )

    try fixture.service.apply(plan)

    let codexSkill = fixture.directory(for: "codex").appendingPathComponent("review")
    #expect(try String(contentsOf: codexSkill.appendingPathComponent("SKILL.md"), encoding: .utf8) == "new")
    #expect(FileManager.default.fileExists(atPath: codexSkill.appendingPathComponent("scripts/run.sh").path))
    #expect(!FileManager.default.fileExists(atPath: codexSkill.appendingPathComponent("stale.txt").path))

    let backups = try FileManager.default.contentsOfDirectory(
      atPath: fixture.backupURL.appendingPathComponent("review/codex").path
    )
    #expect(backups.count == 1)

    let rescanned = try #require(fixture.service.scan(locations: fixture.locations).first)
    #expect(rescanned.variantCount == 1)
  }

  @Test
  func applyInstallsIntoMissingLocation() throws {
    let fixture = try SkillFixture()
    defer { fixture.remove() }

    try fixture.writeSkill("review", in: "claudeCode", files: ["SKILL.md": "hello"])
    let skill = try #require(fixture.service.scan(locations: fixture.locations).first)
    let plan = try fixture.service.makePlan(
      for: skill,
      from: "claudeCode",
      to: fixture.locations.filter { $0.id == "factory" }
    )

    try fixture.service.apply(plan)

    let installed = fixture.directory(for: "factory").appendingPathComponent("review/SKILL.md")
    #expect(try String(contentsOf: installed, encoding: .utf8) == "hello")
  }

  @Test
  func applyStopsWhenTargetChangedAfterPlanning() throws {
    let fixture = try SkillFixture()
    defer { fixture.remove() }

    try fixture.writeSkill("review", in: "claudeCode", files: ["SKILL.md": "source"])
    try fixture.writeSkill("review", in: "codex", files: ["SKILL.md": "target"])
    let skill = try #require(fixture.service.scan(locations: fixture.locations).first)
    let plan = try fixture.service.makePlan(for: skill, from: "claudeCode", to: fixture.locations)

    try fixture.writeSkill("review", in: "codex", files: ["SKILL.md": "concurrent edit"])

    #expect(throws: SkillLibraryError.self) {
      try fixture.service.apply(plan)
    }
    let target = fixture.directory(for: "codex").appendingPathComponent("review/SKILL.md")
    #expect(try String(contentsOf: target, encoding: .utf8) == "concurrent edit")
  }

  @Test
  func symbolicLinksToTheSourceAreNotRewritten() throws {
    let fixture = try SkillFixture()
    defer { fixture.remove() }

    try fixture.writeSkill("review", in: "claudeCode", files: ["SKILL.md": "shared"])
    try FileManager.default.createDirectory(
      at: fixture.directory(for: "codex"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: fixture.directory(for: "codex").appendingPathComponent("review"),
      withDestinationURL: fixture.directory(for: "claudeCode").appendingPathComponent("review")
    )

    let skill = try #require(fixture.service.scan(locations: fixture.locations).first)
    #expect(skill.installation(in: "codex")?.isSymbolicLink == true)

    let plan = try fixture.service.makePlan(
      for: skill,
      from: "claudeCode",
      to: fixture.locations.filter { $0.id == "codex" }
    )
    #expect(plan.targets.isEmpty)
  }

  @Test
  func frontMatterDescriptionSupportsQuotedAndFoldedValues() {
    #expect(
      SkillLibraryService.frontMatterValue(
        "description",
        in: "---\nname: a\ndescription: \"Reviews code\"\n---\n# A"
      ) == "Reviews code"
    )
    #expect(
      SkillLibraryService.frontMatterValue(
        "description",
        in: "---\nname: a\ndescription: >\n  Line one\n  line two\n---\n"
      ) == "Line one line two"
    )
    #expect(SkillLibraryService.frontMatterValue("description", in: "# No front matter") == nil)
  }

  @Test
  func reachabilityFollowsCompatibilityFolders() {
    let skill = SkillRecord(
      name: "review",
      summary: "",
      installations: [
        "claudeCode": SkillInstallation(
          locationID: "claudeCode",
          url: URL(fileURLWithPath: "/tmp/review"),
          resolvedURL: URL(fileURLWithPath: "/tmp/review"),
          isSymbolicLink: false,
          digest: "a",
          fileDigests: [:],
          modificationDate: nil
        )
      ]
    )

    let reached = skill.reachableHarnesses(among: AgentTool.harnesses)
    #expect(reached == [.claudeCode, .cursor, .grok, .warp])
  }
}

private struct SkillFixture {
  let root: URL
  let backupURL: URL
  let service: SkillLibraryService
  let locations: [SkillLocation]

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentFilesSkillTests-\(UUID().uuidString)", isDirectory: true)
      .resolvingSymlinksInPath()
    backupURL = root.appendingPathComponent("Backups", isDirectory: true)
    service = SkillLibraryService(backupRootURL: backupURL)
    let root = root
    locations = ["claudeCode", "codex", "factory"].map { id in
      SkillLocation(
        id: id,
        title: id,
        systemImage: "folder",
        directory: root.appendingPathComponent(id, isDirectory: true),
        tool: AgentTool(rawValue: id),
        isAvailable: true
      )
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func directory(for locationID: String) -> URL {
    root.appendingPathComponent(locationID, isDirectory: true)
  }

  func writeSkill(_ name: String, in locationID: String, files: [String: String]) throws {
    let skill = directory(for: locationID).appendingPathComponent(name, isDirectory: true)
    for (path, content) in files {
      let url = skill.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}
