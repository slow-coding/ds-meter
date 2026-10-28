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
        return nil
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
