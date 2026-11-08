import Foundation

enum Fmt {
    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func money(_ value: Double) -> String {
        let text = moneyFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "¥" + text
    }

    /// 一次请求多少钱：几分钱的东西，两位小数会变成 ¥0.01，看不出变化。
    /// 按量级给位：一元以上看两位，一角以上看三位，再小看四位。
    static func moneyFine(_ value: Double) -> String {
        let digits = value >= 1 ? 2 : (value >= 0.1 ? 3 : 4)
        return "¥" + String(format: "%.\(digits)f", value)
    }

    /// 柱子上的 token 数：一列才 14pt 宽，写不下「820万」这种带单位的数。
    /// 所以整张图共用一个单位（亿 / 万），单位写在图角上，柱子上只写裸数字。
    static func tokenUnit(_ top: Double) -> (divisor: Double, suffix: String) {
        L.tokenUnit(top)
    }

    /// 柱子上那个裸数字：≥10 取整，1 到 10 之间一位小数，小到看不见就给 nil（不标）。
    static func barNumber(_ value: Double, unit: Double) -> String? {
        let scaled = value / unit
        if scaled >= 10 { return String(format: "%.0f", scaled) }
        if scaled >= 0.1 { return String(format: "%.1f", scaled) }
        // 不到 0.1 就不写（2026-11-07 他定的，次日口径）：「有 0.1 就写 0.1，小于 0.1 就不写了」。
        // 也不再放「<」那个记号（前一天先加的，他看过之后说不要）。所以这一层的读法是一对一：
        // 有柱子没数字 = 那小时有量但不到 0.1；没柱子 = 那小时真的零。
        return nil
    }

    /// 柱子上的 token 数（token 两层专用，2026-11-08 口径）：**有柱子就有数，最多 3 个字**。
    /// ≥10 取整，≥0.1 一位小数（带前导 0），>0 且 <0.1 写成省掉前导 0 的两位小数（`.02`）——
    /// 4 个字符 8.5pt 在 14pt 列里会跟邻居连成 `0.020.03`，省前导 0 后一行 24 根各呆各的格。
    /// 0 仍返回 nil——没量就是没量，不画柱子不写数。
    /// 钱那层和其它地方继续用 barNumber 的旧口径（不到 0.1 不写），不要一起改。
    static func barNumberAll(_ value: Double, unit: Double) -> String? {
        let scaled = value / unit
        if scaled <= 0 { return nil }
        if scaled >= 10 { return String(format: "%.0f", scaled) }
        if scaled >= 0.1 { return String(format: "%.1f", scaled) }
        // 两位小数四舍五入后仍是 ".00"（不到 0.01 亿 = 100 万 token）就不写数（2026-11-08）：
        // 原来钳到 ".01" 起步，4 万 token 的一小时会写成 ".01"（100 万），是假数字。别撒谎。
        let text = String(format: "%.2f", scaled)
        return text == "0.00" ? nil : text.replacingOccurrences(of: "0.", with: ".")
    }

    /// 请求数这种整数：带千分位（9403 → "9,403"）。四五位数一眼要认出量级。
    static func count(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }
}
