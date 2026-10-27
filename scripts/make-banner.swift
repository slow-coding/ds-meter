import AppKit

/// 生成 README / GitHub social preview 用的产品 banner（1280×640，2x）。
/// 只读 docs/panel.png（假数据），不碰真实凭据。
///   swift scripts/make-banner.swift
let width: CGFloat = 1280
let height: CGFloat = 640
let scale: CGFloat = 2

let panelURL = URL(fileURLWithPath: "docs/panel.png")
guard let panel = NSImage(contentsOf: panelURL) else {
    FileHandle.standardError.write("找不到 docs/panel.png\n".data(using: .utf8)!)
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * scale),
    pixelsHigh: Int(height * scale),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// 底：暖近黑，右边一团很淡的光
NSGradient(colors: [
    NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1),
    NSColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1),
])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

let glow = NSGradient(colors: [
    NSColor(red: 0.98, green: 0.57, blue: 0.18, alpha: 0.16),
    NSColor(red: 0.98, green: 0.57, blue: 0.18, alpha: 0),
])!
glow.draw(
    fromCenter: NSPoint(x: 980, y: 330),
    radius: 0,
    toCenter: NSPoint(x: 980, y: 330),
    radius: 420,
    options: []
)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func text(_ string: String, font: NSFont, color: NSColor, x: CGFloat, top: CGFloat) -> NSSize {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (string as NSString).size(withAttributes: attributes)
    (string as NSString).draw(
        at: NSPoint(x: x, y: height - top - size.height),
        withAttributes: attributes
    )
    return size
}

// 左边：名字 + 一句话 + 三个标签
_ = text("DS Meter", font: rounded(64, .bold), color: .white, x: 80, top: 186)
_ = text(
    "DeepSeek spend, at a glance.",
    font: rounded(26, .regular),
    color: NSColor(white: 1, alpha: 0.62),
    x: 84,
    top: 268
)

struct Chip {
    var text: String
    var color: NSColor
}

let chips = [
    Chip(text: "menu bar", color: NSColor(red: 0.46, green: 0.80, blue: 0.50, alpha: 1)),
    Chip(text: "peak / off-peak", color: NSColor(red: 0.98, green: 0.60, blue: 0.22, alpha: 1)),
    Chip(text: "100% local", color: NSColor(red: 0.40, green: 0.66, blue: 1.00, alpha: 1)),
]
let chipFont = rounded(15, .medium)
var chipX: CGFloat = 84
for chip in chips {
    let attributes: [NSAttributedString.Key: Any] = [.font: chipFont, .foregroundColor: chip.color]
    let textSize = (chip.text as NSString).size(withAttributes: attributes)
    let box = NSRect(x: chipX, y: height - 352, width: textSize.width + 28, height: 34)
    let path = NSBezierPath(roundedRect: box, xRadius: 17, yRadius: 17)
    chip.color.withAlphaComponent(0.12).setFill()
    path.fill()
    chip.color.withAlphaComponent(0.35).setStroke()
    path.lineWidth = 1
    path.stroke()
    (chip.text as NSString).draw(
        at: NSPoint(x: box.minX + 14, y: box.minY + 9),
        withAttributes: attributes
    )
    chipX = box.maxX + 10
}

_ = text(
    "No server. No telemetry. Nothing leaves your Mac.",
    font: rounded(16, .regular),
    color: NSColor(white: 1, alpha: 0.52),
    x: 84,
    top: 404
)
_ = text(
    "macOS 13+  ·  MIT  ·  open source",
    font: rounded(15, .regular),
    color: NSColor(white: 1, alpha: 0.32),
    x: 84,
    top: 440
)

// 右边：面板（假数据那张）
let panelHeight: CGFloat = 540
let panelWidth = panelHeight * (panel.size.width / panel.size.height)
let panelRect = NSRect(
    x: width - panelWidth - 80,
    y: (height - panelHeight) / 2,
    width: panelWidth,
    height: panelHeight
)

let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
panel.draw(in: panelRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

// 面板右下角加一道很淡的高光边，别让它看起来是贴上去的
let border = NSBezierPath(
    roundedRect: panelRect.insetBy(dx: 0.5, dy: 0.5),
    xRadius: 14,
    yRadius: 14
)
NSColor(white: 1, alpha: 0.10).setStroke()
border.lineWidth = 1
border.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("导出失败\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: "docs/banner.png"))
print("docs/banner.png  \(Int(width * scale))×\(Int(height * scale))")
