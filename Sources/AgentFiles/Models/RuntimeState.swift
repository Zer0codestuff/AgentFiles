import Foundation

enum FileAvailability: Equatable, Sendable {
  case available
  case missing
  case unreadable(String)
}

struct FileSnapshot: Equatable, Sendable {
  var content: String?
  var digest: String?
  var modificationDate: Date?
  var availability: FileAvailability
  var revision: Int

  static func missing(revision: Int) -> FileSnapshot {
    FileSnapshot(
      content: nil,
      digest: nil,
      modificationDate: nil,
      availability: .missing,
      revision: revision
    )
  }
}

enum SyncIssueKind: Equatable, Sendable {
  case differentContents
  case conflict
  case fileError
}

struct SyncIssue: Equatable, Identifiable, Sendable {
  var id: UUID
  var groupID: UUID
  var kind: SyncIssueKind
  var title: String
  var message: String
  var affectedFileIDs: [UUID]
  var detectedAt: Date

  init(
    id: UUID = UUID(),
    groupID: UUID,
    kind: SyncIssueKind,
    title: String,
    message: String,
    affectedFileIDs: [UUID],
    detectedAt: Date = Date()
  ) {
    self.id = id
    self.groupID = groupID
    self.kind = kind
    self.title = title
    self.message = message
    self.affectedFileIDs = affectedFileIDs
    self.detectedAt = detectedAt
  }
}

enum GroupSyncState: Equatable, Sendable {
  case empty
  case disabled
  case missingFiles
  case needsSource
  case synchronized
  case conflict
  case error
}

struct AppNotice: Identifiable, Equatable, Sendable {
  var id = UUID()
  var title: String
  var message: String
}
