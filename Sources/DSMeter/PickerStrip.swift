import AppKit
import SwiftUI

/// 面板里原地展开的那条：最近 30 天，一天一根柱子，柱高 = 那天花了多少。
///
/// 不是日历格子——30 个小方块怎么摆都像一堆积木；也不另开窗口。
/// 手法全照主面板那张按小时的图：细柱、0.5pt 的底线、8.5pt 的刻度、系统 popover 那层底。
struct PickerStrip: View {
    @ObservedObject var meter: Meter
    var onPick: (Int) -> Void

    /// 展开后的高度：数字 12 + 柱子 44 + 空 3 + 底线 2 + 空 4 + 刻度 11 = 76。面板拿它做高度动效，
    /// 写死是故意的：动效只用插值一个数，不用每帧重新量内容（那会让 popover 一路追着改窗口大小，抖）。
    static let height: CGFloat = 76

    /// 柱子顶上那行数字的高度。给最贵那几天标金额用，留白留在这里，柱子不从这块地方借。
    private static let labelHeight: CGFloat = 12
    private static let barArea: CGFloat = 44
    private static let gap: CGFloat = 2
    /// 左右各留 14pt：两端的刻度（9/28、今天）比一根柱子宽，不留就被面板裁掉半个字。
    private static let sideInset: CGFloat = 14
    private static let slot: CGFloat = (Layout.contentWidth - sideInset * 2 - gap * 29) / 30

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering: Int?

    var body: some View {
        let daily = Array(meter.snap.daily.dropFirst())        // 30 天，最后一个 = 今天
        let reference = Self.reference(meter.snap.daily)
        VStack(spacing: 0) {
            bars(daily: daily, reference: reference)
            baseline
            axis(daily: daily)
            Spacer(minLength: 0)
        }
        .frame(height: Self.height, alignment: .top)
    }

    /// 30 根柱子：底对齐、列宽一致（跟面板那张图一样把列宽写死，切日时不会跟着抖）。
    /// 最贵那几天柱顶上标金额——没有数字的话，「哪天最贵、贵多少」只能靠眼睛量高度。
    private func bars(daily: [Double], reference: Double) -> some View {
        let tops = Self.topDays(daily)
        return HStack(alignment: .bottom, spacing: Self.gap) {
            ForEach(Array(daily.enumerated()), id: \.offset) { index, money in
                let offset = daily.count - 1 - index
                let height = max(1.5, Self.heat(money: money, reference: reference) * Self.barArea)
                let isSelected = offset == meter.selected
                let isHovering = hovering == offset
                let label: String? = tops.contains(offset) ? Self.amountText(money) : nil
                // 两根高峰挨在一起时，右边那个标签抬一层，不然两个数字压在一起
                let stagger: CGFloat = (label != nil && tops.contains(offset + 1)) ? -Self.labelHeight : 0
                VStack(spacing: 1) {
                    if let label {
                        Text(label)
                            .font(.system(size: 8.5))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .offset(y: stagger)
                    }
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.barColor(money: money, reference: reference, scheme: colorScheme)
                        .opacity(isSelected || isHovering ? 1 : 0.82))
                    .frame(width: Self.slot, height: height)
                    // 上了色以后「选中」不能再靠深浅区分（灰白柱那套不管用了）：
                    // 选中的那根头顶压一条短横线，鼠标悬停那天挂层淡描边。
                    .overlay(alignment: .top) {
                        if isSelected {
                            Rectangle()
                                .fill(Color.primary.opacity(0.85))
                                .frame(width: Self.slot, height: 2)
                                .offset(y: -4)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color.primary.opacity(isHovering ? 0.3 : 0), lineWidth: 1)
                    )
                    .frame(width: Self.slot, height: Self.barArea, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(offset) }
                    .onHover { hovering = $0 ? offset : (hovering == offset ? nil : hovering) }
                    .help("\(Self.dayText(offset: offset)) \(Self.weekdayName(offset: offset)) · \(Fmt.money(money))")
                }
                .frame(width: Self.slot, height: Self.barArea + Self.labelHeight, alignment: .bottom)
            }
        }
        .frame(height: Self.barArea + Self.labelHeight, alignment: .bottom)
        .padding(.horizontal, Self.sideInset)
    }

    /// 柱子的底线：跟面板两张图一样，一条 0.5pt 的淡线，柱子有地方站。
    /// 今天那根底下再压一小段实线——面板上「现在这个小时」也是这么标的。
    private var baseline: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 0.5)
            Rectangle()
                .fill(Color.primary.opacity(0.45))
                .frame(width: Self.slot - 1, height: 2)
                .offset(x: 29 * (Self.slot + Self.gap))
        }
        .frame(height: 2)
        .padding(.horizontal, Self.sideInset)
        .padding(.top, 3)
    }

    /// 刻度：只标 5 个点——最早那天、每 7 天、今天。30 个 8.5pt 的字挤在 11pt 的格子里必然糊作一团；
    /// 正在看的那天在面板上那行已经写清楚了，这里不用再标。
    private func axis(daily: [Double]) -> some View {
        let last = daily.count - 1
        let marks: Set<Int> = [0, 7, 14, 21, last]
        return HStack(spacing: Self.gap) {
            ForEach(Array(daily.indices), id: \.self) { index in
                let offset = last - index
                Text(marks.contains(index) ? (index == last ? T.todayLabel.s : Self.axisText(offset: offset)) : " ")
                    .font(.system(size: 8.5))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: Self.slot)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 11, alignment: .top)
        .padding(.horizontal, Self.sideInset)
        .padding(.top, 4)
    }

    /// 柱高 0…1：0 是那天没花钱，1 是这 30 天最贵那天的水平。线性，不压缩。
    ///
    /// 原来分母取 85 分位、再开 0.8 次方，超过分位的那些天全撞在同一个高度上——
    /// 30 天里最贵的三四天看着一样贵，读的人以为数据错了。现在按最大值线性映射，
    /// 贵多少就高多少；柱区也从 34pt 提到 44pt，给最贵那天留出地方。
    static func heat(money: Double, reference: Double) -> Double {
        guard reference > 0, money > 0 else { return 0 }
        return min(1, money / reference)
    }

    /// 一根柱子的颜色：只有一个主色调（面板上「命中率」那支蓝），深浅跟着金额走——
    /// 便宜的天是压暗的蓝，贵的那几天才亮起来。橙色试过，在真实数据上偏土黄，
    /// 跟面板里那几支橙糊成一片；蓝色在这块深底上最干净，也不跟绿/橙打架。
    static func barColor(money: Double, reference: Double, scheme: ColorScheme) -> Color {
        let t = heat(money: money, reference: reference)
        guard t > 0.03 else { return Color.primary.opacity(0.10) }   // 那天没花钱：一根淡灰
        let hue = 0.595                                             // 蓝（≈214°，跟命中率那支同相）
        if scheme == .dark {
            // 深底上：越贵越亮越实，便宜的天沉下去（亮度压不到太低，不然跟灰底分不开）
            return Color(hue: hue, saturation: 0.30 + 0.42 * t, brightness: 0.48 + 0.44 * t)
        }
        // 浅底上反过来：越贵越深，不然最贵那根在白底上发飘
        return Color(hue: hue, saturation: 0.34 + 0.40 * t, brightness: 0.99 - 0.30 * t)
    }

    /// 柱顶上要标金额的那几根：30 天里最贵的三根（offset，0 = 今天）。没花钱的天不算。
    static func topDays(_ daily: [Double], count: Int = 3) -> Set<Int> {
        let shown = Array(daily.dropFirst())          // 第一个是窗口外那天，柱子里不摆它
        let last = shown.count - 1
        return Set(shown.enumerated()
            .filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
            .prefix(count)
            .map { last - $0.offset })
    }

    /// 柱顶那个金额：一列才 11pt 宽，写不下「¥121.08」。≥10 给整数，1 到 10 一位小数。
    static func amountText(_ money: Double) -> String {
        money >= 10 ? String(format: "%.0f", money) : String(format: "%.1f", money)
    }

    /// 分母：这 30 天里的最大值（柱子里不摆的那个窗口外那天不算）。
    static func reference(_ daily: [Double]) -> Double {
        let shown = Array(daily.dropFirst())
        return shown.max() ?? 0
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        formatter.timeZone = PeakHours.timeZone
        return formatter
    }()

    private static let axisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.timeZone = PeakHours.timeZone
        return formatter
    }()

    static func dayText(offset: Int) -> String {
        dayFormatter.string(from: PeakHours.daysBefore(offset))
    }

    static func axisText(offset: Int) -> String {
        axisFormatter.string(from: PeakHours.daysBefore(offset))
    }

    /// 周日…周六（系统周日 = 1，换成 0…6）
    static func weekdayName(offset: Int) -> String {
        L.weekday((PeakHours.weekday(of: PeakHours.daysBefore(offset)) - 1 + 7) % 7)
    }
}
