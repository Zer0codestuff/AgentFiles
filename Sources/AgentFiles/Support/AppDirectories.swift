import Foundation

enum AppDirectories {
  static var applicationSupport: URL {
    FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Agent Files", isDirectory: true)
  }

  static var configurationFile: URL {
    applicationSupport.appendingPathComponent("configuration.json")
  }

  static var backups: URL {
    applicationSupport.appendingPathComponent("Backups", isDirectory: true)
  }
}
