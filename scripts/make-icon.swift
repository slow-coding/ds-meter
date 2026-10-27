#!/usr/bin/env swift
// 生成 AppIcon.icns：深色圆角块 + 一圈「花了多少」的环（绿＝闲时、橙＝高峰）+ 中间一个 ¥。
// 用法：swift scripts/make-icon.swift   →  assets/AppIcon.icns（并留一张 1024 预览图）

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("assets", isDirectory: true)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let offPeak = NSColor(srgbRed: 0.263, green: 0.780, blue: 0.396, alpha: 1)   // 绿
let peak = NSColor(srgbRed: 0.965, green: 0.620, blue: 0.180, alpha: 1)      // 橙

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// 在 1024×1024 的坐标系里画一张，直接落在目标像素尺寸上（每个尺寸单独画，不从大图缩）。
func draw(size: CGFloat) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: 1024, height: 1024)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let body = NSBezierPath(
        roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
        xRadius: 184,
        yRadius: 184
    )

    // 底下那一层软阴影，让它在 Dock / Finder 里立起来
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 深色底：上面偏亮、下面更黑
    NSGradient(colors: [
        NSColor(srgbRed: 0.153, green: 0.169, blue: 0.208, alpha: 1),
        NSColor(srgbRed: 0.055, green: 0.063, blue: 0.078, alpha: 1),
    ])?.draw(in: body, angle: -90)

    // 上缘一道高光 + 一圈发丝边
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.10),
        NSColor.white.withAlphaComponent(0.0),
    ])?.draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.08).setStroke()
    body.lineWidth = 3
    body.stroke()

    // 柱状图：五根柱子（绿＝闲时、橙＝高峰），底下一条基线
    let variant = ProcessInfo.processInfo.environment["ICON_VARIANT"] ?? "1"
    let bottom: CGFloat = 292
    let barWidth: CGFloat
    let gap: CGFloat
    let heights: [CGFloat]
    let colors: [NSColor]
    switch variant {
    case "2":   // 五根，一路往上，最后那根橙
        barWidth = 108; gap = 38
        heights = [240, 330, 420, 510, 600]
        colors = [offPeak, offPeak, offPeak, offPeak, peak]
    default:    // 三根，一路往上，最后那根橙；四周留足空气
        barWidth = 120; gap = 58
        heights = [236, 354, 472]
        colors = [offPeak, offPeak, peak]
    }
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let left = 512 - total / 2

    for (index, height) in heights.enumerated() {
        let x = left + CGFloat(index) * (barWidth + gap)
        let rect = NSRect(x: x, y: bottom, width: barWidth, height: height)
        let bar = NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32)
        colors[index].setFill()
        bar.fill()
    }

    let baseline = NSBezierPath(
        roundedRect: NSRect(x: left, y: bottom - 34, width: total, height: 9),
        xRadius: 4.5,
        yRadius: 4.5
    )
    NSColor.white.withAlphaComponent(0.12).setFill()
    baseline.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for variant in variants {
    guard let data = draw(size: variant.size) else { continue }
    try? data.write(to: iconset.appendingPathComponent(variant.name))
}

let previewPath = ProcessInfo.processInfo.environment["ICON_PREVIEW"] ?? assets.appendingPathComponent("AppIcon-preview.png").path
if let preview = draw(size: 1024) {
    try? preview.write(to: URL(fileURLWithPath: previewPath))
}

let icns = assets.appendingPathComponent("AppIcon.icns")
try? FileManager.default.removeItem(at: icns)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try? task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "生成好了：\(icns.path)" : "iconutil 失败")
