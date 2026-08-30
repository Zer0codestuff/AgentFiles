import SwiftUI

struct GroupStatusLabel: View {
  let state: GroupSyncState

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.caption)
      .foregroundStyle(foregroundStyle)
      .lineLimit(1)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .glassEffect(.regular, in: Capsule())
  }

  private var title: String {
    switch state {
    case .empty:
      "Add files"
    case .disabled:
      "Sync off"
    case .missingFiles:
      "File missing"
    case .needsSource:
      "Choose source"
    case .synchronized:
      "In sync"
    case .conflict:
      "Conflict"
    case .error:
      "Needs attention"
    }
  }

  private var systemImage: String {
    switch state {
    case .empty:
      "plus"
    case .disabled:
      "pause.fill"
    case .missingFiles:
      "doc.badge.ellipsis"
    case .needsSource:
      "arrow.triangle.branch"
    case .synchronized:
      "checkmark"
    case .conflict:
      "exclamationmark.triangle.fill"
    case .error:
      "exclamationmark.circle.fill"
    }
  }

  private var foregroundStyle: AnyShapeStyle {
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

extension GroupSyncState {
  var shortDescription: String {
    switch self {
    case .empty:
      "Add at least two files"
    case .disabled:
      "Automatic sync is off"
    case .missingFiles:
      "One or more files are unavailable"
    case .needsSource:
      "Select the version to keep"
    case .synchronized:
      "Files have matching content"
    case .conflict:
      "Sync paused after concurrent edits"
    case .error:
      "A file needs attention"
    }
  }

  var sidebarSystemImage: String {
    switch self {
    case .synchronized:
      "checkmark.circle"
    case .disabled:
      "pause.circle"
    case .empty:
      "folder"
    case .needsSource:
      "arrow.triangle.branch"
    case .missingFiles, .conflict, .error:
      "exclamationmark.circle"
    }
  }
}
