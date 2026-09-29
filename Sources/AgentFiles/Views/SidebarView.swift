import AppKit
import SwiftUI

struct SidebarView: View {
  let store: AgentFilesStore

  @State private var projectPendingRemoval: Workspace?

  var body: some View {
    List(selection: selection) {
      Section("Instructions") {
        if let global = store.globalWorkspace {
          row(global, systemImage: "globe")
        }
        ForEach(store.projects) { project in
          row(project, systemImage: "folder")
            .contextMenu {
              if let root = project.rootPath {
                Button("Reveal in Finder") {
                  NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root)])
                }
              }
              Divider()
              Button("Remove Project", role: .destructive) {
                projectPendingRemoval = project
              }
            }
        }
      }

      Section("Library") {
        Label("Skills", systemImage: "sparkles")
          .badge(skillBadge)
          .tag(SidebarItem.skills)
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      Button {
        addProject()
      } label: {
        Label("Add Project", systemImage: "plus")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glass)
      .controlSize(.large)
      .padding(12)
    }
    .confirmationDialog(
      "Remove \(projectPendingRemoval?.name ?? "this project")?",
      isPresented: Binding(
        get: { projectPendingRemoval != nil },
        set: { if !$0 { projectPendingRemoval = nil } }
      )
    ) {
      Button("Remove Project", role: .destructive) {
        if let projectPendingRemoval {
          store.removeProject(id: projectPendingRemoval.id)
        }
        projectPendingRemoval = nil
      }
    } message: {
      Text("The instruction files stay on disk. Agent Files stops managing them.")
    }
  }

  private func row(_ workspace: Workspace, systemImage: String) -> some View {
    Label {
      HStack {
        Text(workspace.name)
          .lineLimit(1)
        Spacer(minLength: 4)
        if store.needsAttention(workspace) {
          Image(systemName: "circle.fill")
            .font(.system(size: 7))
            .foregroundStyle(.orange)
            .help("A file changed outside Agent Files")
        } else if store.template(for: workspace.id) == nil {
          Text("Set up")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
    } icon: {
      Image(systemName: systemImage)
    }
    .tag(SidebarItem.workspace(workspace.id))
  }

  private var skillBadge: Text? {
    let attention = store.skillsNeedingAttention.count
    return attention > 0 ? Text("\(attention)") : nil
  }

  private var selection: Binding<SidebarItem?> {
    Binding(
      get: { store.selection },
      set: { store.selection = $0 }
    )
  }

  private func addProject() {
    if let folder = OpenPanelService().chooseProjectFolder() {
      store.addProject(at: folder)
    }
  }
}
