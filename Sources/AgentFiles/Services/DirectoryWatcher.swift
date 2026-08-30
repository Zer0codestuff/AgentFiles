import Darwin
import Dispatch
import Foundation

enum DirectoryWatcherError: LocalizedError {
  case cannotOpen(URL)

  var errorDescription: String? {
    switch self {
    case .cannotOpen(let url):
      "Agent Files could not watch \(url.path)."
    }
  }
}

final class DirectoryWatcher: @unchecked Sendable {
  private let descriptor: CInt
  private let source: DispatchSourceFileSystemObject

  init(
    directoryURL: URL,
    eventHandler: @escaping @Sendable () -> Void
  ) throws {
    let descriptor = open(directoryURL.path, O_EVTONLY)
    guard descriptor >= 0 else {
      throw DirectoryWatcherError.cannotOpen(directoryURL)
    }

    self.descriptor = descriptor
    source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .rename, .delete, .attrib, .extend],
      queue: DispatchQueue.global(qos: .utility)
    )
    source.setEventHandler(handler: eventHandler)
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()
  }

  deinit {
    source.cancel()
  }
}

@MainActor
final class FileObservationService {
  private var watchers: [UUID: DirectoryWatcher] = [:]

  func watch(
    file: ManagedInstructionFile,
    onChange: @escaping @MainActor @Sendable (UUID) -> Void
  ) throws {
    watchers[file.id] = try DirectoryWatcher(
      directoryURL: file.url.deletingLastPathComponent()
    ) {
      Task { @MainActor in
        onChange(file.id)
      }
    }
  }

  func stopWatching(fileID: UUID) {
    watchers[fileID] = nil
  }

  func stopAll() {
    watchers.removeAll()
  }
}
