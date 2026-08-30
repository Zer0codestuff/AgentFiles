import Foundation

struct AppConfiguration: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int
  var automaticSyncEnabled: Bool
  var groups: [SyncGroup]

  init(
    schemaVersion: Int = Self.currentSchemaVersion,
    automaticSyncEnabled: Bool = true,
    groups: [SyncGroup] = []
  ) {
    self.schemaVersion = schemaVersion
    self.automaticSyncEnabled = automaticSyncEnabled
    self.groups = groups
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case automaticSyncEnabled
    case groups
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    automaticSyncEnabled =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .automaticSyncEnabled
      ) ?? true
    groups = try container.decodeIfPresent([SyncGroup].self, forKey: .groups) ?? []
  }
}
