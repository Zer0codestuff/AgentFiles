import Foundation
import Testing

@testable import AgentFiles

@Suite("Synchronization engine")
struct SynchronizationEngineTests {
  @Test
  func wholeFileStrategyCopiesSourceContent() throws {
    let strategy = WholeFileSynchronizationStrategy()
    let result = try strategy.contentForTarget(
      sourceContent: "shared instructions",
      currentTargetContent: "old instructions"
    )

    #expect(result == "shared instructions")
  }

  @Test
  func planWritesOnlyTargetsWithDifferentContent() throws {
    let sourceID = UUID()
    let changedTargetID = UUID()
    let matchingTargetID = UUID()
    let engine = SynchronizationEngine()

    let plan = try engine.makePlan(
      sourceFileID: sourceID,
      sourceContent: "new",
      targets: [
        SyncTargetState(
          fileID: changedTargetID,
          currentContent: "old",
          baselineDigest: FileAccessService.digest(for: "old")
        ),
        SyncTargetState(
          fileID: matchingTargetID,
          currentContent: "new",
          baselineDigest: FileAccessService.digest(for: "new")
        ),
      ],
      strategy: WholeFileSynchronizationStrategy(),
      allowConcurrentOverwrite: false
    )

    #expect(
      plan.operations == [
        SyncWriteOperation(fileID: changedTargetID, content: "new")
      ]
    )
  }

  @Test
  func planStopsWhenAnotherTargetChanged() {
    let sourceID = UUID()
    let targetID = UUID()
    let engine = SynchronizationEngine()

    #expect(throws: SyncPlanningError.concurrentChanges([targetID])) {
      try engine.makePlan(
        sourceFileID: sourceID,
        sourceContent: "source edit",
        targets: [
          SyncTargetState(
            fileID: targetID,
            currentContent: "independent edit",
            baselineDigest: FileAccessService.digest(for: "old")
          )
        ],
        strategy: WholeFileSynchronizationStrategy(),
        allowConcurrentOverwrite: false
      )
    }
  }

  @Test
  func explicitSourceCanOverwriteConcurrentTarget() throws {
    let sourceID = UUID()
    let targetID = UUID()
    let engine = SynchronizationEngine()

    let plan = try engine.makePlan(
      sourceFileID: sourceID,
      sourceContent: "chosen source",
      targets: [
        SyncTargetState(
          fileID: targetID,
          currentContent: "independent edit",
          baselineDigest: FileAccessService.digest(for: "old")
        )
      ],
      strategy: WholeFileSynchronizationStrategy(),
      allowConcurrentOverwrite: true
    )

    #expect(
      plan.operations == [
        SyncWriteOperation(fileID: targetID, content: "chosen source")
      ]
    )
  }
}
