import AppKit
import SwiftUI

/// Edits the exact contents of one file. Saving decides whether the edits are shared
/// with the other files or kept only in this one.
struct InstructionEditorView: View {
  let store: AgentFilesStore
  let workspace: Workspace
  let target: WorkspaceTarget
  let template: InstructionTemplate
  @Binding var drafts: [String: String]
  let onReview: () -> Void
  let onShowDifferences: () -> Void

  @State private var sharesEdits = true
  @State private var copied = false

  var body: some View {
    VStack(spacing: 0) {
      if status == .changedOutside {
        outsideChangeBanner
          .padding(.horizontal, 20)
          .padding(.bottom, 10)
      } else if !target.writesFile {
        copyBanner
          .padding(.horizontal, 20)
          .padding(.bottom, 10)
      }

      TextEditor(text: text)
        .font(.system(size: 13, design: .monospaced))
        .lineSpacing(3)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .disabled(status == .changedOutside)

      saveBar
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
  }

  // MARK: Parts

  private var outsideChangeBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundStyle(.orange)
        .font(.title3)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(target.title) changed outside Agent Files")
          .font(.callout.weight(.semibold))
        Text("Review the change to keep it or restore the previous version.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Review", action: onReview)
        .buttonStyle(.glassProminent)
    }
    .padding(12)
    .glassEffect(.regular.tint(.orange.opacity(0.12)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  /// Cursor and Warp keep user rules in their settings, so their text is copied by hand.
  private var copyBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "doc.on.clipboard")
        .foregroundStyle(target.tint)
        .font(.title3)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(target.title) keeps rules in its settings")
          .font(.callout.weight(.semibold))
        Text("Save here, then paste this text into \(target.tools.first?.settingsRulesLocation ?? "its settings").")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rendered, forType: .string)
        copied = true
      }
      .buttonStyle(.glassProminent)
      .disabled(isDirty)
      .help(isDirty ? "Save first to copy the latest text" : "Copy the saved text")
    }
    .padding(12)
    .glassEffect(
      .regular.tint(target.tint.opacity(0.12)),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .onChange(of: rendered) { _, _ in
      copied = false
    }
  }

  private var saveBar: some View {
    GlassEffectContainer(spacing: 10) {
      HStack(spacing: 10) {
        Picker("Save edits", selection: $sharesEdits) {
          Text(workspace.kind == .global ? "For All Agents" : "For All Files").tag(true)
          Text("Only \(target.title)").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(
          sharesEdits
            ? "Edits reach every file that shares the changed lines."
            : "Edits stay in \(target.title). The other files keep their text."
        )

        Spacer(minLength: 12)

        if isDirty {
          Text("Unsaved changes")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if specificLines > 0 {
          Button(action: onShowDifferences) {
            Text(specificLines == 1 ? "1 line only here" : "\(specificLines) lines only here")
              .font(.callout)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help("Show the differences between files")
        }

        Button("Revert") {
          drafts[target.key] = nil
        }
        .buttonStyle(.glass)
        .disabled(!isDirty)

        Button("Save") {
          save()
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!isDirty || status == .changedOutside)
      }
      .padding(8)
      .padding(.leading, 4)
      .glassEffect(.regular, in: Capsule())
    }
  }

  // MARK: State

  private var status: TargetStatus {
    store.status(of: target, in: workspace)
  }

  private var rendered: String {
    template.render(for: target.key)
  }

  private var specificLines: Int {
    template.specificLineCount(for: target.key)
  }

  private var isDirty: Bool {
    drafts[target.key] != nil
  }

  private var text: Binding<String> {
    Binding(
      get: { drafts[target.key] ?? rendered },
      set: { newValue in
        drafts[target.key] = newValue == rendered ? nil : newValue
      }
    )
  }

  private func save() {
    guard let draft = drafts[target.key] else {
      return
    }
    let saved = store.save(
      draft,
      for: target.key,
      in: workspace.id,
      scope: sharesEdits ? .shared : .only(target.key)
    )
    if saved {
      drafts[target.key] = nil
    }
  }
}
