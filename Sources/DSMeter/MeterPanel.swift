import AppKit
import SwiftUI

enum Style {
    static let hero = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let value = Font.system(size: 13, weight: .medium, design: .rounded)
    static let body = Font.system(size: 11, weight: .regular)
    static let hint = Color.secondary.opacity(0.75)

    static let peak = Color.orange
    static let offPeak = Color.green
    /// 缓存这条：命中蓝、未命中黄（比高峰那档橙更亮更黄，摆一起分得开）。
    static let hit = Color(red: 0.30, green: 0.60, blue: 1.00)
    static let miss = Color(red: 1.00, green: 0.84, blue: 0.28)
    /// token 那张柱子图的配色：跟钱那张分开（钱是绿 / 橙），免得两张图看混。
    static let tokenOffPeak = Color(red: 0.38, green: 0.66, blue: 0.72)
    static let tokenPeak = Color(red: 0.56, green: 0.49, blue: 0.84)

    /// 命中率后面那串对比的颜色：涨了蓝、跌了黄。
    /// 浅色底上不能直接用上面那两个值——亮蓝和白字旁的黄在小字号上读不清（白底对比 2.9:1），
    /// 所以浅色模式压暗一档，深色模式保持原样（原色在黑底上本来就有 6:1 以上）。
    /// 用传进来的 dark 而不是动态 NSColor：动态色在离屏渲染（浅色那张图）里不会跟着换，实测改不动。
    static func delta(better: Bool, dark: Bool) -> Color {
        if dark {
            return better ? hit : miss
        }
        return better
            ? Color(red: 0.10, green: 0.42, blue: 0.85)
            : Color(red: 0.54, green: 0.38, blue: 0.00)
    }
}

/// 面板的尺寸：只有这里写数，图那块按内容宽度算每一列的宽，不另抄一遍。
enum Layout {
    static let panelWidth: CGFloat = 420
    static let padding: CGFloat = 18
    static let contentWidth: CGFloat = panelWidth - padding * 2
}

/// 点状态栏那一格弹出来的面板。
/// 上半是账单（余额口径，涵盖所有消费），下半是 pi 的明细（本机日志口径，能拆到模型）。
struct MeterPanel: View {
    @ObservedObject var meter: Meter
    /// 深色 / 浅色：只有对比色要按它挑一档深浅（见 Style.delta）。
    @Environment(\.colorScheme) private var colorScheme
    /// 展开/收起那条的曲线：单调、不弹跳。带弹性的曲线会把高度顶过头再收回来，看着像抖。
    static let pickerAnimation = Animation.easeOut(duration: 0.18)

    /// 点面板上别的地方也把那条收起来：开着的时候点图、点分模型、点页脚，都该收。
    /// （日期钮和柱子自己有手势，不走这条。）
    private func closePicker() {
        guard showingPicker else { return }
        withAnimation(Self.pickerAnimation) { showingPicker = false }
    }

    /// 自检渲染时直接把那条 30 天展开，不用点。
    var pickerStartOpen: Bool = false
    @State private var hoveringDate = false
    /// 30 天那条：点日期按钮原地展开，再点收起（不另开窗口）。
    @State private var showingPicker = false

    init(meter: Meter, pickerStartOpen: Bool = false) {
        self.meter = meter
        self.pickerStartOpen = pickerStartOpen
        _showingPicker = State(initialValue: pickerStartOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !setupNeeded {
                // 余额这块点一下也收起那条（整块当成「别的地方」；
                // 用 VStack 不用 Group：Group 的修饰符是一人一份，两个元素之间的空隙点不着）
                VStack(alignment: .leading, spacing: 0) {
                    Text(T.balance.s).font(Style.body).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(meter.balance.amount.map(Fmt.money) ?? "—")
                            .font(Style.hero)
                            .monospacedDigit()
                        Spacer(minLength: 12)
                        nowTone
                        Text(balanceStamp)
                            .font(Style.body)
                            .foregroundStyle(.tertiary)
                            .help(T.balanceHelp.s)
                    }
                    .padding(.top, 2)
                }
                .dismissesPicker(closePicker)
            }

            if meter.needsLogin {
                loginPrompt
            } else if meter.snap.error != nil, meter.balance.amount == nil {
                Text(meter.snap.error ?? "")
                    .font(Style.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    daySwitch
                    dateButton
                    // 那天花了多少 + 那天过了多少 token，两行摞在同一个位置
                    // （金额定宽：位数一变 ¥1.94 → ¥128.21，右边的东西不会跟着跳）
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dayLoaded ? Fmt.money(day.money) : "—")
                            .font(Style.value)
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(tokenTotalText)
                            .font(.system(size: 8.5))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 58, alignment: .leading)
                    .dismissesPicker(closePicker)
                    Spacer(minLength: 8)
                    if let total = meter.snap.totalRecent {
                        // 跟左边那摞同一个顺序（金额在上、小字在下），两个金额落在同一条基线上。
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Fmt.money(total))
                                .font(Style.value)
                                .monospacedDigit()
                                .lineLimit(1)
                            Text(T.last30.s)
                                .font(.system(size: 8.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .help(T.last30.s)
                        .dismissesPicker(closePicker)
                    }
                }
                .padding(.top, 12)

                // 30 天那条：插在日期行下面，长出来的时候只把下面的图往下挤，
                // 上面一行（余额、日期、金额）一个像素都不动。再点一次日期钮、选完那天都收起。
                //
                // 动效只用 easeOut，不用 .smooth / .snappy 这类带弹性的曲线：
                // 高度上弹一下就是整块面板先长过头再缩回来，看起来是「震荡」。
                PickerStrip(meter: meter) { offset in
                    meter.selectDay(offset)
                    withAnimation(Self.pickerAnimation) { showingPicker = false }
                }
                .frame(height: showingPicker ? PickerStrip.height : 0, alignment: .top)
                .clipped()
                .opacity(showingPicker ? 1 : 0)
                .padding(.top, showingPicker ? 10 : 0)

                chart.padding(.top, 12).dismissesPicker(closePicker)

                splitColumns.padding(.top, 12).dismissesPicker(closePicker)

                unitPriceRow.padding(.top, 10).dismissesPicker(closePicker)

                requestsRow.padding(.top, 5).dismissesPicker(closePicker)

                if modelSlots > 0 {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(0..<modelSlots, id: \.self) { index in
                            let model = index < day.models.count ? day.models[index] : nil
                            HStack(spacing: 8) {
                                Text(model?.name ?? " ")
                                    .font(Style.body)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text(model.map { Fmt.money($0.cost) } ?? " ")
                                    .font(Style.body)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 12)
                    .dismissesPicker(closePicker)
                }

                footer.padding(.top, 13).dismissesPicker(closePicker)
            }
        }
        .padding(Layout.padding)
        .frame(width: Layout.panelWidth)
        .onAppear { Timing.mark("面板 onAppear") }
        // 面板被收起（点外面 / Esc / 失焦）时把那条一起收掉，不留到下次
        .onReceive(NotificationCenter.default.publisher(for: .dsMeterPanelClosed)) { _ in
            showingPicker = false
        }
    }

    // MARK: - 哪一天：今日 / 昨天两颗按钮，其余日子收在日期按钮的日历里

    /// 正在看的那天；还没取到时先摆个空的一天，别让整块往上跳。
    private var day: DayCost { meter.snap.days[meter.selected] ?? DayCost() }

    /// 那天的账取到了没（点开一个新日子时先摆「—」，别先闪一下 0）。
    private var dayLoaded: Bool { meter.snap.days[meter.selected] != nil }

    /// 前一天：「未命中」那行拿它比。（看最早那天时可能没有。）
    private var shadow: DayCost? { meter.snap.days[meter.selected + 1] }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        formatter.timeZone = PeakHours.timeZone
        return formatter
    }()

    private static func dayText(offset: Int) -> String {
        dayFormatter.string(from: PeakHours.daysBefore(offset))
    }

    /// 什么都没填：面板上不摆那个「—」，直接给两条路。
    private var setupNeeded: Bool {
        Account.apiKey == nil && Account.consoleToken == nil
    }

    /// 没设置 / 没登录 / 登录过期：一句话 + 一颗按钮，别让人去猜。
    private var loginPrompt: some View {
        let hasKey = Account.apiKey != nil
        let hasToken = Account.consoleToken != nil
        let title = !hasKey ? T.setupTitle.s : (hasToken ? T.loginExpiredTitle.s : T.loginTitle.s)
        let body = !hasKey ? T.setupBody.s : (hasToken ? T.loginExpiredBody.s : T.loginBody.s)
        return VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(Style.value)
            Text(body)
                .font(Style.body)
                .foregroundStyle(Style.hint)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                LoginWindow.shared.present { _ in meter.reloadAccount() }
            } label: {
                Text(T.loginAction.s)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            if !hasKey {
                Button(T.setupBalanceOnly.s) {
                    NotificationCenter.default.post(name: .dsMeterOpenSettings, object: nil)
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
            }
            HStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: 8))
                Text(T.loginStaysLocal.s)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
        .padding(.top, setupNeeded ? 4 : 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var daySwitch: some View {
        Picker("", selection: Binding(get: { meter.selected }, set: { meter.selectDay($0) })) {
            Text(T.today.s).tag(0)
            Text(T.yesterday.s).tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }

    /// 日期按钮：平时收起，只显示正在看的是哪天；点一下把下面那条 30 天原地展开，再点收起。
    private var dateButton: some View {
        Button {
            withAnimation(Self.pickerAnimation) { showingPicker.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                Text(Self.dayText(offset: meter.selected))
                    .font(Style.body)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(hoveringDate ? 0.16 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringDate = $0 }
        .help(showingPicker ? T.hidePicker.s : T.pickDay.s)
    }

    // MARK: - 柱状图：那天每小时（账单口径）；颜色只回答「这个小时贵不贵」

    private var chart: some View {
        let hours = day.hours
        let tokens = day.hourTokens
        // 两张图各用各的尺子，都是「今天 + 前两天」的窗口、所看那天兜底：
        // 窗口跟着日历走、不跟着所看那天走，切今天/昨天时两张图都不缩放。
        // 前一天同一小时的淡影（看今天时它就是昨天）：两层柱子都带
        let ghostHours = shadow?.hours
        let ghostTokens = shadow?.hourTokens
        let moneyPeak = ruler(hours, ghostHours)
        let tokenPeak = tokenRuler(tokens, ghostTokens)
        let unit = Fmt.tokenUnit(tokenPeak)
        // 只有看今天时才有「现在这个小时」可标
        let nowHour: Int? = meter.selected == 0 ? PeakHours.hour(of: Date()) : nil
        let gap: CGFloat = 2
        let moneyArea: CGFloat = 58
        let tokenArea: CGFloat = 40
        let labelHeight: CGFloat = 11
        // 每列宽度按面板内容宽度钉死：原来每列是 maxWidth: .infinity，哪一小时顶着数字、
        // 数字几个字，就把那一列撑宽一点；切日时数字一换，整排柱子和下面的刻度就跟着错开。
        let slot = (Layout.contentWidth - gap * 23) / 24
        return VStack(spacing: 0) {
            bars(hours, ghost: ghostHours, scale: moneyPeak, area: moneyArea, slot: slot, gap: gap, nowHour: nowHour,
                 offPeak: Style.offPeak, peak: Style.peak,
                 label: { $0 >= 0.1 ? Self.compact($0) : nil })
                // 底对齐：这一行的高度按「柱子 + 顶上那个数字」算，内容多高会随那天有没有数字变。
                // 不写 alignment: .bottom 时整行在固定高度里居中，柱子底会跟着上下跳 6pt。
                .frame(height: labelHeight + 2 + moneyArea, alignment: .bottom)

            // 钱的底线（也是 token 那张图的顶），「现在」那一刻标在这条线上
            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5)
                    if let nowHour {
                        Rectangle().fill(Color.primary.opacity(0.45))
                            .frame(width: slot - 1, height: 2)
                            .offset(x: CGFloat(nowHour) * (slot + gap))
                    }
                }
            }
            .frame(height: 2)
            .padding(.top, 4)

            // 第二张：token 量。跟上面那张一样的 24 根，换一套配色，不带数字（数在页脚）
            // 这层的抬头：只有名字。柱子上的裸数字用哪个单位，看日期那行下面写的总量。
            HStack(spacing: 4) {
                Text(T.tokenLayer.s).font(.system(size: 8.5)).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            bars(tokens, ghost: ghostTokens, scale: tokenPeak, area: tokenArea, slot: slot, gap: gap, nowHour: nowHour,
                 offPeak: Style.tokenOffPeak, peak: Style.tokenPeak, floor: 1,
                 label: { Fmt.barNumber($0, unit: unit.divisor) })
                .frame(height: labelHeight + 2 + tokenArea, alignment: .bottom)

            // token 那层的底线：柱子得站在一条线上，不然像浮着
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.top, 3)

            // 两张图共用这一行：每根柱子下面标出是哪一小时
            HStack(spacing: gap) {
                ForEach(0..<24, id: \.self) { hour in
                    Text("\(hour)")
                        .font(.system(size: 8.5))
                        .monospacedDigit()
                        .foregroundStyle(hour == nowHour ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: slot)
                }
            }
            .padding(.top, 5)
        }
        .help(T.hourChart.s)
    }

    /// 一层柱子：24 小时、每列宽一致、底对齐。钱和 token 两张只是值、尺子和配色不同。
    /// `ghost` 是前一天同一小时的值，画在今天这根背后拓一层淡的。
    private func bars(_ values: [Double], ghost: [Double]?, scale: Double, area: CGFloat, slot: CGFloat, gap: CGFloat,
                      nowHour: Int?, offPeak: Color, peak: Color, floor: CGFloat = 2,
                      label: @escaping (Double) -> String?) -> some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(values.enumerated()), id: \.offset) { hour, value in
                let height = max(floor, CGFloat(value / scale) * area)
                let ghostValue = ghost?[hour] ?? 0
                ZStack(alignment: .bottom) {
                    if ghostValue > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.primary.opacity(0.13))
                            .frame(height: max(floor, CGFloat(ghostValue / scale) * area))
                    }
                    vstackBody(number: label(value), color: tierColor(hour: hour, nowHour: nowHour,
                                                                      hasValue: value > 0, offPeak: offPeak, peak: peak),
                               height: height)
                }
                .frame(width: slot)
            }
        }
    }

    /// 日期那行下面那行小字：所看那天过了多少 token，单位跟柱子那层一致。
    private var tokenTotalText: String {
        guard dayLoaded else { return " " }
        let unit = Fmt.tokenUnit(tokenRuler(day.hourTokens, shadow?.hourTokens))
        return L.tokenTotal(L.trimDecimal(Double(day.tokenTotal) / unit.divisor), suffix: unit.suffix)
    }

    /// 柱子上那个数字 + 柱子本身。
    private func vstackBody(number: String?, color: Color, height: CGFloat) -> some View {
        VStack(spacing: 2) {
            if let number {
                Text(number)
                    .font(.system(size: 8.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // 英文的单位是 M/B/K，柱子上可能冒出三位数（"160"），14pt 的列塞不下就等比缩一点，
                    // 别截成 "1…"——那种截法比没有数字还难读。
                    .minimumScaleFactor(0.72)
            }
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(height: height)
        }
    }

    /// token 那张图的尺子：跟柱子一样取「今天 + 前两天」，所看那天兜底。
    private func tokenRuler(_ values: [Double], _ ghost: [Double]?) -> Double {
        var value = 1.0
        for offset in 0...2 {
            if let day = meter.snap.days[offset] {
                value = max(value, day.hourTokens.max() ?? 0)
            }
        }
        return max(value, values.max() ?? 0, ghost?.max() ?? 0)
    }

    /// 那一小时有没有花销：有就实、没有就淡，还没到的时段最淡。
    private func tierColor(hour: Int, nowHour: Int?, hasValue: Bool, offPeak: Color, peak: Color) -> Color {
        let tier = PeakHours.isPeak(hour: hour, weekday: day.weekday) ? peak : offPeak
        if let nowHour {
            if hour == nowHour { return tier }
            if hour > nowHour { return tier.opacity(0.12) }
        }
        return tier.opacity(hasValue ? 0.88 : 0.18)
    }

    /// 纵轴的尺子（元 / 小时）：三天窗口（今天、昨天、前天）的最大值，再用所看那天兜底。
    /// 窗口跟着日历走、不跟着所看的那天走，所以切今天/昨天时柱子不跟着缩放。
    private func ruler(_ hours: [Double], _ ghost: [Double]?) -> Double {
        var value = 0.01
        for offset in 0...2 {
            if let day = meter.snap.days[offset] {
                value = max(value, day.hours.max() ?? 0)
            }
        }
        return max(value, hours.max() ?? 0, ghost?.max() ?? 0)
    }

    /// 柱子上的数：≥10 取整，小的一位数给一位小数，省地方。
    private static func compact(_ value: Double) -> String {
        value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    // MARK: - 两根条并排：左闲时/高峰，右命中/未命中

    /// 一列 = 上面一个标签、中间一根条、下面一个标签；两列并排，条只要一半宽就够读。
    private var splitColumns: some View {
        let total = day.money
        let rate = day.hitRate
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                statLine(dot: Style.offPeak) {
                    Text(dayLoaded ? "\(T.offPeak.s) \(Fmt.money(day.offPeak))" : T.offPeakDash.s)
                        .font(Style.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                proportionBar(leftShare: total > 0 ? day.offPeak / total : 1, left: Style.offPeak, right: Style.peak)
                    .opacity(total > 0 ? 1 : 0.15)
                statLine(dot: Style.peak) {
                    Text(dayLoaded ? peakLabel(peak: day.peak) : T.peakDash.s)
                        .font(Style.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(L.peakHelp())

            VStack(alignment: .leading, spacing: 5) {
                statLine(dot: Style.hit) {
                    HStack(spacing: 4) {
                        Text(rate.map { "\(T.hit.s) \(Self.percent($0))" } ?? T.hitDash.s)
                            .foregroundStyle(.secondary)
                        if let delta = hitDelta {
                            // 括号比主体小一号：这是注解，不是第二个数。
                            Text(L.hitDelta(delta.text, relation: meter.selected == 0 ? T.vsYesterday.s : T.vsPreviousDay.s))
                                .font(.system(size: 10))
                                .foregroundStyle(Style.delta(better: delta.better, dark: colorScheme == .dark))
                        }
                    }
                    .font(Style.body)
                    .monospacedDigit()
                }
                .help(L.hitHelp())
                proportionBar(leftShare: rate ?? 1, left: Style.hit, right: Style.miss, minRight: 3)
                    .opacity(rate == nil ? 0.15 : 1)
                statLine(dot: Style.miss) {
                    Text(rate.map { "\(T.miss.s) \(Self.percent(1 - $0))" } ?? T.missDash.s)
                        .font(Style.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 一列里的一行字：前面一颗颜色点，后面跟数字。
    private func statLine<Content: View>(dot: Color, @ViewBuilder text: () -> Content) -> some View {
        HStack(spacing: 6) {
            legendDot(dot)
            text()
                .lineLimit(1)
        }
    }

    /// 夹在标签之间的那根条：左段 / 右段按比例分宽度。
    private func proportionBar(leftShare: Double, left: Color, right: Color, minRight: CGFloat = 0) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let rightWidth = max(minRight, width * (1 - max(0, min(1, leftShare))))
            HStack(spacing: 0) {
                Rectangle().fill(left).frame(width: max(0, width - rightWidth))
                Rectangle().fill(right).frame(width: rightWidth)
            }
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 8)
    }

    /// 周末整天都是闲时，就不摆一个 0；有高峰花销时把这一档的单价标在后边（"（2 倍价）"），
    /// 不把溢价换算成钱。倍数写成括号里的名词：早先裸写「¥128.21 ×2」，读起来像把金额再乘 2。
    private func peakLabel(peak: Double) -> String {
        guard day.hasPeakHours else { return T.peakAllOffPeak.s }
        guard peak >= 0.005 else { return "\(T.peak.s) \(Fmt.money(0))" }
        return L.peakMoney(Fmt.money(peak), multiplier: PeakHours.multiplierLabel)
    }

    // MARK: - 每亿 token 的单价

    /// 那天花了多少 ÷ 那天的 token 量。切日跟着变；后面括号里是前一天同一个数，
    /// 拿它当尺子——两个数一比就知道那天是高峰多、还是缓存没命中。
    private var unitPriceRow: some View {
        let price = dayLoaded ? day.unitPricePer100M : nil
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(T.unitPrice.s)
                .font(Style.body)
                .foregroundStyle(.secondary)
            if let price {
                Text(Fmt.money(price))
                    .font(Style.value)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(Style.value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if price != nil, let previous = meter.snap.comparisonUnitPrices(selected: meter.selected)?.previous {
                Text(L.unitPriceReference(
                    Fmt.money(previous),
                    relation: meter.selected == 0 ? T.yesterday.s : T.previousDay.s
                ))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .help(T.unitPriceHelp.s)
    }

    // MARK: - 请求数

    /// 那天平台记了多少次调用。一次 API 调用算一次（工具每转一圈、子代理跑的都在里面），
    /// 所以它比「我打过多少句话」大一个量级，不能当提问数看。
    private var requestsRow: some View {
        let count = dayLoaded && day.requests > 0 ? day.requests : nil
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(T.requests.s)
                .font(Style.body)
                .foregroundStyle(.secondary)
            if let count {
                Text(L.requestCount(count))
                    .font(Style.value)
                    .monospacedDigit()
                if let previous = shadow?.requests, previous > 0 {
                    Text(L.requestsReference(
                        Fmt.count(previous),
                        relation: meter.selected == 0 ? T.yesterday.s : T.previousDay.s
                    ))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                }
            } else {
                Text("—")
                    .font(Style.value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .help(T.requestHelp.s)
    }

    // MARK: - 页脚
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(runwayText).font(Style.body).foregroundStyle(.secondary)
                .help(L.runwayHelp())
            Spacer(minLength: 8)
            Button {
                NSWorkspace.shared.open(PeakHours.sourceURL)
            } label: {
                Text(priceLine).font(Style.body).foregroundStyle(PeakHours.isPriceStale ? Style.peak : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(PeakHours.sourceURL.absoluteString)
        }
    }

    // MARK: - 文案

    private func pair(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(Style.body).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(Style.value).monospacedDigit().lineLimit(1).fixedSize()
        }
    }

    /// 那天的命中率 - 前一天的命中率，单位是百分点。最早的那天没有前一天，不摆。
    /// 两个数怎么截到同一段时长，见 `Snapshot.comparisonHitRates`。
    private var hitDelta: (text: String, better: Bool)? {
        guard let pair = meter.snap.comparisonHitRates(selected: meter.selected) else { return nil }
        let delta = pair.current - pair.previous
        guard abs(delta) >= 0.001 else { return nil }
        return (String(format: "%+.1f%%", delta * 100), delta > 0)
    }

    /// 缓存里任何一天有命中数据，这一行就占着位置（切日时不会抽上去一格）。
    private var hasHitData: Bool {
        meter.snap.days.values.contains { $0.hitRate != nil }
    }

    /// 缓存里模型最多的那天决定摆几行，切日时这块高度不变。
    private var modelSlots: Int {
        min(3, meter.snap.days.values.map(\.models.count).max() ?? 0)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func legendDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }

    /// 现在这一档：跟菜单栏那颗灯同一个颜色、同一句话。
    private var nowTone: some View {
        HStack(spacing: 8) {
            legendDot(toneColor)
            Text(PeakHours.now.label).font(Style.body).foregroundStyle(.secondary)
        }
    }

    private var toneColor: Color {
        PeakHours.now.tone == .peak ? Style.peak : Style.offPeak
    }

    private var balanceStamp: String {
        if let date = meter.balance.fetchedAt { return L.updated(Fmt.clock(date)) }
        if meter.balance.error != nil { return T.balanceUnavailable.s }
        return "…"
    }

    /// 「还能用多久」：余额 ÷ 现在的日均。日均由 Trend 从最近两周拟出来（见 Trend.swift），
    /// 不是 30 天除一下——日均会台阶式地变，除 30 天会把「刚开始跑 agent」之前那些轻日子也算进来。
    private var runwayText: String {
        guard let days = meter.runwayDays else { return T.runwayNoData.s }
        return L.runway(days)
    }

    private var priceLine: String {
        let day = DateFormat.short(PeakHours.verifiedOn)
        if PeakHours.isPriceStale, let days = PeakHours.daysSinceVerified {
            return L.priceStale(days)
        }
        return "\(T.priceLine.s) \(day) ↗"
    }
}

enum DateFormat {
    /// "2026-10-26" → "10-26"
    static func short(_ isoDay: String) -> String {
        let parts = isoDay.split(separator: "-")
        return parts.count == 3 ? "\(parts[1])-\(parts[2])" : isoDay
    }
}

private extension View {
    /// 让一块区域可点：点了就调 `action`（面板上「别的地方」都长这样）。
    func dismissesPicker(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle()).onTapGesture(perform: action)
    }
}
