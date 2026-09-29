import Foundation

enum AgentTool: String, Codable, CaseIterable, Identifiable, Sendable {
  case claudeCode
  case codex
  case factory
  case cursor
  case grok
  case warp
  case openCode
  case custom

  /// The coding agents Agent Files detects and manages out of the box.
  static let harnesses: [AgentTool] = [.claudeCode, .codex, .factory, .cursor, .grok, .warp]

  var id: String { rawValue }

  var title: String {
    switch self {
    case .claudeCode:
      "Claude Code"
    case .codex:
      "Codex"
    case .factory:
      "Factory"
    case .cursor:
      "Cursor"
    case .grok:
      "Grok Build"
    case .warp:
      "Warp"
    case .openCode:
      "OpenCode"
    case .custom:
      "Custom"
    }
  }

  var systemImage: String {
    switch self {
    case .claudeCode:
      "asterisk"
    case .codex:
      "curlybraces"
    case .factory:
      "gearshape.2"
    case .cursor:
      "cursorarrow.rays"
    case .grok:
      "bolt"
    case .warp:
      "terminal"
    case .openCode:
      "chevron.left.forwardslash.chevron.right"
    case .custom:
      "doc.plaintext"
    }
  }

  /// The per-user configuration directory, relative to the home directory.
  var homeDirectoryName: String? {
    switch self {
    case .claudeCode:
      ".claude"
    case .codex:
      ".codex"
    case .factory:
      ".factory"
    case .cursor:
      ".cursor"
    case .grok:
      ".grok"
    case .warp:
      ".warp"
    case .openCode:
      ".config/opencode"
    case .custom:
      nil
    }
  }

  /// The file each agent reads as its user-wide instructions. Cursor and Warp keep
  /// user rules in their own settings, so they only read project instruction files.
  var globalInstructionsFileName: String? {
    switch self {
    case .claudeCode:
      "CLAUDE.md"
    case .codex, .factory, .grok, .openCode:
      "AGENTS.md"
    case .cursor, .warp, .custom:
      nil
    }
  }

  /// Where agents without a user-wide file keep their rules.
  var settingsRulesLocation: String? {
    switch self {
    case .cursor:
      "Cursor Settings > Rules"
    case .warp:
      "Warp Settings > AI > Rules"
    default:
      nil
    }
  }

  /// The instruction file each agent reads at the root of a project.
  var projectInstructionsFileName: String? {
    switch self {
    case .claudeCode:
      "CLAUDE.md"
    case .codex, .factory, .cursor, .grok, .warp, .openCode:
      "AGENTS.md"
    case .custom:
      nil
    }
  }

  func homeDirectory(in home: URL) -> URL? {
    homeDirectoryName.map { home.appendingPathComponent($0, isDirectory: true) }
  }

  func globalInstructionsURL(in home: URL) -> URL? {
    guard let directory = homeDirectory(in: home), let globalInstructionsFileName else {
      return nil
    }
    return directory.appendingPathComponent(globalInstructionsFileName)
  }

  func skillsDirectory(in home: URL) -> URL? {
    guard self != .custom, let directory = homeDirectory(in: home) else {
      return nil
    }
    return directory.appendingPathComponent("skills", isDirectory: true)
  }

  func isInstalled(in home: URL) -> Bool {
    guard let directory = homeDirectory(in: home) else {
      return false
    }
    return FileManager.default.fileExists(atPath: directory.path)
  }

  init(from decoder: Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    self = AgentTool(rawValue: rawValue) ?? .custom
  }

  static func detect(from url: URL) -> AgentTool {
    let path = url.standardizedFileURL.path.lowercased()
    let fileName = url.lastPathComponent.lowercased()

    if fileName == "claude.md" || path.contains("/.claude/") {
      return .claudeCode
    }
    if fileName == "warp.md" || path.contains("/.warp/") {
      return .warp
    }
    if path.contains("/.codex/") {
      return .codex
    }
    if path.contains("/.factory/") {
      return .factory
    }
    if path.contains("/.cursor/") {
      return .cursor
    }
    if path.contains("/.grok/") {
      return .grok
    }
    if path.contains("/opencode/") || path.contains("/.opencode/") {
      return .openCode
    }
    return .custom
  }
}
