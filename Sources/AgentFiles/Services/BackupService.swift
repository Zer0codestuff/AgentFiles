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

  /// Copies the current file before the app overwrites it.
  @discardableResult
  func backup(fileAt url: URL, workspaceID: UUID, key: String) throws -> URL? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }

    let data = try Data(contentsOf: url)
    let directory =
      rootURL
      .appendingPathComponent(workspaceID.uuidString, isDirectory: true)
      .appendingPathComponent(key, isDirectory: true)

    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    let timestamp = String(format: "%.6f", Date().timeIntervalSince1970)
      .replacingOccurrences(of: ".", with: "-")
    let backupURL = directory.appendingPathComponent(
      "\(timestamp)-\(url.lastPathComponent)"
    )
    try data.write(to: backupURL, options: .atomic)
    try prune(directory: directory)
    return backupURL
  }

  private func prune(directory: URL) throws {
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    let overflow = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
      .dropLast(retainedBackupsPerFile)

    for file in overflow {
      try FileManager.default.removeItem(at: file)
    }
  }
}
