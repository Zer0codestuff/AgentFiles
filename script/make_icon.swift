// Draws the layers of the app icon, three stacked sheets, as an Icon Composer file.
// The build script compiles it with actool so macOS applies its own shape and glass.
// Usage: swift script/make_icon.swift Icon/AppIcon.icon
import AppKit

let canvas: CGFloat = 1024

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

struct Sheet {
  var name: String
  var center: CGPoint
  var angle: CGFloat
  var fill: [CGColor]
  var lines: [(width: CGFloat, color: CGColor)]
}

let muted = color(1, 1, 1, 0.55)
let ink = color(0.30, 0.32, 0.38, 0.55)

// Back to front: Grok violet, Codex blue, then the shared text with a Claude heading.
let sheets = [
  Sheet(
    name: "back", center: CGPoint(x: 450, y: 540), angle: 14,
    fill: [color(0.62, 0.52, 0.98), color(0.42, 0.33, 0.86)],
    lines: [(160, muted), (245, muted), (200, muted)]
  ),
  Sheet(
    name: "middle", center: CGPoint(x: 496, y: 518), angle: 4,
    fill: [color(0.42, 0.62, 1.0), color(0.22, 0.42, 0.90)],
    lines: [(160, muted), (245, muted), (200, muted)]
  ),
  Sheet(
    name: "front", center: CGPoint(x: 556, y: 486), angle: -7,
    fill: [color(1, 0.99, 0.97), color(0.92, 0.91, 0.90)],
    lines: [
      (180, color(0.85, 0.47, 0.34)),
      (285, ink), (245, ink), (285, ink), (215, ink), (265, ink),
    ]
  ),
]

func draw(_ sheet: Sheet, in context: CGContext) {
  let size = CGSize(width: 430, height: 540)
  let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
  let shape = CGPath(roundedRect: rect, cornerWidth: 52, cornerHeight: 52, transform: nil)

  context.translateBy(x: sheet.center.x, y: sheet.center.y)
  context.rotate(by: sheet.angle * .pi / 180)

  context.saveGState()
  context.addPath(shape)
  context.clip()
  let gradient = CGGradient(colorsSpace: nil, colors: sheet.fill as CFArray, locations: [0, 1])!
  context.drawLinearGradient(
    gradient,
    start: CGPoint(x: rect.minX, y: rect.maxY),
    end: CGPoint(x: rect.maxX, y: rect.minY),
    options: []
  )
  context.restoreGState()

  var y = rect.maxY - 100
  for line in sheet.lines {
    let bar = CGRect(x: rect.minX + 62, y: y - 14, width: line.width, height: 28)
    context.addPath(CGPath(roundedRect: bar, cornerWidth: 14, cornerHeight: 14, transform: nil))
    context.setFillColor(line.color)
    context.fillPath()
    y -= 67
  }
}

func png(_ sheet: Sheet) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
  )!
  let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
  draw(sheet, in: context)
  return rep.representation(using: .png, properties: [:])!
}

let iconURL = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = iconURL.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
for sheet in sheets {
  try png(sheet).write(to: assets.appendingPathComponent("\(sheet.name).png"))
}

let layers = sheets.reversed().map { sheet in
  "        { \"image-name\" : \"\(sheet.name).png\", \"name\" : \"\(sheet.name)\", \"glass\" : true }"
}
let json = """
  {
    "fill" : {
      "linear-gradient" : [
        "srgb:0.20000,0.22000,0.29000,1.00000",
        "srgb:0.07000,0.08000,0.11000,1.00000"
      ]
    },
    "groups" : [
      {
        "layers" : [
  \(layers.joined(separator: ",\n"))
        ],
        "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
        "specular" : true,
        "translucency" : { "enabled" : false, "value" : 0.3 }
      }
    ],
    "supported-platforms" : { "squares" : [ "macOS" ] }
  }

  """
try json.write(to: iconURL.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
