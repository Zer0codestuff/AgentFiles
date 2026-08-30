import Foundation

enum SynchronizationMode: String, Codable, CaseIterable, Sendable {
  case wholeFile
}

struct SyncGroup: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var files: [ManagedInstructionFile]
  var automaticSyncEnabled: Bool
  var synchronizationMode: SynchronizationMode

  init(
    id: UUID = UUID(),
    name: String,
    files: [ManagedInstructionFile] = [],
    automaticSyncEnabled: Bool = true,
    synchronizationMode: SynchronizationMode = .wholeFile
  ) {
    self.id = id
    self.name = name
    self.files = files
    self.automaticSyncEnabled = automaticSyncEnabled
    self.synchronizationMode = synchronizationMode
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case files
    case automaticSyncEnabled
    case synchronizationMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try container.decode(String.self, forKey: .name)
    files = try container.decodeIfPresent([ManagedInstructionFile].self, forKey: .files) ?? []
    automaticSyncEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .automaticSyncEnabled) ?? true
    synchronizationMode =
      try container.decodeIfPresent(
        SynchronizationMode.self,
        forKey: .synchronizationMode
      ) ?? .wholeFile
  }
}
