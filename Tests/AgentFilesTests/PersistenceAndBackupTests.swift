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
      let managedFile = ManagedInstructionFile(
        url: URL(fileURLWithPath: "/tmp/AGENTS.md"),
        tool: .codex
      )
      let expected = AppConfiguration(
        automaticSyncEnabled: false,
        groups: [
          SyncGroup(
            name: "Shared",
            files: [managedFile],
            automaticSyncEnabled: false
          )
        ]
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
      let file = ManagedInstructionFile(url: sourceURL)
      let groupID = UUID()
      let backupService = BackupService(
        rootURL: backupRoot,
        retainedBackupsPerFile: 2
      )

      for value in ["one", "two", "three"] {
        try value.write(to: sourceURL, atomically: true, encoding: .utf8)
        try backupService.backup(file: file, groupID: groupID)
      }

      let fileBackupDirectory =
        backupRoot
        .appendingPathComponent(groupID.uuidString)
        .appendingPathComponent(file.id.uuidString)
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
