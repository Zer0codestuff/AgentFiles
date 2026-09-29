import Foundation

/// A line-based diff built on the longest common subsequence.
enum LineDiff {
  /// Replaces `range` in the old lines with `replacement`.
  struct Hunk: Equatable, Sendable {
    var range: Range<Int>
    var replacement: [String]
  }

  enum Row: Equatable, Sendable {
    case same(String)
    case removed(String)
    case added(String)
  }

  static func lines(in content: String) -> [String] {
    content.components(separatedBy: "\n")
  }

  static func hunks(from old: [String], to new: [String]) -> [Hunk] {
    var hunks: [Hunk] = []
    var oldIndex = 0
    var start: Int?
    var replacement: [String] = []

    func finish() {
      if let start {
        hunks.append(Hunk(range: start..<oldIndex, replacement: replacement))
      }
      start = nil
      replacement = []
    }

    for row in operations(from: old, to: new) {
      switch row {
      case .same:
        finish()
        oldIndex += 1
      case .removed:
        if start == nil {
          start = oldIndex
        }
        oldIndex += 1
      case .added(let line):
        if start == nil {
          start = oldIndex
        }
        replacement.append(line)
      }
    }
    finish()
    return hunks
  }

  static func rows(from old: String, to new: String) -> [Row] {
    operations(from: lines(in: old), to: lines(in: new))
  }

  private static func operations(from old: [String], to new: [String]) -> [Row] {
    var prefix = 0
    while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
      prefix += 1
    }
    var suffix = 0
    while suffix < old.count - prefix, suffix < new.count - prefix,
      old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
    {
      suffix += 1
    }

    let oldMiddle = Array(old[prefix..<(old.count - suffix)])
    let newMiddle = Array(new[prefix..<(new.count - suffix)])
    var rows = old[..<prefix].map(Row.same)

    if oldMiddle.count * newMiddle.count > 4_000_000 {
      rows += oldMiddle.map(Row.removed) + newMiddle.map(Row.added)
    } else {
      rows += middleOperations(from: oldMiddle, to: newMiddle)
    }

    rows += old[(old.count - suffix)...].map(Row.same)
    return rows
  }

  private static func middleOperations(from old: [String], to new: [String]) -> [Row] {
    let oldCount = old.count
    let newCount = new.count
    var lcs = Array(repeating: Array(repeating: 0, count: newCount + 1), count: oldCount + 1)

    if oldCount > 0, newCount > 0 {
      for i in stride(from: oldCount - 1, through: 0, by: -1) {
        for j in stride(from: newCount - 1, through: 0, by: -1) {
          lcs[i][j] =
            old[i] == new[j]
            ? lcs[i + 1][j + 1] + 1
            : max(lcs[i + 1][j], lcs[i][j + 1])
        }
      }
    }

    var rows: [Row] = []
    var i = 0
    var j = 0
    while i < oldCount || j < newCount {
      if i < oldCount, j < newCount, old[i] == new[j] {
        rows.append(.same(old[i]))
        i += 1
        j += 1
      } else if i < oldCount, j == newCount || lcs[i + 1][j] >= lcs[i][j + 1] {
        rows.append(.removed(old[i]))
        i += 1
      } else {
        rows.append(.added(new[j]))
        j += 1
      }
    }
    return rows
  }
}
