import Foundation

/// A directory that holds one folder per skill, each containing a `SKILL.md`.
struct SkillLocation: Identifiable, Hashable, Sendable {
  static let sharedID = "shared"

  var id: String
  var title: String
  var systemImage: String
  var directory: URL
  var tool: AgentTool?
  /// Whether the owning agent is installed. The shared location is always available.
  var isAvailable: Bool

  static func defaultLocations(
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> [SkillLocation] {
    let harnessLocations = AgentTool.harnesses.compactMap { tool -> SkillLocation? in
      guard let directory = tool.skillsDirectory(in: home) else {
        return nil
      }
      return SkillLocation(
        id: tool.rawValue,
        title: tool.title,
        systemImage: tool.systemImage,
        directory: directory,
        tool: tool,
        isAvailable: tool.isInstalled(in: home)
      )
    }

    // ~/.agents/skills is the cross-agent location read by Codex, Cursor, and Warp.
    let shared = SkillLocation(
      id: sharedID,
      title: "Shared",
      systemImage: "square.stack.3d.up",
      directory: home.appendingPathComponent(".agents/skills", isDirectory: true),
      tool: nil,
      isAvailable: true
    )
    return harnessLocations + [shared]
  }
}

struct SkillInstallation: Hashable, Sendable {
  var locationID: String
  var url: URL
  var resolvedURL: URL
  var isSymbolicLink: Bool
  var digest: String
  var fileDigests: [String: String]
  var modificationDate: Date?
}

struct SkillRecord: Identifiable, Hashable, Sendable {
  var name: String
  var summary: String
  var installations: [String: SkillInstallation]

  var id: String { name }

  var variantCount: Int {
    Set(installations.values.map(\.digest)).count
  }

  func installation(in locationID: String) -> SkillInstallation? {
    installations[locationID]
  }
}

enum SkillSyncState: Equatable, Sendable {
  case synchronized
  case missing(Int)
  case differs(Int)
  case conflict
}

/// Persisted opt-in for keeping one skill identical across locations.
struct TrackedSkill: Codable, Hashable, Sendable {
  var name: String
  var locationIDs: [String]
  var baselineDigest: String
}

struct SkillFileChange: Hashable, Sendable {
  enum Kind: Hashable, Sendable {
    case added
    case modified
    case removed
  }

  var path: String
  var kind: Kind
}

struct SkillSyncTarget: Identifiable, Hashable, Sendable {
  var locationID: String
  var directory: URL
  var existed: Bool
  var expectedDigest: String?
  var changes: [SkillFileChange]

  var id: String { locationID }
}

struct SkillSyncPlan: Identifiable, Hashable, Sendable {
  var skillName: String
  var sourceLocationID: String
  var sourceDirectory: URL
  var sourceDigest: String
  var targets: [SkillSyncTarget]

  var id: String { "\(skillName)-\(sourceLocationID)" }

  var changedTargets: [SkillSyncTarget] {
    targets.filter { !$0.changes.isEmpty || !$0.existed }
  }
}

extension AgentTool {
  /// Skill locations each agent loads, including the compatibility folders it reads.
  var readableSkillLocationIDs: [String] {
    let shared = SkillLocation.sharedID
    return switch self {
    case .claudeCode:
      [AgentTool.claudeCode.rawValue]
    case .codex:
      [AgentTool.codex.rawValue, shared]
    case .factory:
      [AgentTool.factory.rawValue]
    case .cursor:
      [AgentTool.cursor.rawValue, shared, AgentTool.claudeCode.rawValue, AgentTool.codex.rawValue]
    case .grok:
      [AgentTool.grok.rawValue, AgentTool.claudeCode.rawValue]
    case .warp:
      [
        AgentTool.warp.rawValue, shared, AgentTool.claudeCode.rawValue,
        AgentTool.codex.rawValue, AgentTool.cursor.rawValue, AgentTool.factory.rawValue,
      ]
    case .openCode, .custom:
      []
    }
  }
}

extension SkillRecord {
  /// Agents that load this skill from at least one of their skill folders.
  func reachableHarnesses(among harnesses: [AgentTool]) -> [AgentTool] {
    harnesses.filter { harness in
      harness.readableSkillLocationIDs.contains { installations[$0] != nil }
    }
  }
}

enum SidebarItem: Hashable, Sendable {
  case workspace(UUID)
  case skills
}
