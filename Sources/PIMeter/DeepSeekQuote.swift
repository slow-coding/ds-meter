import Foundation

/// 「这些调用若走 DeepSeek flash 付费 API 要花多少钱」——免费子线程那行的「省 ¥」。
/// 单价不另立表，从 PeakHours 取（命中 0.02、未命中 1、输出 4 元/百万 token，高峰乘 peakMultiplier）。
/// 闲时/高峰按每条记录发生的**小时**判（PeakHours.isPeak(hour:weekday:day:)），不拿整天平均价；
/// 有北京日（DayCost.day）就先判法定节假日——节假日整天都是闲时价。
/// 不含检索费；命中 / 未命中 / 输出都用日志里实测的那份，不做命中率假设。
enum DeepSeekQuote {
    /// 一份子线程日志按 flash 价折成钱（元）。weekday 从 DayCost.weekday 传进来（1 = 周日 … 7 = 周六），
    /// day 是北京日 yyyy-MM-dd（判节假日，没有就传空串只按星期几判）。
    static func cost(of day: SubagentLog.Day, weekday: Int, beijingDay: String) -> Double {
        let million = 1_000_000.0
        var total = 0.0
        for hour in 0..<24 {
            let multiplier = PeakHours.isPeak(hour: hour, weekday: weekday, day: beijingDay) ? PeakHours.peakMultiplier : 1
            total += multiplier * (Double(day.hourHit[hour]) * 0.02
                + Double(day.hourMiss[hour]) * 1
                + Double(day.hourOut[hour]) * 4) / million
        }
        return total
    }

    /// 单条 lane 的折算：cost.of 那天的账算（节假日整天按闲时）。Probe 自检也走这里，别另写一份单价。
    static func saved(of laneDay: SubagentLog.Day, in cost: DayCost) -> Double {
        guard cost.weekday != 0 else { return 0 }
        return DeepSeekQuote.cost(of: laneDay, weekday: cost.weekday, beijingDay: cost.day)
    }

    /// 那天所有免费子线程（不在账单里的 lane）若走 DeepSeek flash 付费要花的总钱数。
    /// 子线程行和左上角大数右边的「（省 ¥X）」都从这里取，不许各自再算一遍。
    static func saved(of cost: DayCost) -> Double {
        guard cost.weekday != 0 else { return 0 }
        var total = 0.0
        for lane in SubagentLane.all where !lane.billed {
            if let day = cost.subagents[lane.id] {
                total += DeepSeekQuote.saved(of: day, in: cost)
            }
        }
        return total
    }
}
