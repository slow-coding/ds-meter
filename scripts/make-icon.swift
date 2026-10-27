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

    // 深灰底：不是纯黑，也不带渐变，柱子是唯一的颜色
    NSColor(srgbRed: 0.086, green: 0.094, blue: 0.110, alpha: 1).setFill()
    body.fill()

    // 发丝边：一圈很淡的同色，只为在黑底上留个轮廓
    let border = NSBezierPath(roundedRect: NSRect(x: 101, y: 101, width: 822, height: 822), xRadius: 183, yRadius: 183)
    NSColor.white.withAlphaComponent(0.09).setStroke()
    border.lineWidth = 2
    border.stroke()

    // 柱状图：五根柱子（绿＝闲时、橙＝高峰），底下一条基线
    let bottom: CGFloat = 292
    let barWidth: CGFloat = 120
    let gap: CGFloat = 58
    let heights: [CGFloat] = [236, 354, 472]
    let colors: [NSColor] = [offPeak, offPeak, peak]
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let left = 512 - total / 2

    for (index, height) in heights.enumerated() {
        let x = left + CGFloat(index) * (barWidth + gap)
        let rect = NSRect(x: x, y: bottom, width: barWidth, height: height)
        let bar = NSBezierPath(roundedRect: rect, xRadius: 38, yRadius: 38)

        // 柱身：上浅下深，像被上面的光打到
        let base = colors[index]
        NSGradient(colors: [
            base.blended(withFraction: 0.12, of: .white) ?? base,
            base,
        ])?.draw(in: bar, angle: -90)

        // 上缘压一道很细的高光，边界就利落了
        NSGraphicsContext.saveGraphicsState()
        bar.addClip()
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - 3, width: rect.width, height: 3)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSColor.white.withAlphaComponent(0.12).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: left, y: bottom - 34, width: total, height: 6),
        xRadius: 3, yRadius: 3
    ).fill()

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
