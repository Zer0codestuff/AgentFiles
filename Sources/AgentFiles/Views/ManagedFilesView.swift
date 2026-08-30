import SwiftUI

struct ManagedFilesView: View {
  let store: AgentFilesStore
  let searchText: String
  let onAddFiles: () -> Void

  @State private var filePendingRemoval: ManagedInstructionFile?

  var body: some View {
    if let group = store.group(id: store.selectedGroupID) {
      VStack(spacing: 0) {
        groupHeader(group)

        Divider()

        if group.files.isEmpty {
          ContentUnavailableView {
            Label("No Files", systemImage: "doc.badge.plus")
          } description: {
            Text("Add AGENTS.md, CLAUDE.md, or another UTF-8 instruction file.")
          } actions: {
            Button("Add Files", action: onAddFiles)
              .buttonStyle(.glassProminent)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredFiles(in: group).isEmpty {
          ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(selection: selection) {
            ForEach(filteredFiles(in: group)) { file in
              ManagedFileRow(
                file: file,
                snapshot: store.snapshot(for: file.id)
              )
              .tag(file.id)
              .contextMenu {
                Button("Reveal in Finder") {
                  NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
                Divider()
                Button("Remove from Group", role: .destructive) {
                  filePendingRemoval = file
                }
              }
            }
          }
          .listStyle(.inset)
        }

        Divider()

        HStack {
          Text("\(group.files.count) file\(group.files.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Add Files", systemImage: "plus", action: onAddFiles)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
      .confirmationDialog(
        "Remove \(filePendingRemoval?.displayName ?? "this file")?",
        isPresented: Binding(
          get: { filePendingRemoval != nil },
          set: { if !$0 { filePendingRemoval = nil } }
        )
      ) {
        Button("Remove from Group", role: .destructive) {
          if let filePendingRemoval {
            store.removeFile(id: filePendingRemoval.id)
          }
          filePendingRemoval = nil
        }
        Button("Cancel", role: .cancel) {
          filePendingRemoval = nil
        }
      } message: {
        Text("The file stays on disk and will no longer be synchronized by this group.")
      }
    } else {
      ContentUnavailableView {
        Label("Select a Group", systemImage: "sidebar.left")
      } description: {
        Text("Choose a sync group from the sidebar.")
      }
    }
  }

  private func groupHeader(_ group: SyncGroup) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(group.name)
            .font(.title3.weight(.semibold))
          Text("Whole-file synchronization")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle(
          "Automatic sync",
          isOn: Binding(
            get: { group.automaticSyncEnabled },
            set: { store.setAutomaticSyncEnabled($0, for: group.id) }
          )
        )
        .toggleStyle(.switch)
        .labelsHidden()
        .help("Automatic sync for this group")
      }

      GroupStatusLabel(state: store.state(for: group))
    }
    .padding(16)
  }

  private var selection: Binding<UUID?> {
    Binding(
      get: { store.selectedFileID },
      set: { store.selectFile($0) }
    )
  }

  private func filteredFiles(in group: SyncGroup) -> [ManagedInstructionFile] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return group.files
    }

    return group.files.filter { file in
      file.displayName.localizedStandardContains(query)
        || file.path.localizedStandardContains(query)
        || file.tool.title.localizedStandardContains(query)
    }
  }
}

private struct ManagedFileRow: View {
  let file: ManagedInstructionFile
  let snapshot: FileSnapshot?

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: file.tool.systemImage)
        .foregroundStyle(iconStyle)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(file.displayName)
          .lineLimit(1)
        Text("\(file.tool.title)  \(compactParentPath)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(.vertical, 3)
  }

  private var compactParentPath: String {
    let parent = file.url.deletingLastPathComponent().path
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if parent == home {
      return "~"
    }
    if parent.hasPrefix(home + "/") {
      return "~" + parent.dropFirst(home.count)
    }
    return parent
  }

  private var iconStyle: AnyShapeStyle {
    switch snapshot?.availability {
    case .missing, .unreadable:
      AnyShapeStyle(Color.red)
    default:
      AnyShapeStyle(Color.secondary)
    }
  }
}
