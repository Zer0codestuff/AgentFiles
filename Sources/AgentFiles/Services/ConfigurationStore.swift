import Foundation

struct ConfigurationStore: Sendable {
  let fileURL: URL

  init(fileURL: URL = AppDirectories.configurationFile) {
    self.fileURL = fileURL
  }

  func load() throws -> AppConfiguration {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return AppConfiguration()
    }

    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode(AppConfiguration.self, from: data)
  }

  func save(_ configuration: AppConfiguration) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(configuration)
    try data.write(to: fileURL, options: .atomic)
  }
}
