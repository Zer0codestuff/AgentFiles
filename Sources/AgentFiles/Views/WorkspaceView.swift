import AppKit
import SwiftUI

struct WorkspaceView: View {
  let store: AgentFilesStore
  let workspace: Workspace

  @State private var mode = WorkspaceMode.edit
  @State private var selectedKey: String?
  @State private var drafts: [String: String] = [:]
  @State private var reviewTarget: WorkspaceTarget?
  @Namespace private var tabNamespace

  var body: some View {
    Group {
      if workspace.targets.isEmpty {
        ContentUnavailableView {
          Label("No Agents Found", systemImage: "circle.hexagongrid")
        } description: {
          Text("Install Claude Code, Codex, Factory, or Grok Build to manage their instructions.")
        }
      } else if let template = store.template(for: workspace.id) {
        content(template)
      } else {
        WorkspaceSetupView(store: store, workspace: workspace)
      }
    }
    .navigationTitle(workspace.name)
    .navigationSubtitle(subtitle)
    .toolbar {
      if store.template(for: workspace.id) != nil {
        ToolbarItem(placement: .principal) {
          Picker("Mode", selection: $mode) {
            ForEach(WorkspaceMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 220)
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Menu {
          ForEach(workspace.targets.filter(\.writesFile)) { target in
            Button("Reveal \(target.title)") {
              let url = FileManager.default.fileExists(atPath: target.path)
                ? target.url : target.url.deletingLastPathComponent()
              NSWorkspace.shared.activateFileViewerSelecting([url])
            }
          }
          if workspace.kind == .project {
            Divider()
            Button("Remove Project", role: .destructive) {
              store.removeProject(id: workspace.id)
            }
          }
        } label: {
          Label("More", systemImage: "ellipsis")
        }
      }
    }
    .sheet(item: $reviewTarget) { target in
      OutsideChangeSheet(store: store, workspace: workspace, target: target)
    }
  }

  private var subtitle: String {
    switch workspace.kind {
    case .global:
      "User instructions for every agent"
    case .project:
      PathFormatter.compact(workspace.rootPath ?? "")
    }
  }

  private func content(_ template: InstructionTemplate) -> some View {
    let target = workspace.target(key: selectedKey) ?? workspace.targets[0]
    return VStack(spacing: 0) {
      tabBar(template: template, selected: target)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)

      switch mode {
      case .edit:
        InstructionEditorView(
          store: store,
          workspace: workspace,
          target: target,
          template: template,
          drafts: $drafts,
          onReview: { reviewTarget = target },
          onShowDifferences: { mode = .differences }
        )
      case .differences:
        DifferencesView(store: store, workspace: workspace, template: template)
      }
    }
  }

  private func tabBar(template: InstructionTemplate, selected: WorkspaceTarget) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      GlassEffectContainer(spacing: 8) {
        HStack(spacing: 8) {
          ForEach(workspace.targets) { target in
            tab(target, isSelected: target.key == selected.key && mode == .edit)
          }
        }
      }
      .padding(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func tab(_ target: WorkspaceTarget, isSelected: Bool) -> some View {
    let status = store.status(of: target, in: workspace)
    return Button {
      withAnimation(.smooth(duration: 0.25)) {
        selectedKey = target.key
        mode = .edit
      }
    } label: {
      HStack(spacing: 8) {
        TargetIcon(target: target, size: 22)
        Text(target.title)
          .fontWeight(isSelected ? .semibold : .regular)
        if drafts[target.key] != nil {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(.secondary)
            .help("Unsaved changes")
        }
        if let symbol = status.symbol {
          Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(status.color)
            .help(status.title)
        }
      }
      .padding(.leading, 5)
      .padding(.trailing, 12)
      .padding(.vertical, 5)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .glassEffect(
      isSelected ? .regular.tint(target.tint.opacity(0.3)).interactive() : .regular.interactive(),
      in: Capsule()
    )
    .glassEffectID(target.key, in: tabNamespace)
    .help(target.readersDescription)
  }
}

private enum WorkspaceMode: String, CaseIterable, Identifiable {
  case edit
  case differences

  var id: String { rawValue }

  var title: String {
    switch self {
    case .edit:
      "Edit"
    case .differences:
      "Differences"
    }
  }
}

extension TargetStatus {
  var title: String {
    switch self {
    case .synced:
      "Up to date"
    case .willBeCreated:
      "Will be created on the next save"
    case .changedOutside:
      "Changed outside Agent Files"
    case .unreadable(let message):
      message
    case .copyOnly:
      "Copy this text into the app's settings"
    }
  }

  var symbol: String? {
    switch self {
    case .synced:
      nil
    case .willBeCreated:
      "plus.circle"
    case .changedOutside:
      "exclamationmark.circle.fill"
    case .unreadable:
      "xmark.octagon.fill"
    case .copyOnly:
      "doc.on.clipboard"
    }
  }

  var color: Color {
    switch self {
    case .synced, .willBeCreated, .copyOnly:
      .secondary
    case .changedOutside:
      .orange
    case .unreadable:
      .red
    }
  }
}
