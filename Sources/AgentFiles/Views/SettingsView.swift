import AppKit
import SwiftUI

struct SettingsView: View {
  let store: AgentFilesStore

  var body: some View {
    Form {
      Section("Instructions") {
        Text(
          "Each workspace keeps one shared text in Agent Files and writes a plain file for every agent. Files changed in another app are never overwritten until you review them."
        )
        .foregroundStyle(.secondary)

        Button("Show Templates in Finder") {
          reveal(AppDirectories.templates)
        }
      }

      Section("Backups") {
        LabeledContent("Copies per file", value: "20")
        Text(PathFormatter.compact(AppDirectories.backups.path))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)

        Button("Show Backups in Finder") {
          reveal(AppDirectories.backups)
        }
      }

      Section("Skills") {
        LabeledContent("Kept in sync", value: "\(store.configuration.trackedSkills.count)")
        Text("Skills marked Keep in Sync copy edits to their other copies while Agent Files is open.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 500, height: 420)
  }

  private func reveal(_ directory: URL) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    NSWorkspace.shared.open(directory)
  }
}
