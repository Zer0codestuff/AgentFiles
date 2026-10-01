import Foundation

struct InstructionSyncStateStore: Sendable {
  let fileURL: URL

  func load() throws -> InstructionSyncState {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init() }
    let state = try JSONDecoder().decode(InstructionSyncState.self, from: Data(contentsOf: fileURL))
    _ = try state.base.validated()
    return state
  }

  func save(_ state: InstructionSyncState) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: fileURL, options: .atomic)
  }
}
