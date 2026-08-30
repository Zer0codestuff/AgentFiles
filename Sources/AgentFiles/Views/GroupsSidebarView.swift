import SwiftUI

struct GroupsSidebarView: View {
  let store: AgentFilesStore
  let onNewGroup: () -> Void
  let onRenameGroup: (SyncGroup) -> Void

  @State private var groupPendingRemoval: SyncGroup?

  var body: some View {
    List(selection: selection) {
      Section("Sync Groups") {
        ForEach(store.groups) { group in
          GroupSidebarRow(
            group: group,
            state: store.state(for: group)
          )
          .tag(group.id)
          .contextMenu {
            Button("Rename") {
              onRenameGroup(group)
            }
            Button("Remove Group", role: .destructive) {
              groupPendingRemoval = group
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Agent Files")
    .overlay {
      if store.groups.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "folder.badge.plus")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("No Sync Groups")
            .font(.headline)
          Text("Create a group to start.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Button("New Sync Group", action: onNewGroup)
            .buttonStyle(.glassProminent)
        }
        .padding(16)
      }
    }
    .confirmationDialog(
      "Remove \(groupPendingRemoval?.name ?? "this group")?",
      isPresented: Binding(
        get: { groupPendingRemoval != nil },
        set: { if !$0 { groupPendingRemoval = nil } }
      )
    ) {
      Button("Remove Group", role: .destructive) {
        if let groupPendingRemoval {
          store.removeGroup(id: groupPendingRemoval.id)
        }
        groupPendingRemoval = nil
      }
      Button("Cancel", role: .cancel) {
        groupPendingRemoval = nil
      }
    } message: {
      Text("The files stay on disk. Only this group is removed from Agent Files.")
    }
  }

  private var selection: Binding<UUID?> {
    Binding(
      get: { store.selectedGroupID },
      set: { store.selectGroup($0) }
    )
  }
}

private struct GroupSidebarRow: View {
  let group: SyncGroup
  let state: GroupSyncState

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "folder")
        .foregroundStyle(.secondary)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 2) {
        Text(group.name)
          .lineLimit(1)
        Text(state.shortDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 6)

      Image(systemName: state.sidebarSystemImage)
        .font(.caption)
        .foregroundStyle(statusColor)
    }
    .padding(.vertical, 2)
  }

  private var statusColor: AnyShapeStyle {
    switch state {
    case .conflict, .error, .missingFiles:
      AnyShapeStyle(Color.red)
    case .needsSource:
      AnyShapeStyle(Color.orange)
    default:
      AnyShapeStyle(Color.secondary)
    }
  }
}
