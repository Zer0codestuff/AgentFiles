import CryptoKit
import Foundation

enum FileAccessError: LocalizedError, Equatable {
  case missing(URL)
  case notUTF8(URL)

  var errorDescription: String? {
    switch self {
    case .missing(let url):
      "The file no longer exists at \(url.path)."
    case .notUTF8(let url):
      "Agent Files can only manage UTF-8 text files. \(url.lastPathComponent) uses another format."
    }
  }
}

struct DiskFileSnapshot: Equatable, Sendable {
  var content: String
  var digest: String
  var modificationDate: Date?
}

struct FileAccessService: Sendable {
  func read(_ url: URL) throws -> DiskFileSnapshot {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw FileAccessError.missing(url)
    }

    let data = try Data(contentsOf: url)
    guard let content = String(data: data, encoding: .utf8) else {
      throw FileAccessError.notUTF8(url)
    }

    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return DiskFileSnapshot(
      content: content,
      digest: Self.digest(for: data),
      modificationDate: attributes?[.modificationDate] as? Date
    )
  }

  func write(_ content: String, to url: URL) throws -> DiskFileSnapshot {
    let data = Data(content.utf8)
    let existingAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    try data.write(to: url, options: .atomic)

    if let permissions = existingAttributes?[.posixPermissions] {
      try? FileManager.default.setAttributes(
        [.posixPermissions: permissions],
        ofItemAtPath: url.path
      )
    }

    return try read(url)
  }

  static func digest(for content: String) -> String {
    digest(for: Data(content.utf8))
  }

  private static func digest(for data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
