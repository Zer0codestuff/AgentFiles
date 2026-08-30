import Foundation

protocol SynchronizationStrategy: Sendable {
  var mode: SynchronizationMode { get }

  func contentForTarget(
    sourceContent: String,
    currentTargetContent: String
  ) throws -> String
}

struct WholeFileSynchronizationStrategy: SynchronizationStrategy {
  let mode = SynchronizationMode.wholeFile

  func contentForTarget(
    sourceContent: String,
    currentTargetContent: String
  ) throws -> String {
    sourceContent
  }
}

struct SynchronizationStrategyResolver: Sendable {
  func strategy(for mode: SynchronizationMode) -> any SynchronizationStrategy {
    switch mode {
    case .wholeFile:
      WholeFileSynchronizationStrategy()
    }
  }
}
