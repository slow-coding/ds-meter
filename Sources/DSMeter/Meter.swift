import Foundation

/// 最准的模式：钱和明细都取 DeepSeek 平台自己的账单记录（按小时、按模型），
/// 余额取官方公开接口。平台数据本身有约 5 分钟延迟，但它是账单，不是推算。
///
/// 需要一串平台 Token（登录 platform.deepseek.com 后在 localStorage 里的 userToken）。
/// 不开源就没法让人验，所以源码公开；token 只存在本机一个 0600 的凭据文件，只发给 platform.deepseek.com。
final class Meter: ObservableObject {
    @Published private(set) var snap = Snapshot()
    @Published private(set) var balance = BalanceState()
    @Published private(set) var loading = false

    /// 面板上正在看的那天：0 = 今天，1 = 昨天…（heatmap 点哪格就是哪天）
    @Published private(set) var selected = 0

    /// 刷新间隔（秒）：默认 120（平台账单本身有约 5 分钟延迟，取再快也看不到更新的数；
    /// 2 分钟是把「我们这边再拖一截」压到最小、同时两分钟才两次请求）。
    /// 面板开着的时候另有 15 秒的节奏（只在面板开着的那几秒里跑），见 refreshOnOpen。
    @Published var interval: TimeInterval {
        didSet {
            UserDefaults.standard.set(interval, forKey: "refreshInterval")
            restart()
        }
    }

    var onChange: (() -> Void)?

    private var timer: Timer?
    private var recentFetchedAt: Date?
    /// 每天取到的时间，按天数偏移记（0 = 今天，1 = 昨天…）。
    private var dayFetchedAt: [Int: Date] = [:]
    /// 这些缓存是哪一天取的（今天 0 点）；过了零点全部作废。
    private var cacheStart: Date?
    /// 对平台接口的退让：连续失败就把间隔拉长（60s → 120 → 240 → 480 → 900 封顶），成功一次清零。
    /// 401（token 过期）/ 429（请求过多）/ 网络抖动都走这条，不一直敲人家。
    private var failureCount = 0
    private var nextUsageAttempt: Date?
    /// 上一次真的发出去的时间：不管哪个入口（面板 15 秒、后台 2 分钟）都不会比 5 秒更密。
    private var lastUsageRequest: Date?

    init() {
        let stored = UserDefaults.standard.object(forKey: "refreshInterval") as? Double ?? 0
        interval = stored > 0 ? stored : 120
    }

    func start() {
        refresh()
        restart()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        refresh()
        restart()
    }

    /// 自检 / 截图用：强制「已登录」（true）或「没登录」（false），不读本机凭据。
    var forcedSignedIn: Bool?

    /// 面板要不要摆登录入口：没绑登录态，或者刚被判为过期。
    var needsLogin: Bool {
        if let forcedSignedIn { return !forcedSignedIn }
        return snap.tokenProblem || Account.consoleToken == nil
    }

    /// 截图用：把面板切成「没登录」那块。
    func showLoggedOut() { forcedSignedIn = false }

    func reloadAccount() {
        failureCount = 0
        nextUsageAttempt = nil
        recentFetchedAt = nil
        dayFetchedAt = [:]
        cacheStart = nil
        snap.error = nil
        snap.tokenProblem = false
        refresh()
    }

    private func restart() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        refreshBalance()
        refreshUsage()
    }

    /// 面板刚打开：余额永远重取（实时接口，几百字节）；
    /// 账单只在手上这份超过 15 秒时才重取——平台那份账单本身有约 5 分钟延迟，多取只是白耗电。
    func refreshOnOpen() {
        refreshBalance()
        if let updated = snap.updatedAt, Date().timeIntervalSince(updated) < 15 { return }
        refreshUsage()
    }

    // MARK: - 余额（官方公开接口，实时）

    func refreshBalance() {
        BalanceClient.fetch { [weak self] state in
            guard let self else { return }
            if state.amount == nil, self.balance.amount != nil {
                self.balance.error = state.error
            } else {
                self.balance = state
            }
            self.onChange?()
        }
    }

    // MARK: - 用量（平台账单记录）

    func refreshUsage() {
        guard !loading else { return }
        let now = Date()
        if let next = nextUsageAttempt, now < next { return }
        if let last = lastUsageRequest, now.timeIntervalSince(last) < 5 { return }
        lastUsageRequest = now
        loading = true
        PlatformClient.fetchDay(offset: 0) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.fail(error)
            case .success(let bill):
                self.apply(bill: bill)
                self.refreshRecentIfNeeded()
                self.loadSelected()
            }
        }
    }

    /// 面板上换一天：先占位，再拉那天的账（拉过的留着）。
    func selectDay(_ offset: Int) {
        guard offset >= 0 else { return }
        selected = offset
        loadSelected()
    }

    /// 自检 / 截图用：demo 数据已经在手上，切日不发请求。
    func selectDemoDay(_ offset: Int) {
        selected = offset
    }

    private func apply(bill: PlatformClient.DayBill) {
        rolloverIfNeeded()
        var next = snap
        next.days[0] = DayCost(bill: bill, weekday: PeakHours.weekday(of: Date()))
        next.ratePerHour = Self.recentRate(hours: next.days[0]?.hours ?? [])
        next.moneyComplete = true
        next.updatedAt = Date()
        next.error = nil
        next.tokenProblem = false
        loading = false
        failureCount = 0
        nextUsageAttempt = nil
        snap = next
        onChange?()
    }

    /// 刚过零点：所有按偏移缓存的账都对不上了，全清掉重取。
    private func rolloverIfNeeded() {
        let today = PeakHours.startOfDay()
        guard cacheStart != today else { return }
        cacheStart = today
        snap.days = [:]
        snap.daily = []
        snap.avgDaily = nil
        snap.totalRecent = nil
        dayFetchedAt = [:]
        recentFetchedAt = nil
    }

    private func fail(_ error: PlatformError) {
        loading = false
        failureCount += 1
        let delay = min(900, 60 * pow(2, Double(failureCount - 1)))
        nextUsageAttempt = Date().addingTimeInterval(delay)
        snap.error = error.needsToken ? T.noTokenHint.s : T.usageUnavailable.s
        snap.tokenProblem = error.needsToken
        onChange?()
    }

    /// 当前这天 + 前一天（「未命中」那行要跟它比）。已经有的不重取。
    /// 再多取一天：纵轴的尺子是「今天 + 前两天」，尺子要跟所看那天无关，前面那天得先在手上。
    private func loadSelected() {
        ensureDay(selected)
        ensureDay(selected + 1)
        ensureDay(selected + 2)
    }

    /// 近 30 天每天多少（heatmap）+ 完整的天平均每天。十分钟取一次就够。
    private func refreshRecentIfNeeded() {
        if let fetched = recentFetchedAt, Date().timeIntervalSince(fetched) < 600, !snap.daily.isEmpty { return }
        recentFetchedAt = Date()
        PlatformClient.fetchRecent { [weak self] result in
            guard let self, case .success(let recent) = result else { return }
            self.snap.daily = recent.daily
            self.snap.totalRecent = recent.total
            self.snap.avgDaily = recent.average
            self.snap.avgDays = PlatformClient.averageWindowDays
            self.onChange?()
        }
    }

    /// 某一天（今天除外，今天由 refreshUsage 负责）：一小时取一次，历史的天不会变。
    private func ensureDay(_ offset: Int) {
        guard offset > 0 else { return }
        guard offset <= 180 else { return }
        if let at = dayFetchedAt[offset], Date().timeIntervalSince(at) < 3600, snap.days[offset] != nil { return }
        dayFetchedAt[offset] = Date()
        PlatformClient.fetchDay(offset: offset) { [weak self] result in
            guard let self, case .success(let bill) = result else { return }
            let weekday = PeakHours.weekday(of: PeakHours.daysBefore(offset))
            self.snap.days[offset] = DayCost(bill: bill, weekday: weekday)
            self.onChange?()
        }
    }

    /// 近 3 个整小时的平均；今天还没跑满就先空着。
    private static func recentRate(hours: [Double]) -> Double? {
        let nowHour = PeakHours.hour(of: Date())
        guard nowHour >= 3 else { return nil }
        let sum = (nowHour - 3..<nowHour).reduce(0.0) { $0 + hours[$1] }
        return sum > 0 ? sum / 3 : nil
    }

    // MARK: - 自检用（阻塞版）

    func loadSynchronously() {
        if let key = Account.apiKey, !key.isEmpty {
            pump { done in
                BalanceClient.fetch { state in
                    self.balance = state
                    done()
                }
            }
        }
        var today: PlatformClient.DayBill?
        var failure: PlatformError?
        pump { done in
            PlatformClient.fetchDay(offset: 0) { result in
                switch result {
                case .success(let value): today = value
                case .failure(let error): failure = error
                }
                done()
            }
        }
        if let today {
            apply(bill: today)
        } else if let failure {
            snap.error = failure.errorDescription
            snap.tokenProblem = failure.needsToken
        }
        pump { done in
            PlatformClient.fetchRecent { result in
                if case .success(let recent) = result {
                    self.snap.daily = recent.daily
                    self.snap.totalRecent = recent.total
                    self.snap.avgDaily = recent.average
                    self.snap.avgDays = PlatformClient.averageWindowDays
                }
                done()
            }
        }
        // 前一天（「未命中」那行要跟它比）+ 默认选中的那天
        for offset in Set([1, selected, selected + 1]) where offset > 0 {
            pump { done in
                PlatformClient.fetchDay(offset: offset) { result in
                    if case .success(let bill) = result {
                        let weekday = PeakHours.weekday(of: PeakHours.daysBefore(offset))
                        self.snap.days[offset] = DayCost(bill: bill, weekday: weekday)
                    }
                    done()
                }
            }
        }
    }

    /// 自检用：同步切到某一天（把那天和前一天拉下来）。
    func selectDaySynchronously(_ offset: Int) {
        selected = offset
        for target in Set([offset, offset + 1]) where target > 0 {
            pump { done in
                PlatformClient.fetchDay(offset: target) { result in
                    if case .success(let bill) = result {
                        let weekday = PeakHours.weekday(of: PeakHours.daysBefore(target))
                        self.snap.days[target] = DayCost(bill: bill, weekday: weekday)
                    }
                    done()
                }
            }
        }
    }

    // MARK: - 截图用假数据

    /// 灌一组固定的假数据：不发请求、不读凭据。README 截图和界面自检走这条路，
    /// 这样公开出去的图里没有本人的余额和用量。
    func loadDemo() {
        // 一天的花费形状：上午爬坡、午休掉一档、下午又一个峰（高峰时段价格双倍，所以柱子更高）
        let shape: [Double] = [
            0, 0, 0, 0, 0, 0, 0, 0.30, 1.60, 9.80, 11.40, 7.20,
            3.10, 4.60, 10.20, 13.60, 12.90, 8.40, 3.30, 2.10, 6.40, 9.20, 4.10, 1.20,
        ]
        var seed: UInt64 = 20_261_027
        func jitter(_ spread: Double) -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double(seed >> 11) / Double(UInt64(1) << 53)
            return 1 + (unit - 0.5) * 2 * spread
        }

        func bill(scale: Double) -> PlatformClient.DayBill {
            var bill = PlatformClient.DayBill()
            for hour in 0..<24 {
                let cost = (shape[hour] * scale * jitter(0.12) * 100).rounded() / 100
                bill.hours[hour] = cost
                bill.hourTokens[hour] = (cost * 12_500_000 * jitter(0.2)).rounded()
            }
            let total = bill.hours.reduce(0, +)
            let flash = (total * 0.96 * 100).rounded() / 100
            let pro = ((total - flash) * 100).rounded() / 100
            bill.modelCost = ["deepseek-flash": flash, "deepseek-v4-pro": pro]
            let tokens = total * 13_000_000
            bill.tokens = [
                "deepseek-flash": .init(
                    requests: Int(total * 330),
                    miss: Int(tokens * 0.96 * 0.03),
                    hit: Int(tokens * 0.96 * 0.97),
                    response: Int(tokens * 0.96 * 0.12)
                ),
                "deepseek-v4-pro": .init(
                    requests: Int(total * 9),
                    miss: Int(tokens * 0.04 * 0.08),
                    hit: Int(tokens * 0.04 * 0.92),
                    response: Int(tokens * 0.04 * 0.15)
                ),
            ]
            return bill
        }

        rolloverIfNeeded()
        var next = Snapshot()
        next.days[0] = DayCost(bill: bill(scale: 1), weekday: PeakHours.weekday(of: Date()))
        let scales: [Double] = [0.62, 0.88, 0.45, 1.05, 0.71, 0.93, 0.58]
        for (index, scale) in scales.enumerated() {
            let offset = index + 1
            next.days[offset] = DayCost(
                bill: bill(scale: scale),
                weekday: PeakHours.weekday(of: PeakHours.daysBefore(offset))
            )
        }

        // 日历：31 个数，老的在前面，最后一个 = 今天（跟 fetchRecent 的形状一致）
        // 形状刻意不均匀：有零花钱的周末、有几天忙到翻倍，热力格才看得出深浅
        let pattern: [Double] = [
            18, 42, 66, 25, 0, 30, 51, 87, 0, 39, 74, 22, 0, 58, 93, 36,
            0, 27, 61, 88, 0, 45, 70, 19, 0, 33, 57, 96, 12, 0, 40,
        ]
        var daily = pattern.map { ($0 * jitter(0.15) * 100).rounded() / 100 }
        for offset in 1...7 {
            daily[PlatformClient.calendarDays - offset] = next.days[offset]?.money ?? 0
        }
        daily[PlatformClient.calendarDays] = next.days[0]?.money ?? 0
        next.daily = daily
        next.totalRecent = daily.dropFirst().reduce(0, +)
        next.avgDaily = daily.dropLast().reduce(0, +) / Double(PlatformClient.calendarDays)
        next.avgDays = PlatformClient.averageWindowDays
        next.ratePerHour = Self.recentRate(hours: next.days[0]?.hours ?? [])
        next.moneyComplete = true
        next.updatedAt = Date()
        snap = next
        balance = BalanceState(amount: 486.20, fetchedAt: Date(), error: nil)
        forcedSignedIn = true
    }

    private func pump(_ start: (@escaping () -> Void) -> Void) {
        let semaphore = DispatchSemaphore(value: 0)
        start { semaphore.signal() }
        let deadline = Date().addingTimeInterval(20)
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}

/// 一天的账：每小时的金额、分模型的金额与 token 量、缓存命不命中，加上那天是周几。
/// 闲时 / 高峰怎么分、多付多少都由它算。
struct DayCost {
    struct Model: Identifiable {
        var id: String { name }
        let name: String
        let tokens: Int
        let requests: Int
        let cost: Double
    }

    var hours: [Double] = Array(repeating: 0, count: 24)
    /// 每小时的 token 量（命中 + 未命中 + 输出，跨模型）
    var hourTokens: [Double] = Array(repeating: 0, count: 24)
    /// 那天是周几：1 = 周日 … 7 = 周六。
    var weekday = 0
    var models: [Model] = []
    var requests = 0
    var miss = 0
    var hit = 0
    var output = 0

    init() {}

    /// 从平台那份账单装起来：金额按小时分、按模型分，token 量按模型分。
    init(bill: PlatformClient.DayBill, weekday: Int) {
        self.hours = bill.hours
        self.hourTokens = bill.hourTokens
        self.weekday = weekday
        var list: [Model] = []
        for (name, totals) in bill.tokens {
            requests += totals.requests
            miss += totals.miss
            hit += totals.hit
            output += totals.response
            let money = bill.modelCost[name] ?? 0
            guard totals.requests > 0 || money > 0 else { continue }
            list.append(Model(name: name, tokens: totals.miss + totals.hit + totals.response, requests: totals.requests, cost: money))
        }
        models = list.sorted { $0.cost > $1.cost }
    }

    var money: Double { hours.reduce(0, +) }

    /// 那天一共过了多少 token（命中 + 未命中 + 输出）。
    var tokenTotal: Int { hit + miss + output }

    /// 那天有没有高峰时段（周末全天都是闲时价）。
    var hasPeakHours: Bool { (2...6).contains(weekday) }

    /// 落在高峰那几小时的钱（已经按双倍价记的）。
    var peak: Double {
        (0..<24).reduce(0.0) { sum, hour in
            PeakHours.isPeak(hour: hour, weekday: weekday) ? sum + hours[hour] : sum
        }
    }

    var offPeak: Double { max(0, money - peak) }

    /// 高峰单价是闲时的 peakMultiplier 倍，所以高峰那部分里多付的是「一减除以倍数」那一块。
    var premium: Double { peak - peak / PeakHours.peakMultiplier }

    var hitRate: Double? {
        let total = hit + miss
        return total > 0 ? Double(hit) / Double(total) : nil
    }
}

struct Snapshot {
    /// 按天数偏移缓存：0 = 今天，1 = 昨天…（切日时已经取过的直接用）
    var days: [Int: DayCost] = [:]
    /// 近 30 天每天花了多少，老的在前面，最后一个就是今天（heatmap 用）。
    var daily: [Double] = []
    var moneyComplete = true
    var moneySince: Date?
    var ratePerHour: Double?
    /// 最近 30 天一共花了多少（跟日历上那 30 格对得上）。
    var totalRecent: Double?
    var avgDaily: Double?
    var avgDays = 0

    var updatedAt: Date?
    var error: String?
    /// 这次失败是「没绑 / 过期」——面板据此摆登录入口。
    var tokenProblem = false

    var today: DayCost { days[0] ?? DayCost() }
    var hasData: Bool { updatedAt != nil }

    var moneyToday: Double { today.money }
    var primaryToday: Double { moneyToday }
    var peakCost: Double { today.peak }
    var offPeakCost: Double { today.offPeak }
    var peakPremium: Double { today.premium }
}
