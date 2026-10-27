import AppKit
import SwiftUI

/// 面板里原地展开的那条：最近 30 天，一天一根柱子，柱高 = 那天花了多少。
///
/// 不是日历格子——30 个小方块怎么摆都像一堆积木；也不另开窗口。
/// 手法全照主面板那张按小时的图：细柱、0.5pt 的底线、8.5pt 的刻度、系统 popover 那层底。
struct PickerStrip: View {
    @ObservedObject var meter: Meter
    var onPick: (Int) -> Void

    /// 展开后的高度：柱子 34 + 空 3 + 底线 2 + 空 4 + 刻度 11 = 54。面板拿它做高度动效，
    /// 写死是故意的：动效只用插值一个数，不用每帧重新量内容（那会让 popover 一路追着改窗口大小，抖）。
    static let height: CGFloat = 54

    private static let barArea: CGFloat = 34
    private static let gap: CGFloat = 2
    /// 左右各留 14pt：两端的刻度（9/28、今天）比一根柱子宽，不留就被面板裁掉半个字。
    private static let sideInset: CGFloat = 14
    private static let slot: CGFloat = (Layout.contentWidth - sideInset * 2 - gap * 29) / 30

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
    private func bars(daily: [Double], reference: Double) -> some View {
        HStack(alignment: .bottom, spacing: Self.gap) {
            ForEach(Array(daily.enumerated()), id: \.offset) { index, money in
                let offset = daily.count - 1 - index
                let height = max(1.5, Self.heat(money: money, reference: reference) * Self.barArea)
                let isSelected = offset == meter.selected
                let isHovering = hovering == offset
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.92 : (isHovering ? 0.62 : 0.34)))
                    .frame(width: Self.slot, height: height)
                    .frame(width: Self.slot, height: Self.barArea, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(offset) }
                    .onHover { hovering = $0 ? offset : (hovering == offset ? nil : hovering) }
                    .help("\(Self.dayText(offset: offset)) \(Self.weekdayName(offset: offset)) · \(Fmt.money(money))")
            }
        }
        .frame(height: Self.barArea, alignment: .bottom)
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

    /// 柱高 0…1：0 是那天没花钱，1 是这 30 天里最贵那几天的水平。
    ///
    /// 分母取 85 分位而不是最大值——偶尔一天有个大活儿，用最大值会把其他天全压成矮墩。
    static func heat(money: Double, reference: Double) -> Double {
        guard reference > 0, money > 0 else { return 0 }
        return pow(min(1, money / reference), 0.8)
    }

    /// 分母：这 30 天里有花钱的那些天，按金额排序取 85 分位。
    static func reference(_ daily: [Double]) -> Double {
        let shown = Array(daily.dropFirst())          // 第一个是窗口外那天，柱子里不摆它
        let positive = shown.filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return 0 }
        return positive[Int((Double(positive.count - 1) * 0.85).rounded())]
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
