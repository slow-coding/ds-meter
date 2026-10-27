#!/usr/bin/env swift
// 生成 AppIcon.icns：深色圆角块 + 一颗绿灯 + 白色的 ¥，跟菜单栏那一格同一套符号。
// 用法：swift scripts/make-icon.swift   →  assets/AppIcon.icns（并留一张 1024 预览图）

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("assets", isDirectory: true)
// 中间产物丢临时目录，不在工程里留 build/
let stage = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let iconset = stage
try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func roundedDesignFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// 把字画进一张草稿位图，扫出不透明像素的框，得到真正的「墨迹范围」（相对绘制原点的坐标）。
func inkBounds(of text: NSAttributedString) -> CGRect {
    let textSize = text.size()
    let canvas = CGSize(width: ceil(textSize.width) + 40, height: ceil(textSize.height) + 40)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width * 2),
        pixelsHigh: Int(canvas.height * 2),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return CGRect(origin: .zero, size: textSize) }
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    text.draw(at: NSPoint(x: 20, y: 20))
    NSGraphicsContext.restoreGraphicsState()

    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX > minX, maxY > minY else { return CGRect(origin: .zero, size: textSize) }
    let scale = canvas.width / CGFloat(rep.pixelsWide) * 2 // 位图是 2x
    let rect = CGRect(
        x: CGFloat(minX) * scale / 2 - 20,
        y: CGFloat(rep.pixelsHigh - 1 - maxY) * scale / 2 - 20,
        width: CGFloat(maxX - minX) * scale / 2,
        height: CGFloat(maxY - minY) * scale / 2
    )
    return rect
}

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
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let context = NSGraphicsContext.current?.cgContext else { return nil }

    // 圆角块：Big Sur 之后 macOS 图标的比例（内容占 80%，圆角 22.4%）
    let inset = size * 0.098
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plate.width * 0.2237
    let shape = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [
        NSColor(srgbRed: 0.153, green: 0.180, blue: 0.239, alpha: 1).cgColor,
        NSColor(srgbRed: 0.051, green: 0.059, blue: 0.078, alpha: 1).cgColor,
    ]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.midX, y: plate.maxY),
            end: CGPoint(x: plate.midX, y: plate.minY),
            options: []
        )
    }
    // 顶部一道很淡的高光，让块面不显得死平
    context.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
    context.fill(CGRect(x: plate.minX, y: plate.maxY - plate.height * 0.012, width: plate.width, height: plate.height * 0.012))
    context.restoreGState()

    // 内部符号：绿灯 + ¥。按「墨迹框」而不是包围盒定位——包围盒带降部空白，用它会整体偏上。
    let glyphSize = plate.width * 0.47
    let font = roundedDesignFont(size: glyphSize, weight: .bold)
    let text = NSAttributedString(string: "¥", attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
    ])
    let ink = inkBounds(of: text)
    let dotDiameter = plate.width * 0.135
    let gap = plate.width * 0.042
    let groupWidth = dotDiameter + gap + ink.width
    let groupLeft = plate.midX - groupWidth / 2
    let centerY = plate.midY + plate.height * 0.004

    context.saveGState()
    context.setFillColor(NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(
        x: groupLeft,
        y: centerY - dotDiameter / 2,
        width: dotDiameter,
        height: dotDiameter
    ))
    context.restoreGState()

    let inkCenterX = groupLeft + dotDiameter + gap + ink.width / 2
    text.draw(at: NSPoint(x: inkCenterX - ink.midX, y: centerY - ink.midY))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// 每个尺寸单独画，别从小图放大
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

if let preview = draw(size: 1024) {
    try? preview.write(to: assets.appendingPathComponent("AppIcon-preview.png"))
}

let icns = assets.appendingPathComponent("AppIcon.icns")
try? FileManager.default.removeItem(at: icns)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try? task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "生成好了：\(icns.path)" : "iconutil 失败")
