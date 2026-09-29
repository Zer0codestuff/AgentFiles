import AppKit
import SwiftUI

extension AgentTool {
  var tint: Color {
    switch self {
    case .claudeCode:
      Color(red: 0.85, green: 0.47, blue: 0.34)
    case .codex:
      Color(red: 0.33, green: 0.52, blue: 0.96)
    case .factory:
      Color(red: 0.95, green: 0.62, blue: 0.22)
    case .cursor:
      Color(red: 0.25, green: 0.70, blue: 0.68)
    case .grok:
      Color(red: 0.56, green: 0.46, blue: 0.95)
    case .warp:
      Color(red: 0.90, green: 0.36, blue: 0.62)
    case .openCode, .custom:
      Color.gray
    }
  }
}

extension SkillLocation {
  var tint: Color {
    tool?.tint ?? Color(red: 0.45, green: 0.55, blue: 0.68)
  }
}

/// An agent's badge: its real app icon when the app is installed, otherwise a tinted
/// Liquid Glass glyph.
struct HarnessGlyph: View {
  let systemImage: String
  let tint: Color
  var tool: AgentTool?
  var size: CGFloat = 28
  var isActive = true

  init(tool: AgentTool, size: CGFloat = 28, isActive: Bool = true) {
    self.init(systemImage: tool.systemImage, tint: tool.tint, size: size, isActive: isActive)
    self.tool = tool
  }

  init(location: SkillLocation, size: CGFloat = 28, isActive: Bool = true) {
    self.init(
      systemImage: location.systemImage,
      tint: location.tint,
      size: size,
      isActive: isActive
    )
    tool = location.tool
  }

  init(systemImage: String, tint: Color, size: CGFloat = 28, isActive: Bool = true) {
    self.systemImage = systemImage
    self.tint = tint
    self.size = size
    self.isActive = isActive
  }

  var body: some View {
    if let tool, let icon = AppIconProvider.icon(for: tool) {
      Image(nsImage: icon)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .saturation(isActive ? 1 : 0)
        .opacity(isActive ? 1 : 0.45)
    } else if tool == .grok {
      GrokMark(size: size)
        .opacity(isActive ? 1 : 0.45)
    } else {
      Image(systemName: systemImage)
        .font(.system(size: size * 0.44, weight: .semibold))
        .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
        .frame(width: size, height: size)
        .glassEffect(
          isActive ? .regular.tint(tint.opacity(0.8)) : .regular,
          in: Circle()
        )
    }
  }
}

/// Grok Build ships without a desktop app, so its badge is drawn: a ring crossed by a
/// diagonal stroke on a dark app-icon tile.
struct GrokMark: View {
  let size: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
      .fill(Color(white: 0.08))
      .overlay {
        ZStack {
          Circle()
            .stroke(.white, lineWidth: size * 0.075)
            .frame(width: size * 0.48, height: size * 0.48)
          Capsule()
            .fill(.white)
            .frame(width: size * 0.075, height: size * 0.66)
            .rotationEffect(.degrees(40))
        }
      }
      .padding(size * 0.08)
      .frame(width: size, height: size)
  }
}

/// Shows the agents that read one file, overlapping when there are several.
struct TargetIcon: View {
  let target: WorkspaceTarget
  var size: CGFloat = 22

  var body: some View {
    if target.tools.count == 1 {
      HarnessGlyph(tool: target.tools[0], size: size)
    } else {
      let iconSize = size * 0.9
      HStack(spacing: -iconSize * 0.45) {
        ForEach(target.tools) { tool in
          HarnessGlyph(tool: tool, size: iconSize)
        }
      }
    }
  }
}

/// Looks up the icons of installed agent apps through Launch Services.
@MainActor
enum AppIconProvider {
  private static var cache: [AgentTool: NSImage?] = [:]

  static func icon(for tool: AgentTool) -> NSImage? {
    if let cached = cache[tool] {
      return cached
    }
    let icon = bundleIdentifiers(for: tool).lazy
      .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
      .first
      .map { NSWorkspace.shared.icon(forFile: $0.path) }
    cache[tool] = icon
    return icon
  }

  private static func bundleIdentifiers(for tool: AgentTool) -> [String] {
    switch tool {
    case .claudeCode:
      ["com.anthropic.claudefordesktop"]
    case .codex:
      ["com.openai.codex"]
    case .factory:
      ["com.electron.factory", "ai.factory.desktop"]
    case .cursor:
      ["com.todesktop.230313mzl4w4u92"]
    case .warp:
      ["dev.warp.Warp-Stable", "dev.warp.Warp"]
    case .openCode:
      ["ai.opencode.desktop"]
    case .grok, .custom:
      []
    }
  }
}

/// A compact capsule used for statuses and small facts.
struct GlassTag: View {
  let title: String
  var systemImage: String?
  var tint: Color?

  var body: some View {
    HStack(spacing: 5) {
      if let systemImage {
        Image(systemName: systemImage)
          .imageScale(.small)
      }
      Text(title)
        .lineLimit(1)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .glassEffect(.regular, in: Capsule())
  }
}

/// A soft wash of color behind detail panes so the glass has something to refract.
struct AmbientBackground: View {
  let tint: Color

  var body: some View {
    ZStack {
      RadialGradient(
        colors: [tint.opacity(0.22), .clear],
        center: .topLeading,
        startRadius: 0,
        endRadius: 560
      )
      RadialGradient(
        colors: [tint.opacity(0.10), .clear],
        center: .bottomTrailing,
        startRadius: 0,
        endRadius: 480
      )
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}

/// A rounded glass card for grouping related detail content.
struct GlassCard<Content: View>: View {
  var title: String?
  var systemImage: String?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let title {
        Label {
          Text(title)
        } icon: {
          if let systemImage {
            Image(systemName: systemImage)
          }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      }
      content
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

enum PathFormatter {
  static func compact(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == home {
      return "~"
    }
    if path.hasPrefix(home + "/") {
      return "~" + path.dropFirst(home.count)
    }
    return path
  }
}

/// Wraps its subviews onto new lines when they run out of horizontal space.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    let width = rows.map(\.width).max() ?? 0
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var y = bounds.minY
    for row in arrange(subviews: subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if proposedWidth > width, !current.indices.isEmpty {
        rows.append(current)
        current = Row()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty {
      rows.append(current)
    }
    return rows
  }
}

extension WorkspaceTarget {
  var tint: Color {
    tools.count == 1 ? tools[0].tint : Color(red: 0.45, green: 0.55, blue: 0.68)
  }

  var systemImage: String {
    tools.count == 1 ? tools[0].systemImage : "doc.text"
  }

  /// The agents that read this file, for display under its title.
  var readersDescription: String {
    tools.map(\.title).joined(separator: ", ")
  }
}
