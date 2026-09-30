import Foundation

/// A GitHub-style comparison of one file against a reference file. It is built from the
/// template, so every change knows the variation it belongs to.
struct FileComparison: Sendable {
  enum Kind: Sendable {
    case context
    case removed
    case added
  }

  struct Line: Identifiable, Sendable {
    var id: Int
    var kind: Kind
    var text: String
    var oldNumber: Int?
    var newNumber: Int?
    /// Word-level changes against the paired line, when the two lines are similar.
    var words: [LineDiff.Row]?
    var templateIndex: Int?
  }

  struct Hunk: Identifiable, Sendable {
    var lines: [Line]
    var variation: TemplateVariation?

    var id: Int { lines.first?.id ?? 0 }
  }

  enum Segment: Identifiable, Sendable {
    case hunk(Hunk)
    case unchanged([Line])

    var id: Int {
      switch self {
      case .hunk(let hunk):
        hunk.id
      case .unchanged(let lines):
        -(lines.first?.id ?? 0) - 1
      }
    }
  }

  var segments: [Segment]
  var additions: Int
  var deletions: Int

  var isIdentical: Bool {
    additions == 0 && deletions == 0
  }
}

extension InstructionTemplate {
  /// Compares the file rendered for `key` with the file rendered for `reference`.
  func comparison(
    of key: String,
    against reference: String,
    variations: [TemplateVariation],
    context: Int = 3
  ) -> FileComparison {
    var lines = comparedLines(of: key, against: reference)
    var oldNumber = 0
    var newNumber = 0
    for index in lines.indices {
      if lines[index].kind != .added {
        oldNumber += 1
        lines[index].oldNumber = oldNumber
      }
      if lines[index].kind != .removed {
        newNumber += 1
        lines[index].newNumber = newNumber
      }
    }

    // Consecutive changes that belong to the same variation form one hunk.
    var groups: [(range: Range<Int>, variation: TemplateVariation?)] = []
    for index in lines.indices where lines[index].kind != .context {
      let variation = lines[index].templateIndex.flatMap { templateIndex in
        variations.first { $0.range.contains(templateIndex) }
      }
      if let last = groups.last, last.variation?.id == variation?.id,
        lines[last.range.upperBound..<index].allSatisfy({ $0.kind != .context })
          || last.variation != nil
      {
        groups[groups.count - 1].range = last.range.lowerBound..<(index + 1)
      } else {
        groups.append((index..<(index + 1), variation))
      }
    }

    var segments: [FileComparison.Segment] = []
    var cursor = 0
    for (position, group) in groups.enumerated() {
      let start = max(group.range.lowerBound - context, cursor)
      var end = min(group.range.upperBound + context, lines.count)
      if position + 1 < groups.count {
        // Split shared context between neighboring hunks.
        let next = groups[position + 1].range.lowerBound
        if end > next - context {
          end = max(group.range.upperBound, (group.range.upperBound + next) / 2)
        }
      }
      if start > cursor {
        segments.append(.unchanged(Array(lines[cursor..<start])))
      }
      segments.append(
        .hunk(FileComparison.Hunk(lines: Array(lines[start..<end]), variation: group.variation))
      )
      cursor = end
    }
    if cursor < lines.count, !groups.isEmpty {
      segments.append(.unchanged(Array(lines[cursor...])))
    }

    return FileComparison(
      segments: segments,
      additions: lines.filter { $0.kind == .added }.count,
      deletions: lines.filter { $0.kind == .removed }.count
    )
  }

  private func comparedLines(of key: String, against reference: String) -> [FileComparison.Line] {
    var result: [FileComparison.Line] = []
    var removed: [(text: String, index: Int)] = []
    var added: [(text: String, index: Int)] = []

    func append(_ kind: FileComparison.Kind, _ text: String, _ index: Int?) {
      result.append(FileComparison.Line(id: result.count, kind: kind, text: text, templateIndex: index))
    }

    func flush() {
      guard !removed.isEmpty || !added.isEmpty else {
        return
      }
      // The same text can sit in two audiences, so refine the change with a line diff.
      var oldIndex = 0
      var newIndex = 0
      var runRemoved: [(text: String, index: Int)] = []
      var runAdded: [(text: String, index: Int)] = []
      for row in LineDiff.rows(from: removed.map(\.text), to: added.map(\.text)) {
        switch row {
        case .same(let text):
          appendChange(runRemoved, runAdded)
          runRemoved = []
          runAdded = []
          append(.context, text, nil)
          oldIndex += 1
          newIndex += 1
        case .removed:
          runRemoved.append(removed[oldIndex])
          oldIndex += 1
        case .added:
          runAdded.append(added[newIndex])
          newIndex += 1
        }
      }
      appendChange(runRemoved, runAdded)
      removed = []
      added = []
    }

    func appendChange(
      _ removed: [(text: String, index: Int)],
      _ added: [(text: String, index: Int)]
    ) {
      let pairs = min(removed.count, added.count)
      let words = (0..<pairs).map { Self.wordChanges(from: removed[$0].text, to: added[$0].text) }
      for (offset, line) in removed.enumerated() {
        append(.removed, line.text, line.index)
        if offset < pairs, let rows = words[offset] {
          result[result.count - 1].words = rows.filter { !$0.isAdded }
        }
      }
      for (offset, line) in added.enumerated() {
        append(.added, line.text, line.index)
        if offset < pairs, let rows = words[offset] {
          result[result.count - 1].words = rows.filter { !$0.isRemoved }
        }
      }
    }

    for (index, line) in lines.enumerated() {
      let inReference = line.audience.includes(reference)
      let inFile = line.audience.includes(key)
      if inReference, inFile {
        flush()
        append(.context, line.text, nil)
      } else if inReference {
        removed.append((line.text, index))
      } else if inFile {
        added.append((line.text, index))
      }
    }
    flush()
    return result
  }

  /// Word changes between two lines, or nil when they have too little in common.
  private static func wordChanges(from old: String, to new: String) -> [LineDiff.Row]? {
    let rows = LineDiff.words(from: old, to: new)
    let shared = rows.reduce(0) { total, row in
      if case .same(let text) = row {
        return total + text.trimmingCharacters(in: .whitespaces).count
      }
      return total
    }
    let longest = max(old.count, new.count)
    return longest > 0 && Double(shared) / Double(longest) >= 0.4 ? rows : nil
  }
}

extension LineDiff.Row {
  var isAdded: Bool {
    if case .added = self {
      return true
    }
    return false
  }

  var isRemoved: Bool {
    if case .removed = self {
      return true
    }
    return false
  }
}
