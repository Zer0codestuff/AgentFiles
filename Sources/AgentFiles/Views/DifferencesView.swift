import SwiftUI

/// Compares every file with the selected file, one GitHub-style diff per file.
struct DifferencesView: View {
  let store: AgentFilesStore
  let workspace: Workspace
  let template: InstructionTemplate
  let reference: WorkspaceTarget

  @State private var pendingChoice: PendingChoice?
  @State private var collapsed: Set<String> = []
  @State private var expanded: Set<String> = []

  var body: some View {
    let variations = template.variations(keys: workspace.keys)
    let others = workspace.targets.filter { $0.key != reference.key }
    let comparisons = others.map {
      (target: $0, comparison: template.comparison(
        of: $0.key, against: reference.key, variations: variations
      ))
    }
    let changed = comparisons.filter { !$0.comparison.isIdentical }
    let identical = comparisons.filter(\.comparison.isIdentical).map(\.target)

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
            summary(changed: changed.count, total: others.count)

            ForEach(changed, id: \.target.key) { item in
              fileCard(item.target, item.comparison)
            }

            if !identical.isEmpty {
              identicalRow(identical)
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 4)
          .padding(.bottom, 16)
          .frame(maxWidth: 1_100)
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
      Button("Use \(choice.source.title)'s Version for All") {
        store.resolve(choice.variation, with: choice.lines, in: workspace.id)
        pendingChoice = nil
      }
    } message: { _ in
      Text("The other versions of this passage are replaced. Every file is backed up before it changes.")
    }
  }

  // MARK: Parts

  private func summary(changed: Int, total: Int) -> some View {
    HStack(spacing: 6) {
      Text(changed == 1 ? "1 of \(total) files differs from" : "\(changed) of \(total) files differ from")
      TargetIcon(target: reference, size: 16)
      Text(reference.title)
        .fontWeight(.semibold)
      Spacer()
      Text("Select a tab to compare with another file")
        .foregroundStyle(.tertiary)
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 4)
  }

  private func fileCard(_ target: WorkspaceTarget, _ comparison: FileComparison) -> some View {
    let isCollapsed = collapsed.contains(target.key)
    return VStack(spacing: 0) {
      Button {
        withAnimation(.smooth(duration: 0.2)) {
          if isCollapsed {
            collapsed.remove(target.key)
          } else {
            collapsed.insert(target.key)
          }
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
          TargetIcon(target: target, size: 20)
          Text(target.title)
            .fontWeight(.semibold)
          Text(target.writesFile ? PathFormatter.compact(target.path) : "Copied into settings")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer(minLength: 12)
          DiffStat(additions: comparison.additions, deletions: comparison.deletions)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if !isCollapsed {
        Divider()
        VStack(spacing: 0) {
          ForEach(comparison.segments) { segment in
            switch segment {
            case .hunk(let hunk):
              hunkView(hunk, target: target)
            case .unchanged(let lines):
              unchangedView(lines, id: "\(target.key)-\(segment.id)")
            }
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func hunkView(_ hunk: FileComparison.Hunk, target: WorkspaceTarget) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text(hunk.variation?.section.map(cleanHeading) ?? "Start of file")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer()
        if let variation = hunk.variation {
          useForAllMenu(variation, target: target)
        }
      }
      .padding(.leading, 14)
      .padding(.trailing, 8)
      .padding(.vertical, 5)
      .background(Color.accentColor.opacity(0.08))

      ForEach(hunk.lines) { line in
        DiffLineRow(line: line)
      }
    }
  }

  private func useForAllMenu(_ variation: TemplateVariation, target: WorkspaceTarget) -> some View {
    Menu("Use for All") {
      ForEach([reference, target]) { source in
        if let lines = variation.lines(for: source.key) {
          Button("\(source.title)'s Version") {
            pendingChoice = PendingChoice(variation: variation, lines: lines, source: source)
          }
        }
      }
    }
    .menuStyle(.button)
    .buttonStyle(.glass)
    .controlSize(.mini)
    .fixedSize()
  }

  @ViewBuilder
  private func unchangedView(_ lines: [FileComparison.Line], id: String) -> some View {
    if expanded.contains(id) {
      ForEach(lines) { line in
        DiffLineRow(line: line)
      }
    } else {
      Button {
        withAnimation(.smooth(duration: 0.2)) {
          _ = expanded.insert(id)
        }
      } label: {
        Label(
          lines.count == 1 ? "1 unchanged line" : "\(lines.count) unchanged lines",
          systemImage: "arrow.up.and.down"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.05))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Show unchanged lines")
    }
  }

  private func identicalRow(_ targets: [WorkspaceTarget]) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text("Same as \(reference.title)")
        .foregroundStyle(.secondary)
      ForEach(targets) { target in
        HStack(spacing: 5) {
          TargetIcon(target: target, size: 16)
          Text(target.title)
        }
      }
      Spacer()
    }
    .font(.callout)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func cleanHeading(_ heading: String) -> String {
    heading.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
  }
}

/// One line of a diff: line numbers, a +/- sign, and the text with changed words
/// highlighted.
private struct DiffLineRow: View {
  let line: FileComparison.Line

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      number(line.oldNumber)
      number(line.newNumber)
      Text(sign)
        .foregroundStyle(signColor)
        .frame(width: 20)
      Text(attributedText)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 14)
    }
    .font(.system(size: 12, design: .monospaced))
    .padding(.vertical, 2)
    .background(tint.map { $0.opacity(0.12) } ?? .clear)
  }

  private func number(_ value: Int?) -> some View {
    Text(value.map(String.init) ?? "")
      .foregroundStyle(.tertiary)
      .frame(width: 38, alignment: .trailing)
      .padding(.trailing, 4)
  }

  private var sign: String {
    switch line.kind {
    case .context:
      " "
    case .removed:
      "−"
    case .added:
      "+"
    }
  }

  private var tint: Color? {
    switch line.kind {
    case .context:
      nil
    case .removed:
      .red
    case .added:
      .green
    }
  }

  private var signColor: Color {
    tint ?? .secondary
  }

  private var attributedText: AttributedString {
    guard let words = line.words, let tint else {
      return AttributedString(line.text.isEmpty ? " " : line.text)
    }
    var result = AttributedString()
    for row in words {
      switch row {
      case .same(let text):
        result += AttributedString(text)
      case .removed(let text), .added(let text):
        var changed = AttributedString(text)
        changed.backgroundColor = tint.opacity(0.35)
        result += changed
      }
    }
    return result
  }
}

/// Added and removed line counts with GitHub's five-block bar.
private struct DiffStat: View {
  let additions: Int
  let deletions: Int

  var body: some View {
    HStack(spacing: 8) {
      HStack(spacing: 4) {
        Text("+\(additions)")
          .foregroundStyle(.green)
        Text("−\(deletions)")
          .foregroundStyle(.red)
      }
      .font(.callout.monospacedDigit().weight(.medium))

      HStack(spacing: 2) {
        ForEach(0..<5, id: \.self) { index in
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color(at: index))
            .frame(width: 8, height: 8)
        }
      }
    }
  }

  private func color(at index: Int) -> Color {
    let total = additions + deletions
    guard total > 0 else {
      return .secondary.opacity(0.3)
    }
    let filled = min(5, max(1, total))
    let green = Int((Double(additions) / Double(total) * Double(filled)).rounded())
    if index < green {
      return .green
    }
    if index < filled {
      return .red
    }
    return .secondary.opacity(0.3)
  }
}

private struct PendingChoice {
  var variation: TemplateVariation
  var lines: [String]
  var source: WorkspaceTarget
}

extension TemplateVariation {
  /// The text one file receives in this passage.
  func lines(for key: String) -> [String]? {
    alternatives.first { $0.keys.contains(key) }?.lines
  }
}
