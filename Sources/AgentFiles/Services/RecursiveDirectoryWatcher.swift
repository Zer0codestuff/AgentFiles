import CoreServices
import Foundation

/// Watches directory trees with FSEvents so edits inside nested skill folders are seen.
final class RecursiveDirectoryWatcher: @unchecked Sendable {
  private final class HandlerBox: @unchecked Sendable {
    let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
      self.handler = handler
    }
  }

  private let stream: FSEventStreamRef
  private let box: HandlerBox

  init?(
    directoryURLs: [URL],
    latency: TimeInterval = 0.4,
    eventHandler: @escaping @Sendable () -> Void
  ) {
    let paths = directoryURLs.map(\.path)
    guard !paths.isEmpty else {
      return nil
    }

    let box = HandlerBox(handler: eventHandler)
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(box).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
      guard let info else {
        return
      }
      Unmanaged<HandlerBox>.fromOpaque(info).takeUnretainedValue().handler()
    }

    guard
      let stream = FSEventStreamCreate(
        kCFAllocatorDefault,
        callback,
        &context,
        paths as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        latency,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
      )
    else {
      return nil
    }

    self.box = box
    self.stream = stream
    FSEventStreamSetDispatchQueue(
      stream,
      DispatchQueue(label: "com.gabrielemonni.AgentFiles.skills", qos: .utility)
    )
    FSEventStreamStart(stream)
  }

  deinit {
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
  }
}
