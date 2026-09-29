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

  static var templates: URL {
    applicationSupport.appendingPathComponent("Templates", isDirectory: true)
  }

  static var backups: URL {
    applicationSupport.appendingPathComponent("Backups", isDirectory: true)
  }

  static var skillBackups: URL {
    backups.appendingPathComponent("Skills", isDirectory: true)
  }
}
