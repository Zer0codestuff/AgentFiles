import SwiftUI

/// Shows an edit made in another app and lets the user keep or discard it.
struct OutsideChangeSheet: View {
  let store: AgentFilesStore
  let workspace: Workspace
  let target: WorkspaceTarget

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        TargetIcon(target: target, size: 40)
        VStack(alignment: .leading, spacing: 3) {
          Text("\(target.title) changed outside Agent Files")
            .font(.title3.weight(.semibold))
          Text(PathFormatter.compact(target.path))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(20)

      Divider()

      DiffView(old: expected, new: current)

      Divider()

      HStack(spacing: 10) {
        Button("Discard Change", role: .destructive) {
          store.discardOutsideChange(key: target.key, in: workspace.id)
          dismiss()
        }
        .help("Restore the version Agent Files wrote. The changed file is backed up first.")

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("Keep Only in \(target.title)") {
          store.acceptOutsideChange(key: target.key, in: workspace.id, scope: .only(target.key))
          dismiss()
        }
        .buttonStyle(.glass)

        Button(workspace.kind == .global ? "Share with All Agents" : "Share with All Files") {
          store.acceptOutsideChange(key: target.key, in: workspace.id, scope: .shared)
          dismiss()
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
      }
      .padding(16)
    }
    .frame(width: 760, height: 560)
  }

  private var expected: String {
    store.template(for: workspace.id)?.render(for: target.key) ?? ""
  }

  private var current: String {
    store.content(of: target) ?? ""
  }
}

/// A unified line diff that folds long unchanged stretches.
struct DiffView: View {
  let old: String
  let new: String

  private static let context = 3

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .row(let row):
            line(row)
          case .folded(let count):
            Text(count == 1 ? "1 unchanged line" : "\(count) unchanged lines")
              .font(.caption)
              .foregroundStyle(.tertiary)
              .padding(.vertical, 6)
              .padding(.leading, 34)
          }
        }
      }
      .padding(.vertical, 10)
    }
  }

  private func line(_ row: LineDiff.Row) -> some View {
    let (sign, text, color): (String, String, Color?) =
      switch row {
      case .same(let text): (" ", text, nil)
      case .removed(let text): ("−", text, .red)
      case .added(let text): ("+", text, .green)
      }
    return HStack(alignment: .top, spacing: 10) {
      Text(sign)
        .foregroundStyle(color ?? .secondary)
        .frame(width: 14)
      Text(text.isEmpty ? " " : text)
        .foregroundStyle(color == nil ? .secondary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.system(size: 12, design: .monospaced))
    .textSelection(.enabled)
    .padding(.horizontal, 14)
    .padding(.vertical, 1)
    .background(color?.opacity(0.12) ?? .clear)
  }

  private enum Block {
    case row(LineDiff.Row)
    case folded(Int)
  }

  private var blocks: [Block] {
    let rows = LineDiff.rows(from: old, to: new)
    let changed = rows.indices.filter {
      if case .same = rows[$0] { return false }
      return true
    }
    var visible = Set<Int>()
    for index in changed {
      let lower = max(index - Self.context, 0)
      let upper = min(index + Self.context, rows.count - 1)
      visible.formUnion(lower...upper)
    }

    var result: [Block] = []
    var hidden = 0
    for index in rows.indices {
      if visible.contains(index) {
        if hidden > 0 {
          result.append(.folded(hidden))
          hidden = 0
        }
        result.append(.row(rows[index]))
      } else {
        hidden += 1
      }
    }
    if hidden > 0 {
      result.append(.folded(hidden))
    }
    return result
  }
}
