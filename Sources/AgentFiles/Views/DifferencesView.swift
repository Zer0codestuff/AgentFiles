import SwiftUI

/// Lists every place where the files differ, side by side.
struct DifferencesView: View {
  let store: AgentFilesStore
  let workspace: Workspace
  let template: InstructionTemplate

  @State private var pendingChoice: PendingChoice?

  var body: some View {
    let variations = template.variations(keys: workspace.keys)
    Group {
      if variations.isEmpty {
        ContentUnavailableView {
          Label("No Differences", systemImage: "checkmark.circle")
        } description: {
          Text(
            workspace.kind == .global
              ? "Every agent receives the same instructions."
              : "AGENTS.md and CLAUDE.md contain the same instructions."
          )
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            Text(
              variations.count == 1
                ? "1 place where the files differ"
                : "\(variations.count) places where the files differ"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            ForEach(variations) { variation in
              card(variation)
            }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .frame(maxWidth: 920)
          .frame(maxWidth: .infinity)
        }
      }
    }
    .confirmationDialog(
      "Use this text for every file?",
      isPresented: Binding(
        get: { pendingChoice != nil },
        set: { if !$0 { pendingChoice = nil } }
      ),
      presenting: pendingChoice
    ) { choice in
      Button("Use for All") {
        store.resolve(choice.variation, with: choice.lines, in: workspace.id)
        pendingChoice = nil
      }
    } message: { _ in
      Text("The other versions of this passage are replaced. Every file is backed up before it changes.")
    }
  }

  private func card(_ variation: TemplateVariation) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(variation.section.map(cleanHeading) ?? "Start of file")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      ForEach(variation.alternatives) { alternative in
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(targets(for: alternative)) { target in
              HStack(spacing: 6) {
                TargetIcon(target: target, size: 18)
                Text(target.title)
                  .font(.caption.weight(.medium))
              }
            }
          }
          .frame(width: 130, alignment: .leading)

          Text(passage(alternative.lines))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(alternative.lines.isEmpty ? .tertiary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
              .background.opacity(0.5),
              in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

          Button("Use for All") {
            pendingChoice = PendingChoice(variation: variation, lines: alternative.lines)
          }
          .buttonStyle(.glass)
          .controlSize(.small)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private func targets(for alternative: TemplateVariation.Alternative) -> [WorkspaceTarget] {
    alternative.keys.compactMap { workspace.target(key: $0) }
  }

  private func passage(_ lines: [String]) -> String {
    lines.isEmpty ? "Nothing here" : lines.joined(separator: "\n")
  }

  private func cleanHeading(_ heading: String) -> String {
    heading.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
  }
}

private struct PendingChoice {
  var variation: TemplateVariation
  var lines: [String]
}
