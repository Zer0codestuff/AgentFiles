import Foundation

/// Persists one template per workspace as a readable Markdown file.
struct TemplateStore: Sendable {
  let directory: URL

  init(directory: URL = AppDirectories.templates) {
    self.directory = directory
  }

  func load(workspaceID: UUID) throws -> InstructionTemplate? {
    let url = fileURL(for: workspaceID)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return InstructionTemplate(parsing: try String(contentsOf: url, encoding: .utf8))
  }

  func save(_ template: InstructionTemplate, workspaceID: UUID) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(template.text.utf8).write(to: fileURL(for: workspaceID), options: .atomic)
  }

  func remove(workspaceID: UUID) {
    try? FileManager.default.removeItem(at: fileURL(for: workspaceID))
  }

  private func fileURL(for workspaceID: UUID) -> URL {
    directory.appendingPathComponent("\(workspaceID.uuidString).md")
  }
}
