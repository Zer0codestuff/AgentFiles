import Foundation
import Testing

@testable import AgentFiles

@Suite("Persistence and backups")
struct PersistenceAndBackupTests {
  @Test
  func configurationRoundTrip() throws {
    try withTemporaryDirectory { temporaryDirectory in
      let fileURL = temporaryDirectory.appendingPathComponent("configuration.json")
      let configurationStore = ConfigurationStore(fileURL: fileURL)
      let expected = AppConfiguration(
        workspaces: [Workspace.project(at: URL(fileURLWithPath: "/tmp/project"))],
        trackedSkills: [TrackedSkill(name: "review", locationIDs: ["codex"], baselineDigest: "a")]
      )

      try configurationStore.save(expected)

      #expect(try configurationStore.load() == expected)
    }
  }

  @Test
  func backupRetentionKeepsNewestCopies() throws {
    try withTemporaryDirectory { temporaryDirectory in
      let sourceURL = temporaryDirectory.appendingPathComponent("AGENTS.md")
      let backupRoot = temporaryDirectory.appendingPathComponent("Backups")
      let workspaceID = UUID()
      let backupService = BackupService(
        rootURL: backupRoot,
        retainedBackupsPerFile: 2
      )

      for value in ["one", "two", "three"] {
        try value.write(to: sourceURL, atomically: true, encoding: .utf8)
        try backupService.backup(fileAt: sourceURL, workspaceID: workspaceID, key: "codex")
      }

      let fileBackupDirectory =
        backupRoot
        .appendingPathComponent(workspaceID.uuidString)
        .appendingPathComponent("codex")
      let backups = try FileManager.default.contentsOfDirectory(
        at: fileBackupDirectory,
        includingPropertiesForKeys: nil
      )

      #expect(backups.count == 2)
    }
  }

  private func withTemporaryDirectory(
    _ operation: (URL) throws -> Void
  ) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentFilesTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    try operation(directory)
  }
}
