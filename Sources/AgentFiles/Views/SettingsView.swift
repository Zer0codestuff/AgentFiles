import AppKit
import SwiftUI

struct SettingsView: View {
  let store: AgentFilesStore

  var body: some View {
    TabView {
      Form {
        Section("Synchronization") {
          Toggle(
            "Automatic sync",
            isOn: Binding(
              get: { store.automaticSyncEnabled },
              set: { store.setAutomaticSyncEnabled($0) }
            )
          )

          LabeledContent("Current mode", value: "Whole file")
          Text(
            "When automatic sync is off, Agent Files still notices disk changes but does not copy them."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section("Application") {
          LabeledContent("Background mode", value: "Menu bar only")
          Text("Closing the main window leaves Agent Files running in the menu bar.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .tabItem {
        Label("General", systemImage: "gearshape")
      }

      Form {
        Section("Backups") {
          LabeledContent("Copies per file", value: "20")
          Text(compactPath(AppDirectories.backups.path))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

          Button("Show Backups in Finder") {
            showBackups()
          }
        }

        Section("Conflicts") {
          Text(
            "If several files change before a sync completes, Agent Files pauses the group and asks you to choose the source version."
          )
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .tabItem {
        Label("Safety", systemImage: "lock.shield")
      }
    }
    .frame(width: 520, height: 340)
    .scenePadding()
  }

  private func showBackups() {
    try? FileManager.default.createDirectory(
      at: AppDirectories.backups,
      withIntermediateDirectories: true
    )
    NSWorkspace.shared.open(AppDirectories.backups)
  }

  private func compactPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home + "/") {
      return "~" + path.dropFirst(home.count)
    }
    return path
  }
}
