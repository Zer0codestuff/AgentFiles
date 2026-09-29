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

/// Watches instruction files and their folders. Folder events catch files that are
/// created or atomically replaced; file events catch edits written in place.
@MainActor
final class FileObservationService {
  private var directoryWatchers: [String: DirectoryWatcher] = [:]
  private var fileWatchers: [String: DirectoryWatcher] = [:]

  func watch(
    directories: Set<String>,
    files: Set<String>,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) {
    let handler: @Sendable () -> Void = {
      Task { @MainActor in
        onChange()
      }
    }

    for path in Set(directoryWatchers.keys).subtracting(directories) {
      directoryWatchers[path] = nil
    }
    for path in directories where directoryWatchers[path] == nil {
      directoryWatchers[path] = try? DirectoryWatcher(
        directoryURL: URL(fileURLWithPath: path, isDirectory: true),
        eventHandler: handler
      )
    }

    // A replaced file gets a new inode, so file watchers are always recreated.
    fileWatchers = [:]
    for path in files {
      fileWatchers[path] = try? DirectoryWatcher(
        directoryURL: URL(fileURLWithPath: path),
        eventHandler: handler
      )
    }
  }
}
