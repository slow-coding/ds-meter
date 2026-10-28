import Foundation

/// 「还能撑几天」里的「现在每天花多少」。
///
/// 不用 30 天平均：日均是台阶式变化的（开始跑 agent 那天从几十跳到两百多），
/// 30 天平均还压在 86 上，算出来「还能撑 36 天」，比实际长一倍多。
/// 也不直接用最近三天平均：一天 spike 就把数推歪。
/// 所以把最近两周每天花了多少拟一条直线，取这条线在最后一天的值——趋势进来了，单日噪声被压掉。
///
/// 只做「拟合出现在的日均」，不往后外推增长：日花费的斜率在两周窗口里噪声很大，
/// 拿它累加到余额归零，多推一天就多一层误差。外推的那部分收益（差两天）不抵它带来的不确定。
enum Trend {
    /// 拟合窗口：两周。再短被单日 spike 带跑，再长跟不上「开始用 agent」这种台阶。
    static let window = 14

    /// daily：每天花了多少，老的在前面，最后一个是今天（今天没过完，不参与拟合）。
    /// 返回「现在每天花多少」；数据不够或拟合不出正数时返回 nil，宁可不摆数字也不摆一个假数。
    static func burnRate(daily: [Double]) -> Double? {
        let complete = daily.dropLast()
        guard complete.count >= 3 else { return nil }

        let values = Array(complete.suffix(window))
        let n = values.count
        let mean = values.reduce(0, +) / Double(n)
        guard mean > 0.5 else { return nil }

        // 最小二乘：d(i) = mean + slope · (i - meanX)
        let meanX = Double(n - 1) / 2
        var sxx = 0.0
        var sxy = 0.0
        for (index, value) in values.enumerated() {
            let x = Double(index) - meanX
            sxx += x * x
            sxy += x * (value - mean)
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        // 这条线在最后一个完整天（就是昨天）上的值 = 现在的日均。不外推到今天那一格。
        let fitted = mean + slope * (Double(n - 1) - meanX)

        // 拟合值掉到 0 以下说明这条线在往下穿零：那是「没在花了」，不是一个可用的日均。
        // 退回窗口平均，别把负数当天数算，也别报无穷。
        return fitted > 0.5 ? fitted : mean
    }

    /// 余额按现在这个日均还能撑几天。给不出一整天就按一天算（0.4 天这种数没意义）。
    static func runwayDays(balance: Double, burnRate: Double?) -> Int? {
        guard let burnRate, burnRate > 0, balance > 0 else { return nil }
        return Int(max(balance / burnRate, 0.4).rounded())
    }
}
