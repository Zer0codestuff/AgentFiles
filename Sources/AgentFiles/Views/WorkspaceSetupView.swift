import SwiftUI

/// First run for a workspace: imports the existing files into one shared template.
struct WorkspaceSetupView: View {
  let store: AgentFilesStore
  let workspace: Workspace

  @State private var baseKey: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        GlassEffectContainer(spacing: 10) {
          HStack(spacing: 10) {
            ForEach(heroTools) { tool in
              HarnessGlyph(tool: tool, size: 52)
            }
          }
        }

        VStack(spacing: 8) {
          Text(title)
            .font(.largeTitle.weight(.semibold))
          Text(
            "Agent Files keeps one shared text and remembers which lines differ in each file. Your files stay plain Markdown."
          )
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 460)
        }

        VStack(spacing: 0) {
          ForEach(workspace.targets) { target in
            row(target)
            if target.key != workspace.targets.last?.key {
              Divider()
                .padding(.leading, 54)
            }
          }
        }
        .padding(.vertical, 6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

        if !existingTargets.isEmpty {
          Picker("Start from", selection: selectedBase) {
            ForEach(existingTargets) { target in
              Text(target.title).tag(Optional(target.key))
            }
          }
          .frame(maxWidth: 320)
        }

        VStack(spacing: 8) {
          Button {
            store.setUp(workspaceID: workspace.id, baseKey: selectedBase.wrappedValue)
          } label: {
            Text("Set Up")
              .frame(minWidth: 140)
          }
          .buttonStyle(.glassProminent)
          .controlSize(.extraLarge)

          Text(footnote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }
      .padding(40)
      .frame(maxWidth: 600)
      .frame(maxWidth: .infinity)
    }
  }

  private var title: String {
    workspace.kind == .global ? "Set Up Global Instructions" : "Set Up \(workspace.name)"
  }

  private var footnote: String {
    let missing = workspace.targets.filter { $0.writesFile && store.content(of: $0) == nil }
    if missing.isEmpty {
      return "Existing files are not changed."
    }
    let names = missing.map(\.title).joined(separator: ", ")
    return "Existing files are not changed. \(names) will be created from the shared text."
  }

  private var heroTools: [AgentTool] {
    var tools: [AgentTool] = []
    for tool in workspace.targets.flatMap(\.tools) where !tools.contains(tool) {
      tools.append(tool)
    }
    return tools
  }

  private var existingTargets: [WorkspaceTarget] {
    workspace.targets.filter { store.content(of: $0) != nil }
  }

  /// Defaults to the longest existing file, which usually holds the most complete text.
  private var selectedBase: Binding<String?> {
    Binding(
      get: {
        baseKey
          ?? existingTargets.max {
            (store.content(of: $0)?.count ?? 0) < (store.content(of: $1)?.count ?? 0)
          }?.key
      },
      set: { baseKey = $0 }
    )
  }

  private func row(_ target: WorkspaceTarget) -> some View {
    HStack(spacing: 12) {
      TargetIcon(target: target, size: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(target.title)
          .fontWeight(.medium)
        Text(target.writesFile ? PathFormatter.compact(target.path) : "Rules in app settings")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      Text(detail(for: target))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }

  private func detail(for target: WorkspaceTarget) -> String {
    guard target.writesFile else {
      return "Copy and paste"
    }
    switch store.files[target.path] {
    case .available(let content):
      let lines = LineDiff.lines(in: content).count
      return lines == 1 ? "1 line" : "\(lines) lines"
    case .unreadable:
      return "Unreadable"
    case .missing, nil:
      return "Missing"
    }
  }
}
