import Foundation

/// Portable instruction content. Local paths, credentials, and skills never enter this model.
struct SyncedWorkspace: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var name: String
  var kind: WorkspaceKind
  var keys: [String]
  var template: String

  var instructions: InstructionTemplate { InstructionTemplate(parsing: template) }
}

struct InstructionSyncDocument: Codable, Equatable, Sendable {
  var schemaVersion = 1
  var workspaces: [SyncedWorkspace] = []

  func workspace(id: String) -> SyncedWorkspace? {
    workspaces.first { $0.id == id }
  }

  func validated() throws -> Self {
    guard schemaVersion == 1 else {
      throw InstructionSyncError.message("This repository needs a newer version of Agent Files.")
    }
    let globalKeys = Set(AgentTool.harnesses.map(\.templateKey))
    guard workspaces.count <= 1_000,
      Set(workspaces.map(\.id)).count == workspaces.count,
      workspaces.allSatisfy({ workspace in
        let validID = workspace.kind == .global
          ? workspace.id == "global" : UUID(uuidString: workspace.id) != nil
        let allowed = workspace.kind == .global ? globalKeys : Set(["agents", "claude"])
        return validID && !workspace.keys.isEmpty && Set(workspace.keys).isSubset(of: allowed)
          && Set(workspace.keys).count == workspace.keys.count
          && workspace.name.count <= 200
      })
    else {
      throw InstructionSyncError.message("The repository contains invalid workspace data. No files were changed.")
    }
    return self
  }

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  /// Plain Markdown copies make GitHub history useful without exposing local paths.
  func repositoryFiles() throws -> [String: String] {
    _ = try validated()
    var files = ["agent-files.json": String(decoding: try encoded(), as: UTF8.self)]
    for workspace in workspaces {
      for key in workspace.keys {
        let name = key == "claude" ? "CLAUDE.md" : "AGENTS.md"
        files["instructions/\(workspace.id)/\(key)/\(name)"] = workspace.instructions.render(for: key)
      }
    }
    return files
  }
}

struct InstructionSyncConflict: Identifiable, Equatable, Sendable {
  var id: String { local.id }
  var local: SyncedWorkspace
  var cloud: SyncedWorkspace
}

struct InstructionSyncMerge: Sendable {
  var document: InstructionSyncDocument
  var conflicts: [InstructionSyncConflict]

  /// Merge independent workspaces. Different edits to one workspace require review.
  static func merge(
    base: InstructionSyncDocument,
    local: InstructionSyncDocument,
    cloud: InstructionSyncDocument
  ) -> Self {
    var merged: [SyncedWorkspace] = []
    var conflicts: [InstructionSyncConflict] = []
    let ids = Set(local.workspaces.map(\.id)).union(cloud.workspaces.map(\.id))
    for id in ids.sorted() {
      let before = base.workspace(id: id)
      let here = local.workspace(id: id)
      let there = cloud.workspace(id: id)
      if let here, let there {
        if here == there || there == before {
          merged.append(here)
        } else if here == before {
          merged.append(there)
        } else {
          conflicts.append(.init(local: here, cloud: there))
        }
      } else {
        // Removing a local project only disconnects this computer. Missing cloud
        // records are checked by the store before it attempts a merge.
        if let remaining = there ?? here { merged.append(remaining) }
      }
    }
    return Self(document: InstructionSyncDocument(workspaces: merged), conflicts: conflicts)
  }
}

struct InstructionSyncState: Codable, Equatable, Sendable {
  var repository: String?
  var automatic = true
  var base = InstructionSyncDocument()
  var projectBindings: [String: UUID] = [:]
  var lastSyncedAt: Date?
}

struct InstructionSyncSnapshot: Sendable {
  var document: InstructionSyncDocument
  var branch: String
  var headSHA: String
  var treeSHA: String
  var missingArchive = false
}

enum InstructionSyncError: LocalizedError, Sendable {
  case message(String)
  case http(Int, String)
  case concurrentUpdate

  var errorDescription: String? {
    switch self {
    case .message(let message): message
    case .http(let code, let message): "GitHub returned \(code): \(message)"
    case .concurrentUpdate:
      "Another computer synced during this update. Your edits are safe. Sync again to review the latest version."
    }
  }
}

protocol InstructionSyncRemote: Sendable {
  func connect(repositoryName: String) async throws -> String
  func fetch(repository: String) async throws -> InstructionSyncSnapshot
  func push(
    _ document: InstructionSyncDocument, repository: String, after snapshot: InstructionSyncSnapshot
  ) async throws
}
