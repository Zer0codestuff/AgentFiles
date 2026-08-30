import Foundation

enum AgentTool: String, Codable, CaseIterable, Identifiable, Sendable {
  case codex
  case cursor
  case openCode
  case claudeCode
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .codex:
      "Codex"
    case .cursor:
      "Cursor"
    case .openCode:
      "OpenCode"
    case .claudeCode:
      "Claude Code"
    case .custom:
      "Custom"
    }
  }

  var systemImage: String {
    switch self {
    case .codex:
      "chevron.left.forwardslash.chevron.right"
    case .cursor:
      "cursorarrow"
    case .openCode:
      "terminal"
    case .claudeCode:
      "brain.head.profile"
    case .custom:
      "doc.plaintext"
    }
  }

  static func detect(from url: URL) -> AgentTool {
    let path = url.standardizedFileURL.path.lowercased()
    let fileName = url.lastPathComponent.lowercased()

    if fileName == "claude.md" || path.contains("/.claude/") {
      return .claudeCode
    }
    if path.contains("/.codex/") {
      return .codex
    }
    if path.contains("/.cursor/") {
      return .cursor
    }
    if path.contains("/opencode/") || path.contains("/.opencode/") {
      return .openCode
    }
    return .custom
  }
}
