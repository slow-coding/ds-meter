import AppKit
import SwiftUI

enum Style {
    static let hero = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let value = Font.system(size: 13, weight: .medium, design: .rounded)
    static let body = Font.system(size: 11, weight: .regular)
    static let hint = Color.secondary.opacity(0.75)
    /// 块标题统一这两档（2026-11-07）：11pt medium，总数加等宽数字。
    /// 全面板的标题一个字号，字长不缩（minimumScaleFactor 一律不挂，放不下就改文案）。
    static let sectionTitle = Font.system(size: 11, weight: .medium)
    static let sectionTotal = Font.system(size: 11, weight: .medium).monospacedDigit()

    // 颜色只表示「这是什么」，一种颜色只指一件事（2026-11-08 他定的）。
    //   绿 = 闲时（半价）  ·  黄 = 高峰（双倍）：跟菜单栏那颗灯同一套，两张图都按这个上色
    //   紫 = 子智能体（走订阅、不花钱的那半）
    //   蓝 = 检索次数  ·  青 = 缓存命中  ·  灰 = 未命中 / 影子 / 还没到的时段
    // 原来钱用琥珀两档表示闲时/高峰，靠明度差分——他说「闲时和高峰颜色没有错开」，
    // 所以时段档位回到绿/黄两个色相，跟菜单栏一致；代价是两张图的柱子颜色一样，
    // 靠标题（¥ / 今日 token）和柱顶那个数认。
    /// 闲时（半价）：绿
    static let offPeak = Color(red: 0.28, green: 0.72, blue: 0.38)
    /// 高峰（双倍价）：黄
    static let peak = Color(red: 0.93, green: 0.70, blue: 0.10)
    /// 检索次数：蓝
    static let search = Color(red: 0.36, green: 0.61, blue: 0.94)
    /// 缓存命中：青。未命中：灰（2026-11-08 他看的：先玫红→太夸张，棕→又回来，最后定灰）。
    static let hit = Color(red: 0.40, green: 0.72, blue: 0.74)
    static let miss = Color(red: 0.58, green: 0.58, blue: 0.60)
    /// 子智能体（走订阅、不花钱的那半）：紫。试过青，贴在绿柱上分不出来，换成紫。
    /// 它不分闲时/高峰，反正不花钱。
    static let subagent = Color(red: 0.64, green: 0.51, blue: 0.92)
    /// token 那张图跟钱同一套档位色（绿闲时 / 黄高峰）。
    static let tokenOffPeak = offPeak
    static let tokenPeak = peak

    /// 「比昨天 +2.2%」：涨跌靠符号读，不占色相。
    static func delta(better: Bool, dark: Bool) -> Color {
        gray(dark, faint: !better)
    }

    /// 灰字统一从这里取（浅色模式灰字太浅，2026-11-07 遗留项）：
    /// 浅色底上 tertiary（≈25% 黑）对比只剩 ~1.9:1，接近看不见；secondary（≈50%）在 8.5pt 上也只有 ~4:1。
    /// 所以浅色一律给 65% 黑（白底 ≈6.9:1），深色维持调用处原来的档位。
    /// 跟 delta 同一个做法：传 dark 的 Bool 而不是用动态 NSColor——动态色在离屏渲染（浅色那张图）里不会跟着换。
    static func gray(_ dark: Bool, faint: Bool = false) -> Color {
        if dark {
            return faint ? Color(nsColor: .tertiaryLabelColor) : Color(nsColor: .secondaryLabelColor)
        }
        return Color.primary.opacity(faint ? 0.55 : 0.65)
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
    /// 柱顶数字那一行的高度。stagger 抬一层就抬这么多（bars / vstackBody 都要用）。
    static let barLabelHeight: CGFloat = 11
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
    /// 服务状态（2026-11-07）：feed 10 分钟一次、本机探测跟着余额走，这里只认它发布的数。
    @ObservedObject private var status = ServiceStatus.shared

    init(meter: Meter, pickerStartOpen: Bool = false) {
        self.meter = meter
        self.pickerStartOpen = pickerStartOpen
        _showingPicker = State(initialValue: pickerStartOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !setupNeeded {
                // 左上角那个大数（2026-11-07 换的位）：**先看今天花了多少**，余额退到第二行。
                // 他原话：「左上角应该大的就是今天的消耗，其次才是什么余额」。
                // 没登录/没数据的时候大数位还是留给余额，否则这块空着。
                // hero 并排两个大数（2026-11-07 他亲口要的）：「今天我耗了多少钱，然后总共耗了多少 token，
                // 这两个都是大字，因为这两个就是我最关注的点。」右边那摞状态小字压在最右，baseline 对齐大数。
                // 原先金额下面那行「17.1 亿 token，其中 16.1 亿 计费」整行删了：17.1 就是右边这个大数、
                // 16.1 是主智能体 header 的数、1.1 是子智能体 header 的数——三个数已各就各位，再写一遍就是重复。
                // 两列各自「标签压在数字正上方」、都 leading 对齐；中间隔 24pt，不再用 Spacer 把右列推到最右——
                // 原先标签右对齐、数字左对齐，两列不在一条竖线上。状态那摞（● 现在 闲时 / 更新时间）单独
                // 一个 Spacer 推到最右、trailing 对齐（2026-11-07 改）。
                // 列间距 24 → 16（2026-11-07）：两列下面各挂一条括号后，括号 + 状态四样挤一行 420 必然截断。
                // 状态那摞 overlay 到右上角，靠「padding.top + 两行 13pt」压在数字那一行的高度里——
                // 原来 padding 16 算下来是 45pt，而括号行从 48pt 才开始，**只差 3pt**（2026-11-07 17:42：
                // 真窗口里那几个点的字高差就直接压在「子智能体 5.2 亿 29%」上，重叠）。
                // 现在不往下压：跟标签行同一个顶边（padding 1），两行到 30pt 就完了，括号行 48pt 才起，
                // 留出 18pt。再往下试探过「改成第三列」——状态那栏要 95pt，括号行被挤到截断（7…），退回 overlay。
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(heroIsSpend ? heroSpendLabel : T.balance.s)
                                .font(Style.sectionTitle).foregroundStyle(.secondary).lineLimit(1)
                            Text(heroMoney)
                                .font(Style.hero)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            if heroIsSpend {
                                spendBracket
                                    .lineLimit(1)
                                    .minimumScaleFactor(bracketScale)
                            }
                        }
                        if heroIsSpend {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(heroTokensLabel)
                                    .font(Style.sectionTitle).foregroundStyle(.secondary).lineLimit(1)
                                tokenHeroNumber
                                tokenBracket
                                    .lineLimit(1)
                                    .minimumScaleFactor(bracketScale)
                            }
                        }
                    }
                    .dismissesPicker(closePicker)
                    VStack(alignment: .trailing, spacing: 3) {
                        nowTone
                        serviceLight
                        Text(balanceStamp)
                            .font(Style.body)
                            .foregroundStyle(Style.gray(colorScheme == .dark, faint: true))
                    }
                    .lineLimit(1)
                    // 英文版这摞最长（"Off-peak now" / "updated 16:18"）：先靠缩到 ~9pt，不够再整体缩 0.85。
                    // 两个大数不许跟着缩，它们是这屏的主角。
                    .minimumScaleFactor(0.85)
                    // 顶到面板右边界（maxWidth: .infinity + trailing）：ZStack 的宽是子视图里最宽的那个，
                    // 括号行一短，ZStack 就变窄，trailing 状态那一摞就跟着往左跑掉、压到「今日 token」上
                    // （2026-11-07 删掉「计费…」半行后的实测）。自己撑满一行，宽度就不再跟着括号行变。
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    // 跟标签行同一个顶边，三行（nowTone / serviceLight / 更新时间）在 45pt 内结束（11pt 字三行 + 2×3 间距），碰不到 48pt 起的括号行。
                    .padding(.top, 1)
                    .help(T.balanceHelp.s)
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
                    // 第二行的金额位现在是**余额**（以前是当天花费，2026-11-07 跟大数位换了个位置）：
                    // 金额在上、小标签在下，跟右边「近 30 天」那一槐同一个顺序。
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meter.balance.amount.map(Fmt.money) ?? "—")
                            .font(Style.value)
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(T.balance.s)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 58, alignment: .leading)
                    .help(T.balanceHelp.s)
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

                if modelSlots > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        // 总数用各模型之和，不用 money：检索费没挂在模型上，用 money 会把检索费数第二遍。
                        layerHeader(T.byModel.s, Fmt.money(day.modelsCost))
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<modelSlots, id: \.self) { index in
                                let model = index < day.models.count ? day.models[index] : nil
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model?.name ?? " ")
                                        .font(Style.body)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text(model.map { Fmt.money($0.cost) } ?? " ")
                                        .font(Style.value)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
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
        .onReceive(NotificationCenter.default.publisher(for: .piMeterPanelClosed)) { _ in
            showingPicker = false
        }
        // 换天就收起那条（2026-11-07 他报的：在 30 天那条里点某一天不回弹，只能再点日期钮）。
        // 不靠那一条自己的 onPick 关：那条里点中之后是「选中 + 关」两步，只要那一步因为
        // 什么原因没落到界面上，状态就留在开着。改成看 selected：不管从哪换的天
        // （条上点、今日/昨天、日期钮里选），换完就收。
        .onChange(of: meter.selected) { _ in
            guard showingPicker else { return }
            withAnimation(Self.pickerAnimation) { showingPicker = false }
        }
    }

    // MARK: - 服务状态：照官方页顶部那排灯（2026-11-07 重做）

    @State private var hoveringLight = false

    /// 顶部右侧那摞里的服务状态：一颗灯 + 两三个字，点它开 status.deepseek.com。
    /// 那行整行的块删了（2026-11-08 他定的：看历史那天面板不能比看今天矮一截）；
    /// 数据照旧拉（menu bar 那个告警、--status-live 还用它），只是不再占一行。
    /// 灯色优先级跟 `headerText` 一致：官方事件 > 本机波动 > 正常；serviceAlert 最狠，直接红。
    private var serviceLight: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "https://status.deepseek.com")!)
        } label: {
            HStack(spacing: 6) {
                legendDot(serviceColor)
                Text(headerText)
                    .font(Style.body)
                    .foregroundStyle(Style.gray(colorScheme == .dark))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveringLight = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(serviceHelp)
    }

    private var serviceColor: Color {
        // 服务健康不是钱/ token/ 检索任何一件，不占色相：用中性灰的三档，出事了最实。
        if let event = status.event, event.status != "resolved" {
            return status.serviceAlert ? Color.primary : Style.gray(colorScheme == .dark)
        }
        if status.jitterVisible { return Style.gray(colorScheme == .dark) }
        return Style.gray(colorScheme == .dark, faint: true)
    }

    /// 悬停提示：基础文案 + 进行中事件的标题（标题不再单独占一行，挪到这里）
    private var serviceHelp: String {
        var help = T.serviceStatusHelp.s
        if let event = status.event, event.status != "resolved" {
            help += "\n" + event.title
        }
        return help
    }

    /// 右侧状态词：官方事件 > 本机波动 > 正常。判定优先级只有这一处。
    private var headerText: String {
        if let event = status.event, event.status != "resolved" {
            return L.serviceOngoing(minutes: Int(Date().timeIntervalSince(event.updated) / 60))
        }
        return status.jitterVisible ? T.serviceJitter.s : T.serviceOK.s
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
                    NotificationCenter.default.post(name: .piMeterOpenSettings, object: nil)
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
        let toolCalls = day.hourToolCalls.map(Double.init)
        let toolScale = Double(toolRuler)
        // token 那张图：一小时一根柱子，柱高 = 那个小时一共过了多少 token（主线程 + 各子线程），
        // **不分段**（2026-11-08 他定的：钱不分主次，柱子上也不切一刀。子智能体走 GLM、走订阅，
        // 对它来说就是免费的，钱那边本来就没它的份；token 这边只关心那个小时一共多少）。
        let laneSeries = activeLanes.map { lane in
            (lane: lane, values: (day.subagents[lane.id]?.hourTokens ?? []).map(Double.init))
        }
        let ghostLaneSeries = activeLanes.compactMap { lane -> (lane: SubagentLane, values: [Double])? in
            guard let hours = shadow?.subagents[lane.id]?.hourTokens else { return nil }
            return (lane, hours.map(Double.init))
        }
        let stackTotal = Self.stack(tokens, laneSeries.map(\.values))
        let ghostStack = ghostTokens.map { main in Self.stack(main, ghostLaneSeries.map(\.values)) }
        let stackPeak = tokenRuler(stackTotal, ghostStack)
        let unit = Fmt.tokenUnit(stackPeak)
        // 主线程和子线程两个 header 的总数用同一个量级：它们是同一根比例条上的两个数，
        // 「主线程 16.1 亿」旁边摆个「子线程 6203 万」是同一块里换尺子（2026-11-07 遗留项）。
        // 量级按这块显示的最大总数挑，小的那个跟着走，小数位才能对齐。
        let headerUnit = L.tokenUnit(Double(max(day.tokenTotal,
                                                activeLanes.map { day.subagents[$0.id]?.tokens ?? 0 }.max() ?? 0)))
        // 只有看今天时才有「现在这个小时」可标
        let nowHour: Int? = meter.selected == 0 ? PeakHours.hour(of: Date()) : nil
        let gap: CGFloat = 2
        let moneyArea: CGFloat = 58
        let tokenArea: CGFloat = 40
        let toolArea: CGFloat = 30
        let labelHeight = Self.barLabelHeight
        // 每列宽度按面板内容宽度钉死：原来每列是 maxWidth: .infinity，哪一小时顶着数字、
        // 数字几个字，就把那一列撑宽一点；切日时数字一换，整排柱子和下面的刻度就跟着错开。
        let slot = (Layout.contentWidth - gap * 23) / 24
        return VStack(spacing: 0) {
            bars(hours, ghost: ghostHours, scale: moneyPeak, area: moneyArea, slot: slot, gap: gap, nowHour: nowHour,
                 offPeak: Style.offPeak, peak: Style.peak,
                 // 同样的口径（2026-11-07）：有 0.1 写 0.1，不到 ¥0.1 不写（不另放记号）。
                 label: { _, value in value >= 0.1 ? Self.compact(value) : nil })
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

            // 第二张：token 量。一根柱子 = 那个小时一共过了多少 token：底下青的是主线程，
            // 顶上绿的是子智能体（走订阅、不花钱的那半）。钱不分主次，但 token 这边他要看到
            // 子智能体花了多少（2026-11-08：「子智能体的 token 消耗量我要看到」）。
            layerHeader(heroTokensLabel, nil)
            .padding(.top, 5)

            tokenBars(main: tokens, caps: laneSeries.map(\.values), capColor: Style.subagent,
                      ghost: ghostStack, scale: stackPeak,
                      area: tokenArea, slot: slot, gap: gap, nowHour: nowHour,
                      tier: { hour, hasValue in
                          tierColor(hour: hour, nowHour: nowHour, hasValue: hasValue,
                                    offPeak: Style.tokenOffPeak, peak: Style.tokenPeak)
                      },
                      label: { _, value in Fmt.barNumberAll(value, unit: unit.divisor) },
                      hover: { hour in
                          guard hour < tokens.count else { return nil }
                          var parts: [(String, String)] = [(T.mainThread.s, L.tokenSize(Int(tokens[hour]), unit: headerUnit))]
                          for lane in laneSeries where hour < lane.values.count && lane.values[hour] > 0 {
                              parts.append((lane.lane.title, L.tokenSize(Int(lane.values[hour]), unit: headerUnit)))
                          }
                          guard parts.count > 1 else { return nil }
                          return L.stackBarHelp(hour: hour, parts: parts)
                      })
                .frame(height: labelHeight + 2 + tokenArea, alignment: .bottom)
            // token 那层的底线：柱子得站在一条线上，不然像浮着
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.top, 3)

            // 子智能体不占柱子、也不再单独一行（hero 那行已经写着「子智能体 0.35 亿 5%」）：
            // 它跟主线程同一件事，只是换了个跑的地方；钱不分主次，图上也不分。

            // 最后一排：检索次数。跟上面几层同一个横轴，自己一套尺子（每小时最多次数）。
            // 抬头只有名字；数字只在有调用的那几根上标，24 个 0 摆出来全是噪音。
            if hasToolCalls {
                // 检索那层的总数（次数 + 钱）原先只在面板底部那行出现，挪到 header：
                // 一个数只在面板上出现一次。
                layerHeader(T.toolCalls.s,
                            "\(L.toolCallCount(day.toolCalls)) · \(Fmt.money(day.toolCost))",
                            note: day.ccWebCalls > 0 ? L.ccWebCalls(day.ccWebCalls) : nil)
                .padding(.top, 5)
                .help(T.toolCallsHelp.s)

                bars(toolCalls, ghost: shadow.map { $0.hourToolCalls.map(Double.init) }, scale: toolScale,
                     area: toolArea, slot: slot, gap: gap, nowHour: nowHour,
                     offPeak: Style.search, peak: Style.search, floor: 1,
                     label: { _, value in countLabel(value) })
                    .frame(height: labelHeight + 2 + toolArea, alignment: .bottom)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.top, 3)
            }

            // 三层共用这一行：每根柱子下面标出是哪一小时
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

    /// 次数那一排的标签：在 14pt 宽的列里只放得下三位数，四位就不标（写了也是 1.1k 或 10…，反而是噪音）。
    /// 每天的总次数在该层 header 右边；柱子上只要看得出哪个小时多。
    private func countLabel(_ value: Double) -> String? {
        guard value > 0, value < 1000 else { return nil }
        return String(Int(value))
    }

    /// 块 header，所有块同一套：左边这层是什么（11 medium secondary，Style.sectionTitle），
    /// 右边这层的总数（11 medium + 等宽数字，Style.sectionTotal；单位写进总数里，不再单独摆一格）。
    /// 「一个条目只在一个地方出现它的总数」就是靠这个 header 承接的。
    /// 两边都不缩字号：放不下就缩短文案，不许 minimumScaleFactor 把标题缩得天天不一样大。
    private func layerHeader(_ name: String, _ total: String?, note: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(Style.sectionTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let total {
                Text(total)
                    .font(Style.sectionTotal)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // 次要色的小尾巴：「＋ CC N 次」这种单列口径的对照，别抢主数的视线。
            if let note {
                Text(note)
                    .font(Style.sectionTotal)
                    .foregroundStyle(Style.gray(colorScheme == .dark, faint: true))
                    .lineLimit(1)
                    .padding(.leading, 2)
            }
        }
    }

    /// 一层柱子：24 小时、每列宽一致、底对齐。钱和 token 两张只是值、尺子和配色不同。
    /// `ghost` 是前一天同一小时的值，画在今天这根背后拓一层淡的。
    /// `labeled` 是「只标最高几根」的开关（2026-11-07）：给哪几根下标就只给哪几根出 label，默认 nil = 全按 label 闭包走。
    /// `stagger` 是「右邻也标了就抬一层」的小时集合（照 PickerStrip 的 stagger，2026-11-07 子线程层在用）：
    /// `hover` 给每根柱子一句自己的悬停文案（子线程那层在用）；nil 就不挂 .help。
    private func bars(_ values: [Double], ghost: [Double]?, scale: Double, area: CGFloat, slot: CGFloat, gap: CGFloat,
                      nowHour: Int?, offPeak: Color, peak: Color, floor: CGFloat = 2,
                      labeled: Set<Int>? = nil, stagger: Set<Int>? = nil,
                      label: @escaping (Int, Double) -> String?,
                      hover: ((Int) -> String?)? = nil,
                      labelFontSize: CGFloat = 8.5,
                      labelMinScale: CGFloat = 0.75,
                      labelFixed: Bool = false) -> some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(values.enumerated()), id: \.offset) { hour, value in
                // 只有真的有量才画柱子（2026-11-07 他定的：「有柱子就得有数」）：
                // 原来 value = 0 也画一根 floor 高的淡虚线段，那一段恰好是「没数」的那种——
                // 看的人分不清是 0 还是不到 0.1。现在 0 就没有柱子，与上面的数字一一对应。
                let height = value > 0 ? max(floor, CGFloat(value / scale) * area) : 0
                let ghostValue = ghost?[hour] ?? 0
                let shown = labeled?.contains(hour) != false ? label(hour, value) : nil
                // 右邻也标了：这根的数字整行往上抬，两个数不叠（PickerStrip 同一手法）
                let lift: CGFloat = (shown != nil && stagger?.contains(hour + 1) == true) ? -Self.barLabelHeight : 0
                ZStack(alignment: .bottom) {
                    if ghostValue > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.primary.opacity(0.13))
                            // 影子统一最小 2pt（2026-11-08）：④ floor 1pt 的影子看不见，柱子本身仍按各层 floor。
                            .frame(height: max(2, CGFloat(ghostValue / scale) * area))
                    }
                    vstackBody(number: shown, color: tierColor(hour: hour, nowHour: nowHour,
                                                               hasValue: value > 0, offPeak: offPeak, peak: peak),
                               height: height, lift: lift, numberFontSize: labelFontSize,
                               numberMinScale: labelMinScale, numberFixed: labelFixed)
                }
                .frame(width: slot)
                .help(hover.map { $0(hour) ?? "" } ?? T.hourChart.s)
            }
        }
    }

    /// 把主线程和几条子线程的逐小时值加成一串（缺的小时按 0 算）：它就是柱高、柱顶那个数、hover 的来源。
    private static func stack(_ main: [Double], _ lanes: [[Double]]) -> [Double] {
        var out = main
        for lane in lanes {
            for (hour, value) in lane.enumerated() {
                if hour < out.count { out[hour] += value } else { out.append(value) }
            }
        }
        return out
    }

    /// token 那排柱子：底下主线程（青），上面叠子智能体（绿，2026-11-08 他定的：
    /// 「子智能体的 token 消耗量我要看到」）。柱高 = 那个小时一共多少 token，跟 `bars` 同一套画法，
    /// 只是柱子本身分两色：青是主线程、绿是子智能体，两种颜色各指一件事，深浅还是各自的闲时/高峰。
    private func tokenBars(main: [Double], caps: [[Double]], capColor: Color, ghost: [Double]?,
                           scale: Double, area: CGFloat, slot: CGFloat, gap: CGFloat, nowHour: Int?,
                           tier: @escaping (Int, Bool) -> Color,
                           label: @escaping (Int, Double) -> String?,
                           hover: @escaping (Int) -> String?) -> some View {
        let count = max(main.count, caps.map(\.count).max() ?? 0)
        return HStack(alignment: .bottom, spacing: gap) {
            ForEach(0..<count, id: \.self) { hour in
                let mainValue = hour < main.count ? main[hour] : 0
                let capValue = caps.reduce(0.0) { $0 + (hour < $1.count ? $1[hour] : 0) }
                let total = mainValue + capValue
                let ghostValue = (ghost?.count ?? 0) > hour ? (ghost?[hour] ?? 0) : 0
                ZStack(alignment: .bottom) {
                    if ghostValue > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.primary.opacity(0.13))
                            .frame(height: max(2, CGFloat(ghostValue / scale) * area))
                    }
                    VStack(spacing: 2) {
                        if total > 0, let number = label(hour, total) {
                            Text(number)
                                .font(.system(size: 8.5))
                                .monospacedDigit()
                                .foregroundStyle(Style.gray(colorScheme == .dark))
                                .fixedSize()
                        }
                        if total > 0 {
                            VStack(spacing: 0) {
                                if capValue > 0 {
                                    Rectangle()
                                        .fill(capColor)
                                        .frame(height: max(1, CGFloat(capValue / scale) * area))
                                }
                                Rectangle()
                                    .fill(tier(hour, mainValue > 0))
                                    .frame(height: mainValue > 0 ? max(0.5, CGFloat(mainValue / scale) * area) : 0)
                            }
                            .frame(height: max(1, CGFloat(total / scale) * area), alignment: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        }
                    }
                }
                .frame(width: slot)
                .help(hover(hour) ?? T.hourChart.s)
            }
        }
    }

    /// hero 两个抬头跟所看的那天走（2026-11-07）：今天 / 昨天用固定词，更早用短日期（复用 dayText）。
    private var heroSpendLabel: String {
        switch meter.selected {
        case 0: return T.todaySpend.s
        case 1: return T.yesterdaySpend.s
        default: return L.heroDatedSpend(Self.dayText(offset: meter.selected))
        }
    }

    private var heroTokensLabel: String {
        switch meter.selected {
        case 0: return T.todayTokens.s
        case 1: return T.yesterdayTokens.s
        default: return L.heroDatedTokens(Self.dayText(offset: meter.selected))
        }
    }

    /// 左上角那颗大数现在是「那天花了多少」；没登录、没数据时退回余额（免得那块空着）。
    private var heroIsSpend: Bool {
        !setupNeeded && !meter.needsLogin && dayLoaded
    }

    private var heroMoney: String {
        if heroIsSpend { return Fmt.money(day.money) }
        return meter.balance.amount.map(Fmt.money) ?? "—"
    }

    /// 那天一共过了多少 token（主线程 + 各子线程）。它是 hero 右边那个大数、各层 header 占比的分母。
    private var subTokens: Int {
        activeLanes.reduce(0) { $0 + (day.subagents[$1.id]?.tokens ?? 0) }
    }

    private var allTokens: Int { day.tokenTotal + subTokens }

    /// hero 右边的大数：裸数字 26pt，「亿 / B」这层单位 15pt、跟数字 baseline 对齐——
    /// 13pt 时英文的 B 像脚注，提到 15（2026-11-07）。
    private var tokenHeroNumber: some View {
        let (divisor, suffix) = L.tokenUnit(Double(allTokens))
        // 中文数字和单位之间空一格（「17.1 亿」），英文贴着（「1.7B」）——跟 L.tokenHead 的拼法一致。
        let gap: CGFloat = Lang.current == .zh ? 3 : 1
        return HStack(alignment: .firstTextBaseline, spacing: gap) {
            Text(L.trimDecimal(Double(allTokens) / divisor))
                .font(Style.hero)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 某一层 token 占「全部 token」的几成，写成「· 94%」直接拼在总数后面。
    private func headerShare(_ tokens: Int) -> String {
        allTokens > 0 ? String(format: " · %.0f%%", Double(tokens) / Double(allTokens) * 100) : ""
    }

    // MARK: - hero 括号（2026-11-07）：每个大数下面一行「由哪几块构成」。
    // 这是全屏唯一的「大数 → 构成」写法：下面闲时/高峰那两行因此只留档名，不再写第二遍金额。

    /// 括号那行不是标题，自成一套：固定 10pt（2026-11-07，中英一个号）；档名 tertiary、数字 secondary，
    /// 差一档分出「这是什么」和「多少」。两条括号跟右边那摞状态小字挤一行 420，
    /// 放不下就 minimumScaleFactor 等比缩，不许折行（折行把两个大数的基线挤歪）。
    /// 下限 0.95 → 0.82（2026-11-08）：钱那行多了「· 省 ¥X」后，有高峰的那天会排到
    /// 「闲时 ¥259.31 · 高峰 ¥103.44（2 倍价）· 省 ¥45.67」，0.95 缩不完就要截字。只在挤的时候缩，
    /// 平常那几天一个像素都不变。
    private var bracketFont: Font { .system(size: 10) }
    private var bracketScale: CGFloat { 0.82 }

    /// 括号里的一小节。档名（闲时/高峰/计费/子线程、分隔点）tertiary，数字 secondary。
    private func bracket(_ s: String, name: Bool) -> some View {
        Text(s)
            .font(bracketFont)
            .monospacedDigit()
            .foregroundStyle(name ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
    }

    /// 钱的括号 = 闲时 + 高峰（相加就是那个大数）；整天闲时那天只写「全天闲时」，不摆「高峰 ¥0」。
    /// 后面跟一句「省 ¥X」（2026-11-08 他定的）：子智能体那些调用若走 DeepSeek 付费 API 要花多少。
    /// 原先它跟在 token 那行括号的尾巴上，跟「子智能体 0.29 亿 4%」拼成一行、尾巴拖到两列之外；
    /// 挪到「今天花费」下面这块空里——花了多少、省了多少，摆在一起才是一句话。
    private var spendBracket: some View {
        let saved = DeepSeekQuote.saved(of: day)
        return HStack(spacing: 3) {
            if day.hasPeakHours {
                bracket(T.offPeak.s, name: true)
                bracket(Fmt.money(day.offPeak), name: false)
                bracket("·", name: true)
                bracket(T.peak.s, name: true)
                bracket(Fmt.money(day.peak), name: false)
                bracket(L.peakSuffix, name: true)
            } else {
                bracket(T.heroAllOffPeak.s, name: true)
            }
            if saved > 0 {
                bracket("·", name: true)
                // 跟旁边「闲时 ¥24.5」一个重量（secondary）：它是这行第三个数，不是旁注。
                Text(L.savedMoney(Fmt.money(saved)))
                    .font(bracketFont)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// token 括号用的量级：跟图里主线程/子线程两个 header 同一把（同一根比例条上的数，量级要一致）。
    private var heroTokenUnit: (divisor: Double, suffix: String) {
        L.tokenUnit(Double(max(day.tokenTotal,
                               activeLanes.map { day.subagents[$0.id]?.tokens ?? 0 }.max() ?? 0)))
    }

    /// 「16.1 亿」/「1.61B」：数字 + 单位，不带 token 那个词（括号行没有位置摆它）。
    private func tokenHead(_ tokens: Int, unit: (divisor: Double, suffix: String)) -> String {
        let number = L.trimDecimal(Double(tokens) / unit.divisor)
        guard !unit.suffix.isEmpty else { return number }
        return Lang.current == .zh ? "\(number) \(unit.suffix)" : "\(number)\(unit.suffix)"
    }

    /// 占比：分母跟下面两层 header 的 headerShare 同一个（allTokens），同一套四舍五入，94% / 6% 才对得上。
    private func bracketShare(_ tokens: Int) -> String {
        allTokens > 0 ? String(format: "%.0f%%", Double(tokens) / Double(allTokens) * 100) : ""
    }

    /// token 的括号 = 主智能体走的账单里，子智能体占了多少。
    /// （省多少不在这儿：2026-11-08 他定的，摆到「今天花费」那行去了。）
    private var tokenBracket: some View {
        // 只摆「子智能体占多少」（2026-11-08 他定的：原来写「其中免费 0.1 亿 3%」，那是把
        // 「没花钱」当标签；他要看的是子智能体在总 token 里占了多少）。数字本来就是各 lane 之和，
        // 只是标签跟着换；计费那半 = 总量 − 这个数，读的人自己减。
        let unit = heroTokenUnit
        return HStack(spacing: 4) {
            // 绿点 = 子智能体（跟 token 柱子顶上那段一个颜色，2026-11-08）。
            Circle()
                .fill(Style.subagent)
                .frame(width: 5, height: 5)
            bracket(T.subagent.s, name: true)
            bracket("\(tokenHead(subTokens, unit: unit)) \(bracketShare(subTokens))", name: false)
        }
        // 悬停才知道子智能体是什么、钱怎么算的（它不单独占柱子，也没自己的颜色了）。
        .help(activeLanes.first?.help ?? "")
    }

    /// 柱子上那个数字 + 柱子本身。`lift` 把数字整行往上抬（相邻两根都标时的 stagger）。
    private func vstackBody(number: String?, color: Color, height: CGFloat, lift: CGFloat = 0,
                            numberFontSize: CGFloat = 8.5, numberMinScale: CGFloat = 0.75,
                            numberFixed: Bool = false) -> some View {
        VStack(spacing: 2) {
            if let number {
                if numberFixed {
                    // token 两层：两位小数 4 个字在 14pt 列里放不下。不挂 lineLimit / 缩放，
                    // fixedSize 按理想宽画，容不下就往邻列缝里溢一点——截成 "0.…" 更难读。
                    Text(number)
                        .font(.system(size: numberFontSize))
                        .monospacedDigit()
                        .foregroundStyle(Style.gray(colorScheme == .dark))
                        .fixedSize()
                        .offset(y: lift)
                } else {
                    Text(number)
                        .font(.system(size: numberFontSize))
                        .monospacedDigit()
                        .foregroundStyle(Style.gray(colorScheme == .dark))
                        .lineLimit(1)
                        // 英文的单位是 M/B/K，柱子上可能冒出三位数（"160"），14pt 的列塞不下就等比缩一点，
                        // 别截成 "1…"——那种截法比没有数字还难读。
                        // 下限 0.75（2026-11-07）：检索层三位数（"136"）要缩到 ~0.78 才进得了 14pt 的列，
                        // 0.85 还是截成 "1…"；0.75 三位数 ~13pt 放得下，数字完整。0.6 那档删了——
                        // 主线程层当时截成 "11_" 的真正根因是 label 闭包忘了除单位（value * divisor / divisor），
                        // 不是缩放下限不够。
                        .minimumScaleFactor(numberMinScale)
                        .offset(y: lift)
                }
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
        let tier = PeakHours.isPeak(hour: hour, weekday: day.weekday, day: day.day) ? peak : offPeak
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
        // 闲时占比：钱全走闲时就是 100%（周末 / 节假日那种）。没钱（还没花 / 那天真没用量）就 nil，
        // 条和字都退成占位，不假装 100%。
        let offShare: Double? = total > 0 ? max(0, min(1, day.offPeak / total)) : nil
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                // 全天闲时那天（周末 / 节假日）不再塌成一行字：左边整块会空着，右边却有根条。
                // 现在两列长得一样（2026-11-07 他定的：「全天闲时也要有啊，但不能空着」）——
                // 一张全绿的条就是在说「一整天都是闲时」，百分比把它说成数。
                statLine(dot: Style.offPeak) {
                    // 金额挪进 hero 括号了（2026-11-07）：这里只留色点 + 档名 + 占比，同一屏不写第二遍数。
                    Text(offShare.map { "\(T.offPeak.s) \(Self.sharePercent($0))" }
                         ?? (dayLoaded ? T.offPeak.s : T.offPeakDash.s))
                        .font(Style.sectionTitle)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                proportionBar(leftShare: offShare ?? 1, left: Style.offPeak, right: Style.peak)
                    .opacity(offShare == nil ? 0.15 : 1)
                statLine(dot: Style.peak) {
                    Text(offShare.map { "\(L.peakName) \(Self.sharePercent(1 - $0))" }
                         ?? (dayLoaded ? (day.hasPeakHours ? L.peakName : T.peakAllOffPeak.s) : T.peakDash.s))
                        .font(Style.sectionTitle)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        // 半列宽塞不下就缩一点，别截成「高峰（2 倍…」
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 悬停里补一句：节假日表没更新到今年的年份（有就说明是按星期几估的）。
            .help(L.peakHelp() + (PeakHours.holidaysStaleYear.map { "\n" + L.holidayStale(year: $0) } ?? ""))

            VStack(alignment: .leading, spacing: 5) {
                statLine(dot: Style.hit) {
                    HStack(spacing: 4) {
                        Text(rate.map { "\(T.hit.s) \(Self.sharePercent($0))" } ?? T.hitDash.s)
                            .font(Style.sectionTitle)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if let delta = hitDelta {
                            // 括号比主体小一号：这是注解，不是第二个数。
                            Text(L.hitDelta(delta.text, relation: meter.selected == 0 ? T.vsYesterday.s : T.vsPreviousDay.s))
                                .font(.system(size: 10))
                                .foregroundStyle(deltaColor(delta.better))
                        }
                    }
                }
                .help(L.hitHelp())
                proportionBar(leftShare: rate ?? 1, left: Style.hit, right: Style.miss, minRight: 3)
                    .opacity(rate == nil ? 0.15 : 1)
                statLine(dot: Style.miss) {
                    Text(rate.map { "\(T.miss.s) \(Self.sharePercent(1 - $0))" } ?? T.missDash.s)
                        .font(Style.sectionTitle)
                        .monospacedDigit()
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

    // MARK: - 每亿 token 的单价

    /// 那天花了多少 ÷ 那天的 token 量。切日跟着变；后面括号里是前一天同一个数，
    /// 拿它当尺子——两个数一比就知道那天是高峰多、还是缓存没命中。
    /// 右边紧跟着同一把尺子上的另一格：每亿 token 摊到多少次请求（= 1 亿 ÷ 每次的 token 量），
    /// 也带前一天的对照。单价是「贵不贵」，次数是「碎不碎」——两个数一起看才知道钱是被单次变大推高的，
    /// 还是被次数推高的。
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
            if let count = day.requestsPer100M() {
                Text(L.tasksPer100M(count))
                    .font(Style.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let previous = meter.snap.previousRequestDensity(selected: meter.selected) {
                    Text(L.tasksPer100MReference(
                        Fmt.count(previous),
                        relation: meter.selected == 0 ? T.yesterday.s : T.previousDay.s
                    ))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .help(T.unitPriceHelp.s)
    }

    // MARK: - 页脚
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(runwayText).font(Style.body).foregroundStyle(.secondary)
                if let paceText {
                    Text(paceText)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
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
    /// 四舍五入到 0.0 就写「0.0%」、不带正负号：不显示会让人以为这行掉了，
    /// 也不能让 -0.04 显示成「-0.0%」。
    private var hitDelta: (text: String, better: Bool?)? {
        guard let pair = meter.snap.comparisonHitRates(selected: meter.selected) else { return nil }
        let points = (pair.current - pair.previous) * 100
        guard abs(points) >= 0.05 else { return ("0.0%", nil) }
        return (String(format: "%+.1f%%", points), points > 0)
    }

    /// 差值的颜色：涨蓝、跌黄（深浅按明暗走）；抹平到 0.0 用灰的——它不是涨也不是跌。
    private func deltaColor(_ better: Bool?) -> Color {
        guard let better else { return .secondary }
        return Style.delta(better: better, dark: colorScheme == .dark)
    }

    /// 缓存里任何一天有命中数据，这一行就占着位置（切日时不会抽上去一格）。
    private var hasHitData: Bool {
        meter.snap.days.values.contains { $0.hitRate != nil }
    }

    /// 检索折线的纵轴：三天窗口（今天、昨天、前天）里每小时最多的那次，
    /// 跟柱子图同一个思路——切日时线不跟着缩放。
    private var toolRuler: Int {
        var value = 1
        for offset in 0...2 {
            if let day = meter.snap.days[offset] {
                value = max(value, day.hourToolCalls.max() ?? 0)
            }
        }
        return max(value, day.hourToolCalls.max() ?? 0)
    }

    /// 缓存里任一天有检索调用，这行就占着位置（切日时不抽上去一格）。
    /// CC 自带联网的那几次也算：某天只有它查过、DeepSeek 一次没用（周末只跑 cc 就会这样），整层不能因此消失。
    private var hasToolCalls: Bool {
        meter.snap.days.values.contains { $0.toolCalls > 0 || $0.ccWebCalls > 0 }
    }

    /// 看的是哪一天，判断的就是哪一天：那天哪条来源有调用，那条的整排柱和整行才摆。
    /// （不做「缓存里任一天有就常驻」：往前翻没有数的日子会挂着一排空柱子，看着像坏了。
    /// 换天时高度变一下，比摆一排 0 好。）
    private var activeLanes: [SubagentLane] {
        SubagentLane.all.filter { (day.subagents[$0.id]?.calls ?? 0) > 0 }
    }

    /// 缓存里模型最多的那天决定摆几行，切日时这块高度不变。
    private var modelSlots: Int {
        min(3, meter.snap.days.values.map(\.models.count).max() ?? 0)
    }

    /// 占比：整数不带小数点（100% / 0% / 33%），其余一位（98.7%）。
    /// 两列（闲时、命中）同一套写法；全天闲时那种 100% 写成「100.0%」太啰嗦。
    private static func sharePercent(_ value: Double) -> String {
        let pct = value * 100
        return pct == pct.rounded() ? String(format: "%.0f%%", pct) : String(format: "%.1f%%", pct)
    }

    private func legendDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }

    /// 现在这一档：跟菜单栏那颗灯同一个颜色、同一句话。
    private var nowTone: some View {
        HStack(spacing: 8) {
            legendDot(toneColor)
            Text(PeakHours.now.label).font(Style.body).foregroundStyle(Style.gray(colorScheme == .dark))
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

    /// 「还能用多久」：余额 ÷ 现在的日均。日均由 Trend 从最近两周加权平均出来（见 Trend.swift），
    /// 不是 30 天除一下——日均会台阶式地变，除 30 天会把「刚开始跑 agent」之前那些轻日子也算进来。
    private var runwayText: String {
        guard let days = meter.runwayDays else { return T.runwayNoData.s }
        return L.runway(days)
    }

    /// 近一周那截小字（对照主数用）。差得不多就不摆，见 `Meter.weekPaceDays`。
    private var paceText: String? {
        meter.weekPaceDays.map { L.runwayAtPace($0) }
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
