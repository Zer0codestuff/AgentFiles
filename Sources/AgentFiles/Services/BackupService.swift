import Foundation

struct BackupService: Sendable {
  let rootURL: URL
  let retainedBackupsPerFile: Int

  init(
    rootURL: URL = AppDirectories.backups,
    retainedBackupsPerFile: Int = 20
  ) {
    self.rootURL = rootURL
    self.retainedBackupsPerFile = retainedBackupsPerFile
  }

  @discardableResult
  func backup(
    file: ManagedInstructionFile,
    groupID: UUID
  ) throws -> URL? {
    guard FileManager.default.fileExists(atPath: file.path) else {
      return nil
    }

    let data = try Data(contentsOf: file.url)
    let directory =
      rootURL
      .appendingPathComponent(groupID.uuidString, isDirectory: true)
      .appendingPathComponent(file.id.uuidString, isDirectory: true)

    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    let timestamp = String(format: "%.6f", Date().timeIntervalSince1970)
      .replacingOccurrences(of: ".", with: "-")
    let backupURL = directory.appendingPathComponent(
      "\(timestamp)-\(UUID().uuidString)-\(file.url.lastPathComponent)"
    )
    try data.write(to: backupURL, options: .atomic)
    try prune(directory: directory)
    return backupURL
  }

  private func prune(directory: URL) throws {
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )
    let overflow = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
      .dropLast(retainedBackupsPerFile)

    for file in overflow {
      try FileManager.default.removeItem(at: file)
    }
  }
}
