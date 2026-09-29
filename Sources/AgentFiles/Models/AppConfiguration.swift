import Foundation

struct AppConfiguration: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 3

  var schemaVersion: Int
  var workspaces: [Workspace]
  var trackedSkills: [TrackedSkill]

  init(
    schemaVersion: Int = Self.currentSchemaVersion,
    workspaces: [Workspace] = [],
    trackedSkills: [TrackedSkill] = []
  ) {
    self.schemaVersion = schemaVersion
    self.workspaces = workspaces
    self.trackedSkills = trackedSkills
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case workspaces
    case trackedSkills
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    workspaces = try container.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? []
    trackedSkills =
      try container.decodeIfPresent([TrackedSkill].self, forKey: .trackedSkills) ?? []
  }
}
