import AppKit
import SwiftUI

struct FileEditorView: View {
  let store: AgentFilesStore
  let fileID: UUID?

  @State private var draft = ""
  @State private var loadedContent = ""
  @State private var loadedDigest: String?
  @State private var loadedRevision = -1
  @FocusState private var editorFocused: Bool

  var body: some View {
    Group {
      if let fileID,
        let file = store.file(id: fileID),
        let snapshot = store.snapshot(for: fileID)
      {
        editor(file: file, snapshot: snapshot)
          .id(fileID)
          .task(id: fileID) {
            load(snapshot: snapshot, force: true)
          }
          .onChange(of: snapshot.revision) { _, _ in
            if !isDirty {
              load(snapshot: snapshot, force: true)
            }
          }
      } else {
        ContentUnavailableView {
          Label("Select a File", systemImage: "doc.text")
        } description: {
          Text("Choose an instruction file to view or edit its contents.")
        }
      }
    }
  }

  @ViewBuilder
  private func editor(
    file: ManagedInstructionFile,
    snapshot: FileSnapshot
  ) -> some View {
    switch snapshot.availability {
    case .available:
      VStack(spacing: 0) {
        editorHeader(file)

        if let group = store.group(containing: file.id),
          let issue = store.issue(for: group.id)
        {
          SyncIssueBanner(
            issue: issue,
            actionTitle: "Use This File",
            action: { synchronizeUsingDraft(file: file) }
          )
          .padding(.horizontal, 18)
          .padding(.top, 14)
        } else if hasExternalChange(snapshot: snapshot) {
          ExternalChangeBanner(
            onReload: { load(snapshot: snapshot, force: true) },
            onKeepDraft: { synchronizeUsingDraft(file: file) }
          )
          .padding(.horizontal, 18)
          .padding(.top, 14)
        }

        TextEditor(text: $draft)
          .font(.system(size: 13, design: .monospaced))
          .lineSpacing(3)
          .scrollContentBackground(.hidden)
          .padding(12)
          .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
          )
          .padding(18)
          .focused($editorFocused)

        editorFooter(snapshot)
      }
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button("Sync from This File", systemImage: "arrow.triangle.2.circlepath") {
            synchronizeUsingDraft(file: file)
          }
          .disabled(store.group(containing: file.id)?.files.count ?? 0 < 2)
          .help("Copy this file to every other file in the group")

          Button("Save", systemImage: "square.and.arrow.down") {
            save(file: file)
          }
          .keyboardShortcut("s", modifiers: .command)
          .disabled(!isDirty || hasExternalChange(snapshot: snapshot))
        }
      }

    case .missing:
      unavailableView(
        title: "File Missing",
        message: "The file no longer exists at \(file.path).",
        file: file
      )

    case .unreadable(let message):
      unavailableView(
        title: "File Unreadable",
        message: message,
        file: file
      )
    }
  }

  private func editorHeader(_ file: ManagedInstructionFile) -> some View {
    HStack(spacing: 12) {
      Image(systemName: file.tool.systemImage)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 26)

      VStack(alignment: .leading, spacing: 2) {
        Text(file.displayName)
          .font(.headline)
          .lineLimit(1)
        Text(compactPath(file.path))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }

      Spacer()

      Picker(
        "Application",
        selection: Binding(
          get: { file.tool },
          set: { store.setTool($0, for: file.id) }
        )
      ) {
        ForEach(AgentTool.allCases) { tool in
          Label(tool.title, systemImage: tool.systemImage)
            .tag(tool)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: 150)

      Button("Reveal in Finder", systemImage: "folder") {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
      }
      .labelStyle(.iconOnly)
      .help("Reveal in Finder")
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private func editorFooter(_ snapshot: FileSnapshot) -> some View {
    HStack {
      if isDirty {
        Label("Unsaved", systemImage: "circle.fill")
          .foregroundStyle(.secondary)
      } else if let modificationDate = snapshot.modificationDate {
        Text("Modified \(modificationDate, style: .relative)")
          .foregroundStyle(.secondary)
      }

      Spacer()

      Text("\(draft.count.formatted()) characters")
        .foregroundStyle(.secondary)
    }
    .font(.caption)
    .padding(.horizontal, 18)
    .padding(.bottom, 12)
  }

  private func unavailableView(
    title: String,
    message: String,
    file: ManagedInstructionFile
  ) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      HStack {
        Button("Check Again") {
          store.reload(fileID: file.id)
        }
        Button("Remove from Group", role: .destructive) {
          store.removeFile(id: file.id)
        }
      }
    }
  }

  private var isDirty: Bool {
    draft != loadedContent
  }

  private func hasExternalChange(snapshot: FileSnapshot) -> Bool {
    guard isDirty, loadedRevision >= 0 else {
      return false
    }
    return snapshot.digest != loadedDigest
  }

  private func load(snapshot: FileSnapshot, force: Bool) {
    guard force || !isDirty, let content = snapshot.content else {
      return
    }
    draft = content
    loadedContent = content
    loadedDigest = snapshot.digest
    loadedRevision = snapshot.revision
  }

  private func save(file: ManagedInstructionFile) {
    guard
      store.saveEditorContent(
        draft,
        fileID: file.id,
        expectedDigest: loadedDigest
      )
    else {
      return
    }

    if let snapshot = store.snapshot(for: file.id) {
      load(snapshot: snapshot, force: true)
    }
  }

  private func synchronizeUsingDraft(file: ManagedInstructionFile) {
    if isDirty {
      guard
        store.saveEditorContent(
          draft,
          fileID: file.id,
          expectedDigest: loadedDigest,
          force: true
        )
      else {
        return
      }
    } else {
      store.synchronizeFrom(fileID: file.id, force: true)
    }

    if let snapshot = store.snapshot(for: file.id) {
      load(snapshot: snapshot, force: true)
    }
  }

  private func compactPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home + "/") {
      return "~" + path.dropFirst(home.count)
    }
    return path
  }
}

private struct SyncIssueBanner: View {
  let issue: SyncIssue
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(issue.kind == .differentContents ? .orange : .red)

      VStack(alignment: .leading, spacing: 2) {
        Text(issue.title)
          .font(.callout.weight(.semibold))
        Text(issue.message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer()

      Button(actionTitle, action: action)
        .buttonStyle(.glassProminent)
    }
    .padding(12)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct ExternalChangeBanner: View {
  let onReload: () -> Void
  let onKeepDraft: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "arrow.triangle.2.circlepath")
        .foregroundStyle(.orange)

      VStack(alignment: .leading, spacing: 2) {
        Text("File changed on disk")
          .font(.callout.weight(.semibold))
        Text("Reload the external version or explicitly keep this draft.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button("Reload", action: onReload)
      Button("Keep Draft", action: onKeepDraft)
        .buttonStyle(.glassProminent)
    }
    .padding(12)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
