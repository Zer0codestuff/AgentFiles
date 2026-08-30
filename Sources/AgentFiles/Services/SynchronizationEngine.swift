import Foundation

struct SyncTargetState: Equatable, Sendable {
  var fileID: UUID
  var currentContent: String
  var baselineDigest: String?
}

struct SyncWriteOperation: Equatable, Sendable {
  var fileID: UUID
  var content: String
}

struct SyncPlan: Equatable, Sendable {
  var sourceFileID: UUID
  var operations: [SyncWriteOperation]
}

enum SyncPlanningError: LocalizedError, Equatable {
  case concurrentChanges([UUID])

  var errorDescription: String? {
    switch self {
    case .concurrentChanges:
      "More than one file changed before synchronization completed."
    }
  }
}

struct SynchronizationEngine: Sendable {
  func makePlan(
    sourceFileID: UUID,
    sourceContent: String,
    targets: [SyncTargetState],
    strategy: any SynchronizationStrategy,
    allowConcurrentOverwrite: Bool
  ) throws -> SyncPlan {
    let concurrentChanges = targets.compactMap { target -> UUID? in
      guard let baselineDigest = target.baselineDigest else {
        return nil
      }
      let currentDigest = FileAccessService.digest(for: target.currentContent)
      let matchesBaseline = currentDigest == baselineDigest
      let alreadyMatchesSource = target.currentContent == sourceContent
      return matchesBaseline || alreadyMatchesSource ? nil : target.fileID
    }

    if !allowConcurrentOverwrite, !concurrentChanges.isEmpty {
      throw SyncPlanningError.concurrentChanges(concurrentChanges)
    }

    let operations = try targets.compactMap { target -> SyncWriteOperation? in
      let replacement = try strategy.contentForTarget(
        sourceContent: sourceContent,
        currentTargetContent: target.currentContent
      )
      guard replacement != target.currentContent else {
        return nil
      }
      return SyncWriteOperation(fileID: target.fileID, content: replacement)
    }

    return SyncPlan(sourceFileID: sourceFileID, operations: operations)
  }
}
