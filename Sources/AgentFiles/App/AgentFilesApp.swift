import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}

@main
struct AgentFilesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store = AgentFilesStore.makeForLaunch()

  var body: some Scene {
    Window("Agent Files", id: "main") {
      ContentView(store: store)
    }
    .defaultSize(width: 1_100, height: 740)
    .windowResizability(.contentMinSize)

    Settings {
      SettingsView(store: store)
    }
  }
}

extension AgentFilesStore {
  /// Uses `AGENT_FILES_HOME` as a sandboxed home folder when set, for demos and testing.
  static func makeForLaunch() -> AgentFilesStore {
    guard let path = ProcessInfo.processInfo.environment["AGENT_FILES_HOME"] else {
      return AgentFilesStore()
    }
    let home = URL(fileURLWithPath: path, isDirectory: true)
    let support = home.appendingPathComponent("Agent Files Support", isDirectory: true)
    let backups = support.appendingPathComponent("Backups", isDirectory: true)
    return AgentFilesStore(
      configurationStore: ConfigurationStore(
        fileURL: support.appendingPathComponent("configuration.json")
      ),
      templateStore: TemplateStore(directory: support.appendingPathComponent("Templates")),
      backupService: BackupService(rootURL: backups),
      skillLibrary: SkillLibraryService(
        backupRootURL: backups.appendingPathComponent("Skills", isDirectory: true)
      ),
      homeDirectory: home
    )
  }
}
