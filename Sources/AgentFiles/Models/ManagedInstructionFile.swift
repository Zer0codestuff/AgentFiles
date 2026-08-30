import Foundation

struct ManagedInstructionFile: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var path: String
  var displayName: String
  var tool: AgentTool

  init(
    id: UUID = UUID(),
    url: URL,
    displayName: String? = nil,
    tool: AgentTool? = nil
  ) {
    let standardizedURL = url.standardizedFileURL
    self.id = id
    self.path = standardizedURL.path
    self.displayName = displayName ?? standardizedURL.lastPathComponent
    self.tool = tool ?? AgentTool.detect(from: standardizedURL)
  }

  var url: URL {
    URL(fileURLWithPath: path).standardizedFileURL
  }
}
