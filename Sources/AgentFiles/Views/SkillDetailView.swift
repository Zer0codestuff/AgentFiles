import AppKit
import SwiftUI

struct SkillDetailView: View {
  let store: AgentFilesStore
  let skillName: String?

  @State private var previewLocationID: String?
  @State private var document = ""
  @State private var plan: SkillSyncPlan?
  @Namespace private var glassNamespace

  var body: some View {
    Group {
      if let skill = store.skill(named: skillName) {
        detail(skill)
      } else {
        ContentUnavailableView {
          Label("Select a Skill", systemImage: "sparkles")
        } description: {
          Text("Compare every copy of a skill and keep them identical across agents.")
        }
      }
    }
    .sheet(item: $plan) { plan in
      SkillSyncSheet(store: store, plan: plan)
    }
  }

  private func detail(_ skill: SkillRecord) -> some View {
    let source = sourceLocationID(for: skill)
    return ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header(skill)
        copiesCard(skill, source: source)
        reachCard(skill, source: source)
        documentCard(skill, source: source)
      }
      .padding(28)
      .frame(maxWidth: 860, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background(AmbientBackground(tint: store.skillLocation(id: source ?? "")?.tint ?? .accentColor))
    .task(id: "\(skill.name)|\(source ?? "")|\(skill.installation(in: source ?? "")?.digest ?? "")") {
      document = source.map { store.skillDocument(for: skill, in: $0) } ?? ""
    }
    .onChange(of: skill.name) { _, _ in
      previewLocationID = nil
    }
  }

  // MARK: Sections

  private func header(_ skill: SkillRecord) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(skill.name)
        .font(.largeTitle.weight(.semibold))
        .textSelection(.enabled)

      if !skill.summary.isEmpty {
        Text(skill.summary)
          .foregroundStyle(.secondary)
          .lineLimit(4)
      }

      HStack(spacing: 10) {
        SkillStateLabel(state: store.skillState(for: skill))
        Spacer()
        Toggle(
          "Keep in sync",
          isOn: Binding(
            get: { store.trackedSkill(named: skill.name) != nil },
            set: { store.setSkillTracking($0, for: skill.name) }
          )
        )
        .toggleStyle(.switch)
        .help(
          "Copy edits from one agent to every other copy automatically. Sync pauses if several copies change."
        )
      }
    }
  }

  private func copiesCard(_ skill: SkillRecord, source: String?) -> some View {
    GlassCard(title: "Copies", systemImage: "square.on.square") {
      GlassEffectContainer(spacing: 12) {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
          alignment: .leading,
          spacing: 12
        ) {
          ForEach(store.availableSkillLocations) { location in
            copyTile(skill: skill, location: location, isSelected: location.id == source)
          }
        }
      }
    }
  }

  private func copyTile(
    skill: SkillRecord,
    location: SkillLocation,
    isSelected: Bool
  ) -> some View {
    let installation = skill.installation(in: location.id)
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        HarnessGlyph(location: location, size: 30, isActive: installation != nil)
        Spacer()
        if installation?.isSymbolicLink == true {
          Image(systemName: "link")
            .foregroundStyle(.secondary)
            .help("Linked to \(PathFormatter.compact(installation?.resolvedURL.path ?? ""))")
        }
      }

      Text(location.title)
        .font(.headline)

      Text(copyStatus(skill: skill, installation: installation))
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      if installation != nil {
        Button("Use Everywhere") {
          plan = store.skillSyncPlan(for: skill.name, from: location.id)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(skill.variantCount < 2)
      } else if let source = sourceLocationID(for: skill) {
        Button("Install") {
          plan = store.skillSyncPlan(for: skill.name, from: source, to: [location.id])
        }
        .buttonStyle(.glassProminent)
        .controlSize(.small)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .glassEffect(
      isSelected ? .regular.tint(location.tint.opacity(0.28)).interactive() : .regular.interactive(),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .glassEffectID(location.id, in: glassNamespace)
    .onTapGesture {
      if installation != nil {
        withAnimation(.smooth) {
          previewLocationID = location.id
        }
      }
    }
    .contextMenu {
      if let installation {
        Button("Reveal in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([installation.url])
        }
      }
    }
  }

  private func reachCard(_ skill: SkillRecord, source: String?) -> some View {
    let reached = skill.reachableHarnesses(among: store.installedHarnesses)
    let missing = store.missingSkillTargets(for: skill)

    return GlassCard(title: "Agents", systemImage: "circle.hexagongrid") {
      FlowLayout(spacing: 6) {
        ForEach(reached) { tool in
          GlassTag(title: tool.title, systemImage: "checkmark", tint: tool.tint)
        }
        ForEach(missing) { tool in
          GlassTag(title: tool.title, systemImage: "circle.dashed")
            .opacity(0.7)
        }
      }

      if !missing.isEmpty, let source {
        HStack {
          Text(
            missing.count == 1
              ? "\(missing[0].title) cannot load this skill yet."
              : "\(missing.count) agents cannot load this skill yet."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Spacer()
          Button("Install for \(missing.count == 1 ? missing[0].title : "All")") {
            plan = store.skillSyncPlan(
              for: skill.name,
              from: source,
              to: missing.map(\.rawValue)
            )
          }
          .buttonStyle(.glassProminent)
        }
      }
    }
  }

  private func documentCard(_ skill: SkillRecord, source: String?) -> some View {
    let location = source.flatMap { store.skillLocation(id: $0) }
    let installation = source.flatMap { skill.installation(in: $0) }

    return GlassCard(
      title: "SKILL.md · \(location?.title ?? "")",
      systemImage: "doc.text"
    ) {
      ScrollView {
        Text(document.isEmpty ? " " : document)
          .font(.system(size: 12, design: .monospaced))
          .lineSpacing(2)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(14)
      }
      .frame(minHeight: 220, maxHeight: 440)
      .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      if let installation {
        HStack {
          Text(PathFormatter.compact(installation.url.path))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Open", systemImage: "square.and.pencil") {
            NSWorkspace.shared.open(installation.resolvedURL.appendingPathComponent("SKILL.md"))
          }
          .buttonStyle(.glass)
          Button("Reveal", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([installation.url])
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.glass)
        }
      }
    }
  }

  // MARK: Helpers

  /// The copy shown in the preview and used as the source for installs.
  private func sourceLocationID(for skill: SkillRecord) -> String? {
    if let previewLocationID, skill.installation(in: previewLocationID) != nil {
      return previewLocationID
    }
    return skill.installations.values
      .max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }?
      .locationID
  }

  private func copyStatus(skill: SkillRecord, installation: SkillInstallation?) -> String {
    guard let installation else {
      return "No copy"
    }
    let fileCount = installation.fileDigests.count
    let files = fileCount == 1 ? "1 file" : "\(fileCount) files"
    guard skill.variantCount > 1 else {
      return files
    }
    return "Version \(variantLetter(for: installation.digest, in: skill)) · \(files)"
  }

  private func variantLetter(for digest: String, in skill: SkillRecord) -> String {
    var ordered: [String] = []
    for location in store.skillLocations {
      if let digest = skill.installation(in: location.id)?.digest, !ordered.contains(digest) {
        ordered.append(digest)
      }
    }
    let index = ordered.firstIndex(of: digest) ?? 0
    return String(UnicodeScalar(UInt8(65 + min(index, 25))))
  }
}
