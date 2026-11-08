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
/// 法定节假日靠下面那张假期表（每年国务院发布后手工补一年），节假日整天按闲时价。
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

    /// 中国法定节假日（国务院办公厅 国办发明电〔2025〕7号，2025-11-04 发布）：2026 年的放假区间，含调休连出来的天。
    /// 只列「放假」的日期；调休上班的周六（如 2026-02-14、2026-05-09）不进表——官方规则是
    /// 「周末及法定节假日全天为空闲时段」，调休上班的周六仍是周末，照闲时价算。
    /// 每年国务院 11 月前后发下一年的安排，到时候在这里补一年的区间、coveredYears 加上那一年。
    static let holidays: [(start: String, end: String)] = [
        ("2026-01-01", "2026-01-03"),
        ("2026-02-15", "2026-02-23"),
        ("2026-04-04", "2026-04-06"),
        ("2026-05-01", "2026-05-05"),
        ("2026-06-19", "2026-06-21"),
        ("2026-09-25", "2026-09-27"),
        ("2026-10-01", "2026-10-07"),
    ]
    /// 节假日表覆盖到的年份。年份不在里面就不猜：退回星期几规则，界面上提示表待更新。
    static let coveredYears: Set<Int> = [2026]

    /// 那个北京日（yyyy-MM-dd）是不是法定节假日。空串（没有日期可判的地方）→ false。
    /// 区间端点都是 yyyy-MM-dd，字符串直接比大小就是对 chronological 的比较。
    static func isHoliday(_ day: String) -> Bool {
        guard day.count == 10 else { return false }
        guard let year = Int(day.prefix(4)), coveredYears.contains(year) else { return false }
        return holidays.contains { day >= $0.start && day <= $0.end }
    }

    /// 当前北京年不在节假日表里 → 返回那一年（只进悬停说明，不另加界面文字）；表齐全 → nil。
    static var holidaysStaleYear: Int? {
        let year = beijing.component(.year, from: Date())
        return coveredYears.contains(year) ? nil : year
    }

    /// 北京日 yyyy-MM-dd。
    static func dayString(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    /// 没有日期可判的地方（demo、旧调用点）走这里：等价于 day 传空串，只按星期几判。
    static func isPeak(hour: Int, weekday: Int) -> Bool {
        guard (2...6).contains(weekday) else { return false } // 1 = 周日，7 = 周六
        return peakRanges.contains { $0.contains(hour) }
    }

    /// 有日期就走这里：节假日整天都是闲时，先判节假日再判星期几，逻辑只在这一个入口分叉。
    static func isPeak(hour: Int, weekday: Int, day: String) -> Bool {
        if isHoliday(day) { return false }
        return isPeak(hour: hour, weekday: weekday)
    }

    /// 有具体时刻就走这里（灯、`now`）：日期也传进去，节假日整天闲时。
    static func isPeak(_ date: Date) -> Bool {
        let calendar = beijing
        return isPeak(hour: calendar.component(.hour, from: date),
                      weekday: calendar.component(.weekday, from: date),
                      day: dayString(of: date))
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

    /// 那天这个小时算不算高峰（周末和法定节假日整天都不算）。
    static func isPeak(hour: Int, on day: Date) -> Bool {
        isPeak(hour: hour, weekday: weekday(of: day), day: dayString(of: day))
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
