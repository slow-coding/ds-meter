import Foundation

/// DeepSeek 的分时价（元 / 百万 tokens），出处：
/// https://api-docs.deepseek.com/zh-cn/quick_start/pricing（2026-10-26 取线上 HTML）
///
///             flash 空闲   flash 高峰   v4-pro 空闲   v4-pro 高峰
/// 输入·命中      0.02        0.04        0.15          0.30
/// 输入·未命中    1           2           4.5           9
/// 输出           4           8           13.5          27
///
/// 高峰 = 北京时间周一至周五（不含法定节假日）9:00–12:00、14:00–18:00；
/// 其余时段、周末、法定节假日全天都是空闲，空闲价 = 高峰价的一半。
/// 法定节假日认不出来（要靠一张假期表），工作日撞上假期时灯会显示高峰。
enum PeakHours {
    /// 规则和价格的出处。页面会改（分时区间、单价都可能变），所以链接和「上次看的日子」要显示在界面上。
    static let sourceURL = URL(string: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing")!
    static let verifiedOn = "2026-10-26"
    /// 超过这么多天没再看，界面上就把价格那行标黄。
    static let staleAfterDays = 30

    static let timeZone = TimeZone(secondsFromGMT: 28_800) ?? .current

    static let peakRanges = [9..<12, 14..<18]

    /// 高峰单价是闲时的几倍。现在三个档位都是整 2 倍（flash 命中 0.02→0.04、未命中 1→2、输出 4→8；
    /// v4-pro 0.15→0.30、4.5→9、13.5→27）。价格页若改成不是 2 倍，改这里一处就行。
    static let peakMultiplier: Double = 2

    /// 界面上那个系数，比如 "2 倍"（不整就写一位小数）。不写 "×2"：它紧贴在金额后面会被读成乘法。
    static var multiplierLabel: String { L.multiplier(peakMultiplier) }

    static func isPeak(hour: Int, weekday: Int) -> Bool {
        guard (2...6).contains(weekday) else { return false } // 1 = 周日，7 = 周六
        return peakRanges.contains { $0.contains(hour) }
    }

    static func isPeak(_ date: Date) -> Bool {
        let calendar = beijing
        return isPeak(hour: calendar.component(.hour, from: date), weekday: calendar.component(.weekday, from: date))
    }

    static func hour(of date: Date) -> Int {
        beijing.component(.hour, from: date)
    }

    /// 那天（北京时区）是周几：1 = 周日 … 7 = 周六。
    static func weekday(of date: Date) -> Int {
        beijing.component(.weekday, from: date)
    }

    /// 那天是几号（北京时区），日历格子用。
    static func beijingDay(of date: Date) -> Int {
        beijing.component(.day, from: date)
    }

    /// 那天往前数 n 天（按北京日历减，不靠 86400）。
    static func daysBefore(_ n: Int, from date: Date = Date()) -> Date {
        beijing.date(byAdding: .day, value: -n, to: date) ?? date.addingTimeInterval(TimeInterval(-n * 86_400))
    }

    /// 北京时间的今天 0 点。拿它当缓存键，过了零点不会还摆着昨天的账。
    static func startOfDay(_ date: Date = Date()) -> Date {
        beijing.startOfDay(for: date)
    }

    /// 那天这个小时算不算高峰（周末整天都不算）。
    static func isPeak(hour: Int, on day: Date) -> Bool {
        isPeak(hour: hour, weekday: weekday(of: day))
    }

    /// 当前时间在一天里的位置，比如 14:30 → 14.5。算「每小时花多少」时用来折算还没跑完的那小时。
    static func hourFraction(of date: Date) -> Double {
        let hour = beijing.component(.hour, from: date)
        let minute = beijing.component(.minute, from: date)
        return Double(hour) + Double(minute) / 60
    }

    static func isWeekend(_ date: Date) -> Bool {
        let weekday = self.weekday(of: date)
        return weekday == 1 || weekday == 7
    }

    /// 今天这个小时算不算高峰（周末整天都不算）。
    static func isPeakToday(hour: Int) -> Bool {
        isPeak(hour: hour, on: Date())
    }

    /// 现在这一档：灯的颜色 + 一句话 + flash 的单价。
    static var now: (tone: Tone, label: String, input: Double, output: Double) {
        if isPeak(Date()) {
            return (.peak, T.nowPeak.s, 2, 8)
        }
        return (.offPeak, T.nowOffPeak.s, 1, 4)
    }

    enum Tone { case peak, offPeak }

    /// 距上次看定价页过了多少天。
    static var daysSinceVerified: Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        guard let date = formatter.date(from: verifiedOn) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return max(0, days)
    }

    static var isPriceStale: Bool {
        guard let days = daysSinceVerified else { return true }
        return days > staleAfterDays
    }

    private static var beijing: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
