import Foundation

/// One instruction file inside a workspace, identified by a short key used in the template.
/// Agents that keep rules in their own settings get a copy-only target without a file.
struct WorkspaceTarget: Codable, Hashable, Identifiable, Sendable {
  var key: String
  var title: String
  var path: String
  var tools: [AgentTool]

  var id: String { key }

  var writesFile: Bool {
    !path.isEmpty
  }

  var url: URL {
    URL(fileURLWithPath: path).standardizedFileURL
  }

  var fileName: String {
    url.lastPathComponent
  }
}

enum WorkspaceKind: String, Codable, Hashable, Sendable {
  case global
  case project
}

/// A set of instruction files that share one template: the user-wide files of every
/// agent, or the instruction files of one project.
struct Workspace: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var kind: WorkspaceKind
  var rootPath: String?
  var targets: [WorkspaceTarget]

  var keys: [String] {
    targets.map(\.key)
  }

  func target(key: String?) -> WorkspaceTarget? {
    targets.first { $0.key == key }
  }

  static func global(
    id: UUID = UUID(),
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> Workspace {
    Workspace(id: id, name: "Global", kind: .global, rootPath: nil, targets: globalTargets(home: home))
  }

  /// One target per installed agent. Agents without a user-wide file get a copy-only target.
  static func globalTargets(home: URL) -> [WorkspaceTarget] {
    AgentTool.harnesses.compactMap { tool in
      guard tool.isInstalled(in: home) else {
        return nil
      }
      return WorkspaceTarget(
        key: tool.templateKey,
        title: tool.title,
        path: tool.globalInstructionsURL(in: home)?.standardizedFileURL.path ?? "",
        tools: [tool]
      )
    }
  }

  static func project(at folder: URL) -> Workspace {
    let root = folder.standardizedFileURL
    let agentsReaders = AgentTool.harnesses.filter { $0.projectInstructionsFileName == "AGENTS.md" }
    return Workspace(
      id: UUID(),
      name: root.lastPathComponent,
      kind: .project,
      rootPath: root.path,
      targets: [
        WorkspaceTarget(
          key: "agents",
          title: "AGENTS.md",
          path: root.appendingPathComponent("AGENTS.md").path,
          tools: agentsReaders
        ),
        WorkspaceTarget(
          key: "claude",
          title: "CLAUDE.md",
          path: root.appendingPathComponent("CLAUDE.md").path,
          tools: [.claudeCode]
        ),
      ]
    )
  }
}

extension AgentTool {
  /// The short name used in template markers.
  var templateKey: String {
    switch self {
    case .claudeCode:
      "claude"
    default:
      rawValue.lowercased()
    }
  }
}

enum FileAvailability: Equatable, Sendable {
  case available(String)
  case missing
  case unreadable(String)

  var content: String? {
    if case .available(let content) = self {
      return content
    }
    return nil
  }
}

enum TargetStatus: Equatable, Sendable {
  case synced
  case willBeCreated
  case changedOutside
  case unreadable(String)
  case copyOnly
}

struct AppNotice: Identifiable, Equatable, Sendable {
  var id = UUID()
  var title: String
  var message: String
}
