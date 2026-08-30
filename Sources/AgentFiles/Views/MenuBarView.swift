import AppKit
import SwiftUI

struct MenuBarView: View {
  let store: AgentFilesStore

  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open Agent Files") {
      openMainWindow()
    }

    Divider()

    Toggle(
      "Automatic Sync",
      isOn: Binding(
        get: { store.automaticSyncEnabled },
        set: { store.setAutomaticSyncEnabled($0) }
      )
    )

    Button("Sync All Groups") {
      store.synchronizeAllSafeGroups()
    }
    .disabled(store.managedFileCount < 2)

    if store.hasBlockingIssue {
      Divider()
      Button("Review Sync Issue") {
        openMainWindow()
      }
    }

    Divider()

    SettingsLink {
      Text("Settings...")
    }

    Button("Quit Agent Files") {
      NSApplication.shared.terminate(nil)
    }
  }

  private func openMainWindow() {
    let existingWindow = NSApp.windows.first { window in
      window.title == "Agent Files" && window.canBecomeMain
    }

    if let existingWindow {
      existingWindow.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: "main")
    }
    AppActivation.bringForward()
  }
}
