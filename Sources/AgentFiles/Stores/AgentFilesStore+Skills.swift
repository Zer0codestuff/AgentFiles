import Foundation

extension AgentFilesStore {
  var availableSkillLocations: [SkillLocation] {
    skillLocations.filter(\.isAvailable)
  }

  var skillsNeedingAttention: [SkillRecord] {
    skills.filter { skill in
      switch skillState(for: skill) {
      case .differs, .conflict:
        true
      case .synchronized, .missing:
        false
      }
    }
  }

  func skill(named name: String?) -> SkillRecord? {
    guard let name else {
      return nil
    }
    return skills.first { $0.name == name }
  }

  func skillLocation(id: String) -> SkillLocation? {
    skillLocations.first { $0.id == id }
  }

  func trackedSkill(named name: String) -> TrackedSkill? {
    configuration.trackedSkills.first { $0.name == name }
  }

  func skillState(for skill: SkillRecord) -> SkillSyncState {
    if skillConflicts.contains(skill.name) {
      return .conflict
    }
    if skill.variantCount > 1 {
      return .differs(skill.variantCount)
    }
    let harnesses = installedHarnesses
    let missing = harnesses.count - skill.reachableHarnesses(among: harnesses).count
    return missing > 0 ? .missing(missing) : .synchronized
  }

  /// Each installed agent that cannot load the skill yet, paired with its own skill folder.
  func missingSkillTargets(for skill: SkillRecord) -> [AgentTool] {
    let harnesses = installedHarnesses
    let reached = Set(skill.reachableHarnesses(among: harnesses))
    return harnesses.filter { !reached.contains($0) }
  }

  // MARK: Scanning

  func startSkillLibrary() {
    skillLocations = SkillLocation.defaultLocations(home: homeDirectory)
    restartSkillWatcher()
    scheduleSkillScan(delay: .zero)
  }

  func restartSkillWatcher() {
    let directories = skillLocations.map(\.directory).filter {
      FileManager.default.fileExists(atPath: $0.path)
    }
    skillWatcher = RecursiveDirectoryWatcher(directoryURLs: directories) { [weak self] in
      Task { @MainActor in
        self?.scheduleSkillScan()
      }
    }
  }

  func scheduleSkillScan(delay: Duration = .milliseconds(350)) {
    skillScanTask?.cancel()
    skillScanTask = Task { [weak self] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      guard !Task.isCancelled else {
        return
      }
      await self?.rescanSkills()
    }
  }

  func rescanSkills() async {
    guard !isApplyingSkillSync else {
      return
    }

    isScanningSkills = true
    let locations = skillLocations
    let library = skillLibrary
    let records = await Task.detached(priority: .utility) {
      library.scan(locations: locations)
    }.value
    skills = records
    isScanningSkills = false

    if skill(named: selectedSkillName) == nil {
      selectedSkillName = records.first?.name
    }
    reconcileTrackedSkills()
  }

  func skillDocument(for skill: SkillRecord, in locationID: String) -> String {
    guard let installation = skill.installation(in: locationID) else {
      return ""
    }
    return skillLibrary.skillDocument(in: installation)
  }

  // MARK: Synchronizing

  /// Plans a sync from one copy. Without explicit targets, every other existing copy is updated.
  func skillSyncPlan(
    for name: String,
    from sourceLocationID: String,
    to targetLocationIDs: [String]? = nil
  ) -> SkillSyncPlan? {
    guard let skill = skill(named: name) else {
      return nil
    }

    let targets = skillLocations.filter { location in
      if let targetLocationIDs {
        return targetLocationIDs.contains(location.id)
      }
      return skill.installation(in: location.id) != nil
    }

    do {
      return try skillLibrary.makePlan(for: skill, from: sourceLocationID, to: targets)
    } catch {
      notice = AppNotice(title: "Skill sync unavailable", message: error.localizedDescription)
      return nil
    }
  }

  @discardableResult
  func applySkillPlan(_ plan: SkillSyncPlan) async -> Bool {
    isApplyingSkillSync = true
    let library = skillLibrary
    let createsLocation = plan.changedTargets.contains { !$0.existed }

    do {
      try await Task.detached(priority: .userInitiated) {
        try library.apply(plan)
      }.value
    } catch {
      isApplyingSkillSync = false
      notice = AppNotice(title: "Skill sync stopped", message: error.localizedDescription)
      await rescanSkills()
      return false
    }

    skillConflicts.remove(plan.skillName)
    if trackedSkill(named: plan.skillName) != nil {
      let involved = Set(plan.targets.map(\.locationID) + [plan.sourceLocationID])
      updateTrackedSkills { tracked in
        guard let index = tracked.firstIndex(where: { $0.name == plan.skillName }) else {
          return
        }
        let locationIDs = Set(tracked[index].locationIDs).union(involved)
        tracked[index].locationIDs = orderedLocationIDs(locationIDs)
        tracked[index].baselineDigest = plan.sourceDigest
      }
    }

    isApplyingSkillSync = false
    if createsLocation {
      restartSkillWatcher()
    }
    await rescanSkills()
    return true
  }

  func setSkillTracking(_ enabled: Bool, for name: String) {
    guard enabled else {
      updateTrackedSkills { $0.removeAll { $0.name == name } }
      skillConflicts.remove(name)
      return
    }

    guard let skill = skill(named: name),
      skill.variantCount == 1,
      let digest = skill.installations.values.first?.digest
    else {
      notice = AppNotice(
        title: "Choose a version first",
        message:
          "The copies of \(name) differ. Use one version everywhere before keeping the skill in sync."
      )
      return
    }

    let tracked = TrackedSkill(
      name: name,
      locationIDs: orderedLocationIDs(Set(skill.installations.keys)),
      baselineDigest: digest
    )
    updateTrackedSkills { skills in
      skills.removeAll { $0.name == name }
      skills.append(tracked)
    }
  }

  /// Propagates a tracked skill when exactly one version changed since the last sync.
  /// Several independent edits pause the skill until a version is chosen explicitly.
  func reconcileTrackedSkills() {
    guard !isApplyingSkillSync else {
      return
    }

    for tracked in configuration.trackedSkills {
      guard let skill = skill(named: tracked.name) else {
        continue
      }

      let present = tracked.locationIDs.compactMap { skill.installation(in: $0) }
      let changed = present.filter { $0.digest != tracked.baselineDigest }
      guard let source = changed.first else {
        continue
      }

      guard Set(changed.map(\.digest)).count == 1 else {
        if skillConflicts.insert(tracked.name).inserted {
          notice = AppNotice(
            title: "Skill sync paused",
            message: "Several copies of \(tracked.name) changed. Choose the version to keep."
          )
        }
        continue
      }
      guard !skillConflicts.contains(tracked.name) else {
        continue
      }

      let stale = present.filter { $0.digest != source.digest }.map(\.locationID)
      if stale.isEmpty {
        updateTrackedSkills { skills in
          if let index = skills.firstIndex(where: { $0.name == tracked.name }) {
            skills[index].baselineDigest = source.digest
          }
        }
        continue
      }

      guard let plan = skillSyncPlan(for: tracked.name, from: source.locationID, to: stale)
      else {
        continue
      }
      Task {
        await applySkillPlan(plan)
      }
      // The rescan after this sync reconciles the remaining skills.
      return
    }
  }

  private func orderedLocationIDs(_ ids: Set<String>) -> [String] {
    skillLocations.map(\.id).filter(ids.contains)
  }
}
