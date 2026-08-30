import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}

@main
struct AgentFilesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store = AgentFilesStore()

  var body: some Scene {
    WindowGroup("Agent Files", id: "main") {
      ContentView(store: store)
    }
    .defaultSize(width: 1_120, height: 720)
    .windowResizability(.contentMinSize)
    .defaultLaunchBehavior(.presented)

    MenuBarExtra {
      MenuBarView(store: store)
    } label: {
      Image(
        systemName: store.hasBlockingIssue
          ? "exclamationmark.triangle.fill"
          : "arrow.triangle.2.circlepath"
      )
      .accessibilityLabel("Agent Files")
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView(store: store)
    }
  }
}
