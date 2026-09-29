import CryptoKit
import Foundation

enum SkillLibraryError: LocalizedError, Equatable {
  case sourceMissing(String)
  case changedSincePreview(String)

  var errorDescription: String? {
    switch self {
    case .sourceMissing(let name):
      "The source copy of \(name) is no longer available."
    case .changedSincePreview(let path):
      "\(path) changed after the sync was prepared. Review the skill again before synchronizing."
    }
  }
}

/// Reads, compares, and mirrors skill folders. Every overwrite is preceded by a
/// full backup of the target folder.
struct SkillLibraryService: Sendable {
  static let ignoredNames: Set<String> = [
    ".DS_Store", ".git", "node_modules", "__pycache__", ".venv",
  ]

  let backupRootURL: URL
  let retainedBackupsPerSkill: Int

  init(
    backupRootURL: URL = AppDirectories.skillBackups,
    retainedBackupsPerSkill: Int = 20
  ) {
    self.backupRootURL = backupRootURL
    self.retainedBackupsPerSkill = retainedBackupsPerSkill
  }

  // MARK: Scanning

  func scan(locations: [SkillLocation]) -> [SkillRecord] {
    var records: [String: SkillRecord] = [:]

    for location in locations {
      guard
        let entries = try? FileManager.default.contentsOfDirectory(
          at: location.directory,
          includingPropertiesForKeys: [.isSymbolicLinkKey],
          options: [.skipsHiddenFiles]
        )
      else {
        continue
      }

      for entry in entries {
        guard let installation = inspect(skillAt: entry, locationID: location.id) else {
          continue
        }
        let name = entry.lastPathComponent
        var record =
          records[name] ?? SkillRecord(name: name, summary: "", installations: [:])
        if record.summary.isEmpty {
          record.summary = Self.summary(in: installation.resolvedURL)
        }
        record.installations[location.id] = installation
        records[name] = record
      }
    }

    return records.values.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  func inspect(skillAt url: URL, locationID: String) -> SkillInstallation? {
    let resolvedURL = url.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue,
      FileManager.default.fileExists(
        atPath: resolvedURL.appendingPathComponent("SKILL.md").path
      )
    else {
      return nil
    }

    let isSymbolicLink =
      (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
    let (fileDigests, modificationDate) = fileDigests(in: resolvedURL)

    return SkillInstallation(
      locationID: locationID,
      url: url,
      resolvedURL: resolvedURL,
      isSymbolicLink: isSymbolicLink,
      digest: Self.folderDigest(fileDigests),
      fileDigests: fileDigests,
      modificationDate: modificationDate
    )
  }

  func skillDocument(in installation: SkillInstallation) -> String {
    let url = installation.resolvedURL.appendingPathComponent("SKILL.md")
    guard let data = try? Data(contentsOf: url) else {
      return ""
    }
    return String(decoding: data, as: UTF8.self)
  }

  // MARK: Planning

  func makePlan(
    for skill: SkillRecord,
    from sourceLocationID: String,
    to targetLocations: [SkillLocation]
  ) throws -> SkillSyncPlan {
    guard let source = skill.installation(in: sourceLocationID) else {
      throw SkillLibraryError.sourceMissing(skill.name)
    }

    var seenDirectories: Set<String> = [source.resolvedURL.path]
    var targets: [SkillSyncTarget] = []

    for location in targetLocations where location.id != sourceLocationID {
      if let installation = skill.installation(in: location.id) {
        // Symbolic links can make two locations share one folder.
        guard seenDirectories.insert(installation.resolvedURL.path).inserted else {
          continue
        }
        targets.append(
          SkillSyncTarget(
            locationID: location.id,
            directory: installation.resolvedURL,
            existed: true,
            expectedDigest: installation.digest,
            changes: Self.changes(from: installation.fileDigests, to: source.fileDigests)
          )
        )
      } else {
        let directory = location.directory.appendingPathComponent(skill.name, isDirectory: true)
        guard seenDirectories.insert(directory.path).inserted else {
          continue
        }
        targets.append(
          SkillSyncTarget(
            locationID: location.id,
            directory: directory,
            existed: false,
            expectedDigest: nil,
            changes: Self.changes(from: [:], to: source.fileDigests)
          )
        )
      }
    }

    return SkillSyncPlan(
      skillName: skill.name,
      sourceLocationID: sourceLocationID,
      sourceDirectory: source.resolvedURL,
      sourceDigest: source.digest,
      targets: targets
    )
  }

  // MARK: Applying

  func apply(_ plan: SkillSyncPlan) throws {
    guard
      let source = inspect(skillAt: plan.sourceDirectory, locationID: plan.sourceLocationID),
      source.digest == plan.sourceDigest
    else {
      throw SkillLibraryError.changedSincePreview(plan.sourceDirectory.path)
    }

    let targets = plan.changedTargets
    var liveTargets: [(SkillSyncTarget, [String: String])] = []

    // Verify every target first so a concurrent edit stops the whole sync.
    for target in targets {
      if target.existed {
        guard
          let current = inspect(skillAt: target.directory, locationID: target.locationID),
          current.digest == target.expectedDigest
        else {
          throw SkillLibraryError.changedSincePreview(target.directory.path)
        }
        liveTargets.append((target, current.fileDigests))
      } else {
        guard !FileManager.default.fileExists(atPath: target.directory.path) else {
          throw SkillLibraryError.changedSincePreview(target.directory.path)
        }
        liveTargets.append((target, [:]))
      }
    }

    for (target, _) in liveTargets where target.existed {
      try backup(
        directory: target.directory,
        skillName: plan.skillName,
        locationID: target.locationID
      )
    }

    for (target, currentDigests) in liveTargets {
      try mirror(
        from: source.resolvedURL,
        sourceDigests: source.fileDigests,
        to: target.directory,
        targetDigests: currentDigests
      )
    }
  }

  @discardableResult
  func backup(directory: URL, skillName: String, locationID: String) throws -> URL {
    let container =
      backupRootURL
      .appendingPathComponent(skillName, isDirectory: true)
      .appendingPathComponent(locationID, isDirectory: true)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

    let timestamp = String(format: "%.6f", Date().timeIntervalSince1970)
      .replacingOccurrences(of: ".", with: "-")
    let destination = container.appendingPathComponent(timestamp, isDirectory: true)
    try FileManager.default.copyItem(at: directory, to: destination)

    let existing = try FileManager.default.contentsOfDirectory(
      at: container,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    for overflow in existing.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
      .dropLast(retainedBackupsPerSkill)
    {
      try FileManager.default.removeItem(at: overflow)
    }
    return destination
  }

  private func mirror(
    from sourceDirectory: URL,
    sourceDigests: [String: String],
    to targetDirectory: URL,
    targetDigests: [String: String]
  ) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

    for (path, digest) in sourceDigests where targetDigests[path] != digest {
      let sourceURL = sourceDirectory.appendingPathComponent(path)
      let targetURL = targetDirectory.appendingPathComponent(path)
      try fileManager.createDirectory(
        at: targetURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data(contentsOf: sourceURL).write(to: targetURL, options: .atomic)
      if let permissions = try? fileManager.attributesOfItem(atPath: sourceURL.path)[
        .posixPermissions]
      {
        try? fileManager.setAttributes(
          [.posixPermissions: permissions],
          ofItemAtPath: targetURL.path
        )
      }
    }

    for path in targetDigests.keys where sourceDigests[path] == nil {
      try fileManager.removeItem(at: targetDirectory.appendingPathComponent(path))
    }
  }

  // MARK: Helpers

  private func fileDigests(in directory: URL) -> ([String: String], Date?) {
    var digests: [String: String] = [:]
    var latest: Date?
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
      return ([:], nil)
    }

    while let relativePath = enumerator.nextObject() as? String {
      let name = (relativePath as NSString).lastPathComponent
      let type = enumerator.fileAttributes?[.type] as? FileAttributeType
      if Self.ignoredNames.contains(name) {
        if type == .typeDirectory {
          enumerator.skipDescendants()
        }
        continue
      }
      guard type != .typeDirectory else {
        continue
      }

      let url = directory.appendingPathComponent(relativePath)
      guard let data = try? Data(contentsOf: url) else {
        continue
      }
      digests[relativePath] = SHA256.hash(data: data).map { String(format: "%02x", $0) }
        .joined()
      if let date = enumerator.fileAttributes?[.modificationDate] as? Date,
        date > (latest ?? .distantPast)
      {
        latest = date
      }
    }

    return (digests, latest)
  }

  static func folderDigest(_ fileDigests: [String: String]) -> String {
    let manifest = fileDigests.keys.sorted()
      .map { "\($0)\u{0}\(fileDigests[$0] ?? "")" }
      .joined(separator: "\n")
    return FileAccessService.digest(for: manifest)
  }

  static func changes(
    from current: [String: String],
    to incoming: [String: String]
  ) -> [SkillFileChange] {
    var changes: [SkillFileChange] = []
    for (path, digest) in incoming {
      if let existing = current[path] {
        if existing != digest {
          changes.append(SkillFileChange(path: path, kind: .modified))
        }
      } else {
        changes.append(SkillFileChange(path: path, kind: .added))
      }
    }
    for path in current.keys where incoming[path] == nil {
      changes.append(SkillFileChange(path: path, kind: .removed))
    }
    return changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }

  /// Reads the `description` field from the SKILL.md front matter.
  static func summary(in directory: URL) -> String {
    guard
      let data = try? Data(contentsOf: directory.appendingPathComponent("SKILL.md")),
      let content = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return frontMatterValue("description", in: content) ?? ""
  }

  static func frontMatterValue(_ key: String, in content: String) -> String? {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\r"))) }
    guard lines.first == "---" else {
      return nil
    }

    let body = lines.dropFirst().prefix { $0 != "---" }
    let rawLines = content.split(separator: "\n", omittingEmptySubsequences: false)
      .dropFirst().prefix(body.count)
      .map(String.init)

    guard let index = rawLines.firstIndex(where: { $0.hasPrefix("\(key):") }) else {
      return nil
    }

    var value = String(rawLines[index].dropFirst(key.count + 1))
      .trimmingCharacters(in: .whitespaces)
    if value.isEmpty || value == ">" || value == "|" || value == ">-" || value == "|-" {
      value = rawLines[(index + 1)...]
        .prefix { $0.hasPrefix(" ") || $0.hasPrefix("\t") }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .joined(separator: " ")
    }
    if value.count >= 2,
      let first = value.first, let last = value.last,
      first == last, first == "\"" || first == "'"
    {
      value = String(value.dropFirst().dropLast())
    }
    return value.isEmpty ? nil : value
  }
}
