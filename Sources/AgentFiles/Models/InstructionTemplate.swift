import Foundation

/// Which instruction files receive a template line.
enum TemplateAudience: Hashable, Sendable {
  case everyone
  case only(Set<String>)
  case except(Set<String>)

  func includes(_ key: String) -> Bool {
    switch self {
    case .everyone:
      true
    case .only(let keys):
      keys.contains(key)
    case .except(let keys):
      !keys.contains(key)
    }
  }

  /// The audience without `key`, or nil when nobody would receive the line.
  func removing(_ key: String) -> TemplateAudience? {
    switch self {
    case .everyone:
      return .except([key])
    case .only(let keys):
      let remaining = keys.subtracting([key])
      return remaining.isEmpty ? nil : .only(remaining)
    case .except(let keys):
      return .except(keys.union([key]))
    }
  }
}

struct TemplateLine: Hashable, Sendable {
  var text: String
  var audience: TemplateAudience
}

enum EditScope: Hashable, Sendable {
  /// Edits change the line for every file that currently shares it.
  case shared
  /// Edits only change the file being edited.
  case only(String)
}

/// A place where instruction files differ, with the text each file receives.
struct TemplateVariation: Identifiable, Hashable, Sendable {
  struct Alternative: Identifiable, Hashable, Sendable {
    var keys: [String]
    var lines: [String]

    var id: String { keys.joined(separator: ",") }
  }

  var range: Range<Int>
  var section: String?
  var alternatives: [Alternative]

  var id: Int { range.lowerBound }
}

/// One shared document with per-file lines. Rendering a key produces the exact
/// contents of that file, so instruction files never contain markers.
struct InstructionTemplate: Hashable, Sendable {
  private static let onlyPrefix = "<!-- only:"
  private static let exceptPrefix = "<!-- except:"
  private static let endMarker = "<!-- end -->"

  var lines: [TemplateLine]

  init(lines: [TemplateLine]) {
    self.lines = lines
  }

  init(shared content: String) {
    lines = LineDiff.lines(in: content).map { TemplateLine(text: $0, audience: .everyone) }
  }

  // MARK: Serialization

  init(parsing text: String) {
    var parsed: [TemplateLine] = []
    var audience = TemplateAudience.everyone

    for line in LineDiff.lines(in: text) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if let keys = Self.markerKeys(trimmed, prefix: Self.onlyPrefix) {
        audience = .only(keys)
      } else if let keys = Self.markerKeys(trimmed, prefix: Self.exceptPrefix) {
        audience = .except(keys)
      } else if trimmed == Self.endMarker {
        audience = .everyone
      } else {
        parsed.append(TemplateLine(text: line, audience: audience))
      }
    }
    lines = parsed
  }

  var text: String {
    var output: [String] = []
    var index = 0
    while index < lines.count {
      let audience = lines[index].audience
      var end = index
      while end < lines.count, lines[end].audience == audience {
        end += 1
      }
      let block = lines[index..<end].map(\.text)
      switch audience {
      case .everyone:
        output += block
      case .only(let keys):
        output += ["\(Self.onlyPrefix) \(keys.sorted().joined(separator: ", ")) -->"]
          + block + [Self.endMarker]
      case .except(let keys):
        output += ["\(Self.exceptPrefix) \(keys.sorted().joined(separator: ", ")) -->"]
          + block + [Self.endMarker]
      }
      index = end
    }
    return output.joined(separator: "\n")
  }

  private static func markerKeys(_ line: String, prefix: String) -> Set<String>? {
    guard line.hasPrefix(prefix), line.hasSuffix("-->") else {
      return nil
    }
    let body = line.dropFirst(prefix.count).dropLast(3)
    return Set(
      body.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    )
  }

  // MARK: Rendering

  func renderedIndices(for key: String) -> [Int] {
    lines.indices.filter { lines[$0].audience.includes(key) }
  }

  func render(for key: String) -> String {
    renderedIndices(for: key).map { lines[$0].text }.joined(separator: "\n")
  }

  /// Number of lines that only some files receive, counted for `key`.
  func specificLineCount(for key: String) -> Int {
    lines.filter { $0.audience != .everyone && $0.audience.includes(key) }.count
  }

  // MARK: Editing

  /// Applies an edited copy of one file back into the template.
  func applying(edited content: String, from key: String, scope: EditScope) -> InstructionTemplate {
    var result = lines
    let rendered = renderedIndices(for: key)
    let old = rendered.map { lines[$0].text }
    let hunks = LineDiff.hunks(from: old, to: LineDiff.lines(in: content))

    // Work backwards so earlier template indices stay valid.
    for hunk in hunks.reversed() {
      let affected = hunk.range.map { rendered[$0] }
      let insertAt: Int
      if let last = affected.last {
        insertAt = last + 1
      } else if hunk.range.lowerBound > 0 {
        insertAt = rendered[hunk.range.lowerBound - 1] + 1
      } else {
        insertAt = rendered.first ?? result.count
      }

      switch scope {
      case .only(let onlyKey):
        let added = hunk.replacement.map {
          TemplateLine(text: $0, audience: .only([onlyKey]))
        }
        result.insert(contentsOf: added, at: insertAt)
        for index in affected.reversed() {
          if let audience = result[index].audience.removing(onlyKey) {
            result[index].audience = audience
          } else {
            result.remove(at: index)
          }
        }

      case .shared:
        let audience = sharedAudience(
          affected: affected,
          insertionPoint: hunk.range.lowerBound,
          rendered: rendered
        )
        let added = hunk.replacement.map { TemplateLine(text: $0, audience: audience) }
        result.insert(contentsOf: added, at: insertAt)
        for index in affected.reversed() {
          result.remove(at: index)
        }
      }
    }

    return InstructionTemplate(lines: result)
  }

  private func sharedAudience(
    affected: [Int],
    insertionPoint: Int,
    rendered: [Int]
  ) -> TemplateAudience {
    if let first = affected.first {
      let audience = lines[first].audience
      return affected.allSatisfy { lines[$0].audience == audience } ? audience : .everyone
    }
    guard insertionPoint > 0, insertionPoint < rendered.count else {
      return .everyone
    }
    let previous = lines[rendered[insertionPoint - 1]].audience
    let next = lines[rendered[insertionPoint]].audience
    return previous == next ? previous : .everyone
  }

  /// Builds a template from existing files. The base file becomes the shared text and
  /// every difference in the other files is kept only for that file.
  static func importing(
    base: String,
    others: [(key: String, content: String)]
  ) -> InstructionTemplate {
    others.reduce(InstructionTemplate(shared: base)) { template, other in
      template.applying(edited: other.content, from: other.key, scope: .only(other.key))
    }
  }

  /// Drops lines nobody receives and simplifies audiences for the given files.
  func pruned(keys: [String]) -> InstructionTemplate {
    let all = Set(keys)
    let simplified = lines.compactMap { line -> TemplateLine? in
      var line = line
      switch line.audience {
      case .everyone:
        break
      case .only(let only):
        if only.isDisjoint(with: all) {
          return nil
        }
        if all.isSubset(of: only) {
          line.audience = .everyone
        }
      case .except(let except):
        if all.isSubset(of: except) {
          return nil
        }
        if except.isDisjoint(with: all) {
          line.audience = .everyone
        }
      }
      return line
    }
    return InstructionTemplate(lines: simplified)
  }

  // MARK: Variations

  func variations(keys: [String]) -> [TemplateVariation] {
    var result: [TemplateVariation] = []
    var index = 0
    var section: String?

    while index < lines.count {
      guard lines[index].audience != .everyone else {
        if lines[index].text.hasPrefix("#") {
          section = lines[index].text
        }
        index += 1
        continue
      }

      var end = index
      while end < lines.count, lines[end].audience != .everyone {
        end += 1
      }

      var alternatives: [TemplateVariation.Alternative] = []
      for key in keys {
        let text = lines[index..<end].filter { $0.audience.includes(key) }.map(\.text)
        if let existing = alternatives.firstIndex(where: { $0.lines == text }) {
          alternatives[existing].keys.append(key)
        } else {
          alternatives.append(TemplateVariation.Alternative(keys: [key], lines: text))
        }
      }

      if alternatives.count > 1 {
        result.append(
          TemplateVariation(range: index..<end, section: section, alternatives: alternatives)
        )
      }
      index = end
    }
    return result
  }

  /// Replaces a variation with one set of lines shared by every file.
  func resolving(_ variation: TemplateVariation, with chosen: [String]) -> InstructionTemplate {
    var result = lines
    result.replaceSubrange(
      variation.range,
      with: chosen.map { TemplateLine(text: $0, audience: .everyone) }
    )
    return InstructionTemplate(lines: result)
  }
}
