import Foundation

/// 「还能撑几天」里的「现在每天花多少」。
///
/// 三条不用：30 天平均（台阶式变化跟不上，还压在两个月前的轻日子上）、
/// 只拿最近三天平均（一天 spike 就顶掉三分之一）、两点一线的最小二乘（见下）。
///
/// 2026-11-06 踩的两个坑：
///
/// 一是把最近两周拟一条直线、取这条线在最后一天的值。实测余额 ¥2537、此前两周每天花四十到两百八，
/// 它报「日均 ¥18.36」——比窗口里几乎每一天都低，于是面板写「还能撑 138 天」。
/// 原因是末端值不可靠：14 个点时它的方差是均值的 3.6 倍（标准差 1.9 倍），
/// 窗口头几天高、中间掉下去，直线就被压到底，取末端等于取了个「趋势外推」，不是「现在的日均」。
///
/// 二是分层阶梯：最近 3 天按全权重、4–7 天减半、8–14 天打两折。同一份数据它给出 29.6 天，
/// 比半衰期 1.5 天的 23 天还长——最近三天便宜就按全权重，贵的十天被打了两折，越往回埋得越深；
/// 而且明天真涨上去，也要等三天才轮到它开始衰减。阶梯不是「反应快」，是「埋掉旧账」。
///
/// 现在只用加权平均：每往前一天权重减半（半衰期 1.5 天），最近一周占 96% 的权重，两周只是兜底。
/// 今天只过了多久就只算多少——花掉的钱按已过时长折成整日的强度，权重就是那段时长。
/// 结果就是「最近这些天，一天实打实花多少」，没有外推，也不怕单日 spike（昨天只占 0.63 的权重）。
///
/// 「用得猛」这种当天就变了的情况，平均值天生追不上（越快就是权重越集中到今天，代价是一小时的 spike
/// 也能翻倍）。副行那个对照交给另一条：`weekBurn`（近 7 个完整日平均），它慢、但 spike 进不来；
/// 两个数差四分之一以上才摆，差得不多时只留一个数。
enum Trend {
    /// 回看窗口：两周。再长也进不来（半衰期 1.5 天下，第 8 天只剩 2.5%、第 14 天 0.16%）。
    /// 留着只是不让窗口边缘断崖。
    static let window = 14

    /// 权重半衰期（天）：一天的权重每往前一天减半一次。1.5 天意味着「最近三天为主、这一周为辅」。
    static let halfLife = 1.5

    /// daily：每天花了多少，老的在前面，最后一个是今天。
    /// elapsed：今天过了多少（0…24 小时）。今天只算观察到的那一段，不往后外推。
    /// 数据不够或算不出正数时返回 nil，宁可不摆数字也不摆一个假数。
    static func burnRate(daily: [Double], elapsed: Double) -> Double? {
        let complete = daily.dropLast()
        guard complete.count >= 3 else { return nil }

        let values = Array(complete.suffix(window))
        var weighted = 0.0
        var weight = 0.0
        for (index, value) in values.enumerated().reversed() {
            // 昨天算第 1 天、前天第 2 天……越老权重越小
            let daysAgo = Double(values.count - index)
            let w = pow(0.5, daysAgo / halfLife)
            weighted += value * w
            weight += w
        }

        // 今天：已经过掉的那一段就是「一天里的这么多」。花掉多少算多少，权重是这一段的占比。
        // 所以它等价于 today 除以 (elapsed/24) 的强度，但不用把半天的数乘成整天的数再乘回去。
        let fraction = min(max(elapsed / 24, 0), 1)
        if fraction > 0 {
            weighted += daily.last ?? 0
            weight += fraction
        }

        guard weight > 0 else { return nil }
        let now = weighted / weight
        return now > 0.5 ? now : nil
    }

    /// 今天过了多少小时才敢折算。一小时花掉的钱乘 24 倍没有意义，spike 会被放大成十倍。
    static let paceMinHours = 4.0

    /// 今天这个速度：今天已经花掉的，按已经过掉的时长折成一整天。
    /// 现在是「近一周」那条对照的兜底：今天才过两小时就用它，噪声太大。
    static func todayPace(daily: [Double], elapsed: Double) -> Double? {
        guard elapsed >= paceMinHours, let today = daily.last, today > 0.5 else { return nil }
        let pace = today / (elapsed / 24)
        return pace > 0.5 ? pace : nil
    }

    /// 近一周每天实打实花多少：最后 7 个完整日（不算今天，今天只过了半天）。
    ///
    /// 为什么另拿一个数做对照（2026-11-07 回测，见 overview 里的表）：
    /// 它比半衰期加权慢，但 spike 进不了它；两个数一看就知道「最近是在花猛了还是收住了」。
    /// 回测里它比加权差（MAE ¥59 对 57.5），所以只当副行、不当主数。
    static func weekBurn(daily: [Double]) -> Double? {
        let complete = daily.dropLast()
        guard complete.count >= 7 else { return nil }
        let values = Array(complete.suffix(7))
        let mean = values.reduce(0, +) / Double(values.count)
        return mean > 0.5 ? mean : nil
    }

    /// 余额按现在这个日均还能撑几天。给不出一整天就按一天算（0.4 天这种数没意义）。
    static func runwayDays(balance: Double, burnRate: Double?) -> Int? {
        guard let burnRate, burnRate > 0, balance > 0 else { return nil }
        return Int(max(balance / burnRate, 0.4).rounded())
    }
}
