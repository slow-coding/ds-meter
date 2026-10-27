import AppKit

/// 状态栏那一格：一颗灯（闲时绿 / 高峰黄）+ 今天的花费。
/// 灯用 NSTextAttachment 画，位置按基线算死的——不用 ● 字形，那样中英文基线对不齐。
enum StatusTitle {
    private static let fontSize: CGFloat = 13
    private static let dotDiameter: CGFloat = 7
    /// 灯底边离基线多远：让它落在数字的视觉中线上（13pt 的字，数字中线约在基线上 4.5pt）。
    private static let dotRise: CGFloat = 1.1

    static func make(amount: String, tone: PeakHours.Tone) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let attachment = NSTextAttachment()
        attachment.image = dot(color: tone == .peak ? .systemYellow : .systemGreen)
        attachment.bounds = CGRect(x: 0, y: dotRise, width: dotDiameter, height: dotDiameter)
        title.append(NSAttributedString(attachment: attachment))
        title.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: fontSize)]))
        title.append(NSAttributedString(string: amount, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
        ]))
        return title
    }

    private static func dot(color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: dotDiameter, height: dotDiameter), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
