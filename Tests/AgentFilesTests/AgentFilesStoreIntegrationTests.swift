import Foundation
import Testing

@testable import AgentFiles

@Suite("Agent Files store")
struct AgentFilesStoreIntegrationTests {
  @Test
  @MainActor
  func externalEditPropagatesThroughDirectoryWatcher() async throws {
    let fixture = try makeFixture(automaticSyncEnabled: true)
    defer { fixture.remove() }

    let store = AgentFilesStore(
      configurationStore: ConfigurationStore(fileURL: fixture.configurationURL),
      backupService: BackupService(rootURL: fixture.backupURL)
    )
    store.start()

    try "external edit".write(
      to: fixture.sourceURL,
      atomically: true,
      encoding: .utf8
    )

    for _ in 0..<30 {
      if try String(contentsOf: fixture.targetURL, encoding: .utf8) == "external edit" {
        break
      }
      try await Task.sleep(for: .milliseconds(50))
    }

    #expect(
      try String(contentsOf: fixture.targetURL, encoding: .utf8) == "external edit"
    )
    #expect(FileManager.default.fileExists(atPath: fixture.backupURL.path))
  }

  @Test
  @MainActor
  func disabledAutomaticSyncOnlyWritesEditedFile() throws {
    let fixture = try makeFixture(automaticSyncEnabled: false)
    defer { fixture.remove() }

    let store = AgentFilesStore(
      configurationStore: ConfigurationStore(fileURL: fixture.configurationURL),
      backupService: BackupService(rootURL: fixture.backupURL)
    )
    store.start()
    let sourceDigest = store.snapshot(for: fixture.sourceFile.id)?.digest

    let saved = store.saveEditorContent(
      "local only",
      fileID: fixture.sourceFile.id,
      expectedDigest: sourceDigest
    )

    #expect(saved)
    #expect(
      try String(contentsOf: fixture.sourceURL, encoding: .utf8) == "local only"
    )
    #expect(
      try String(contentsOf: fixture.targetURL, encoding: .utf8) == "original"
    )
  }

  private func makeFixture(
    automaticSyncEnabled: Bool
  ) throws -> StoreFixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentFilesStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    let sourceURL = directory.appendingPathComponent("AGENTS.md")
    let targetURL = directory.appendingPathComponent("CLAUDE.md")
    try "original".write(to: sourceURL, atomically: true, encoding: .utf8)
    try "original".write(to: targetURL, atomically: true, encoding: .utf8)

    let sourceFile = ManagedInstructionFile(url: sourceURL, tool: .codex)
    let targetFile = ManagedInstructionFile(url: targetURL, tool: .claudeCode)
    let configuration = AppConfiguration(
      automaticSyncEnabled: automaticSyncEnabled,
      groups: [
        SyncGroup(
          name: "Shared",
          files: [sourceFile, targetFile]
        )
      ]
    )
    let configurationURL = directory.appendingPathComponent("configuration.json")
    try ConfigurationStore(fileURL: configurationURL).save(configuration)

    return StoreFixture(
      directory: directory,
      configurationURL: configurationURL,
      backupURL: directory.appendingPathComponent("Backups"),
      sourceURL: sourceURL,
      targetURL: targetURL,
      sourceFile: sourceFile
    )
  }
}

private struct StoreFixture {
  let directory: URL
  let configurationURL: URL
  let backupURL: URL
  let sourceURL: URL
  let targetURL: URL
  let sourceFile: ManagedInstructionFile

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}
