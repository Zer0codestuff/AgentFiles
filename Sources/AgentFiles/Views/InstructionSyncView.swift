import AppKit
import SwiftUI

struct InstructionSyncView: View {
  let store: AgentFilesStore
  @Environment(\.dismiss) private var dismiss
  @State private var reviewing: InstructionSyncConflict?
  @State private var confirmsDisconnect = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Sync across computers").font(.title2.weight(.semibold))
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      .padding(20)
      Form {
        Section {
          Label(store.syncStatus, systemImage: statusSymbol)
          if let date = store.syncState.lastSyncedAt {
            LabeledContent("Last synced") {
              Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
            }
          }
          Text("Your instruction files sync through a private GitHub repository. Skills and local folder paths stay on this computer.")
            .foregroundStyle(.secondary)

          if store.isSyncConnected {
            Toggle("Sync automatically", isOn: Binding(
              get: { store.syncState.automatic }, set: { store.setAutomaticInstructionSync($0) }
            ))
            .disabled(store.isSyncing)
            Text("Checks every minute while Agent Files is open and after you save. Offline edits sync when the connection returns.")
              .font(.caption).foregroundStyle(.secondary)
            Button("Sync Now") { Task { await store.syncInstructions() } }
              .disabled(store.isSyncing || store.isSigningIn)
          } else {
            Button("Connect Sync") { Task { await store.connectInstructionSync() } }
              .buttonStyle(.borderedProminent)
              .disabled(store.isSyncing || store.isSigningIn)
            Text("Agent Files creates or connects agent-files-sync in your signed-in account. It imports existing instructions without changing them.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if let error = store.syncError {
            Text(error).foregroundStyle(.red).textSelection(.enabled)
          }
          if store.syncArchiveNeedsRestore {
            Button("Restore Saved Archive") { Task { await store.restoreInstructionSyncArchive() } }
              .disabled(store.isSyncing)
            Text("Adds missing instructions from this computer's saved archive. Existing synced versions are kept.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if !store.isSyncConnected || store.syncError != nil {
            Button("Sign In to GitHub") { Task { await store.signInToGitHub() } }
              .disabled(store.isSigningIn || store.isSyncing)
          }
          if let code = store.syncSignInCode {
            LabeledContent("Sign-in code") {
              HStack {
                Text(code).font(.body.monospaced()).textSelection(.enabled)
                Button("Copy") {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(code, forType: .string)
                }
              }
            }
            Text("Enter this code in the browser to authorize GitHub once. All sync and conflict review happen here in Agent Files.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }

        if !store.syncConflicts.isEmpty {
          Section("Review conflicts") {
            Text("These instructions changed on both computers. Choose which version to keep. Sync waits until you review them.")
              .foregroundStyle(.secondary)
            ForEach(store.syncConflicts) { conflict in
              HStack {
                Label(conflict.local.name, systemImage: conflict.local.kind == .global ? "globe" : "folder")
                Spacer()
                Button("Compare") { reviewing = conflict }.disabled(store.isSyncing)
              }
            }
          }
        }

        if !store.pendingSyncedProjects.isEmpty {
          Section("Projects on other computers") {
            Text("Choose the local folder once for each project you want on this computer.")
              .foregroundStyle(.secondary)
            ForEach(store.pendingSyncedProjects) { project in
              HStack {
                Label(project.name, systemImage: "folder")
                Spacer()
                Button("Choose Folder") {
                  if let folder = OpenPanelService().chooseProjectFolder() {
                    store.linkSyncedProject(project, at: folder)
                  }
                }.disabled(store.isSyncing)
              }
            }
          }
        }

        if store.workspaces.contains(where: { store.needsAttention($0) }) {
          Section("Local files to review") {
            Text("Files edited outside Agent Files keep their changes. Open the workspace and review each flagged file before syncing its edits.")
              .foregroundStyle(.secondary)
            ForEach(store.workspaces.filter { store.needsAttention($0) }) { workspace in
              Button("Open \(workspace.name)") {
                store.selection = .workspace(workspace.id)
                dismiss()
              }
            }
          }
        }

        if store.isSyncConnected {
          Section {
            Button("Disconnect This Computer", role: .destructive) { confirmsDisconnect = true }
              .disabled(store.isSyncing)
            Text("Your local files and the private archive are kept.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
    }
    .frame(width: 590, height: 610)
    .sheet(item: $reviewing) { conflict in
      InstructionSyncConflictView(store: store, conflict: conflict)
    }
    .confirmationDialog("Disconnect this computer?", isPresented: $confirmsDisconnect) {
      Button("Disconnect", role: .destructive) { store.disconnectInstructionSync() }
    } message: {
      Text("Automatic sync stops on this computer. Your instructions stay where they are.")
    }
  }

  private var statusSymbol: String {
    if store.syncError != nil || !store.syncConflicts.isEmpty { return "exclamationmark.icloud" }
    return store.isSyncConnected ? "checkmark.icloud" : "icloud"
  }
}

struct InstructionSyncConflictView: View {
  let store: AgentFilesStore
  let conflict: InstructionSyncConflict
  @Environment(\.dismiss) private var dismiss
  @State private var selectedKey: String?

  var body: some View {
    let keys = Array(Set(conflict.local.keys).union(conflict.cloud.keys)).sorted()
    let key = selectedKey ?? keys.first ?? "agents"
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Review \(conflict.local.name)").font(.title2.weight(.semibold))
        Spacer()
        Button("Later") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("Choose one version for this workspace. The other version is kept in local backups or the private archive's history.")
        .foregroundStyle(.secondary)
      Picker("Instruction file", selection: Binding(
        get: { key }, set: { selectedKey = $0 }
      )) {
        ForEach(keys, id: \.self) { key in Text(title(for: key)).tag(key) }
      }
      .pickerStyle(.segmented)

      HStack(alignment: .top, spacing: 16) {
        version("This computer", content: conflict.local.instructions.render(for: key))
        version("Synced version", content: conflict.cloud.instructions.render(for: key))
      }
      HStack {
        Spacer()
        Button("Keep This Computer") { resolve(useCloud: false) }
        Button("Use Synced Version") { resolve(useCloud: true) }
          .buttonStyle(.borderedProminent)
      }.disabled(store.isSyncing)
    }
    .padding(24)
    .frame(width: 900, height: 620)
  }

  private func version(_ title: String, content: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      ScrollView {
        Text(content.isEmpty ? "Empty file" : content)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(12)
      }
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func title(for key: String) -> String {
    if conflict.local.kind == .project { return key == "claude" ? "CLAUDE.md" : "AGENTS.md" }
    return AgentTool.harnesses.first { $0.templateKey == key }?.title ?? "AGENTS.md"
  }

  private func resolve(useCloud: Bool) {
    Task {
      await store.resolveInstructionSyncConflict(conflict, useCloud: useCloud)
      dismiss()
    }
  }
}
