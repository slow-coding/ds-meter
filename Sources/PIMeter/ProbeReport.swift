import Foundation

/// `--probe` 打出去的那份 JSON。
///
/// 为什么不用 `[String: Any]` + JSONSerialization：那种写法把类型检查推到运行时。
/// CI 上的 Swift 比本机旧，`[String: Any]` 里的 Double 会被桥成 `__SwiftValue`，
/// JSONSerialization 认不出来，直接抛 NSException 把进程带走——于是**发出去的每个包，
/// `--probe` 都是崩的**，而本机怎么跑都是好的（v1.0.3 和 v1.0.4 都这样，2026-10-28 拿
/// 挂载的 dmg 里那个二进制跑才发现）。写成 Codable，类型不对是编译错误，这种坑不会再回来。
struct ProbeReport: Encodable {
    struct Model: Encodable {
        let name: String
        let tokens: Int
        let cny: Double
    }

    /// 一条子线程来源的自检数。
    struct LaneUsage: Encodable {
        var calls: Int = 0
        var tokens: Int = 0
        var hourly: [Int] = []
        var daily: [Int: Int] = [:]
        /// 今天这份若走 DeepSeek flash 付费 API 要花多少钱（元）：自检脚本对照基准脚本用。
        var equivalent: Double = 0
        /// CC 自带联网（WebSearch / WebFetch）今天多少次：对拍 /tmp/ref_ccweb.py 的 web。
        var webCalls: Int = 0
        /// 走 DeepSeek key 的检索脚本次数（已在账单里）：对拍同脚本的 viaDS。
        var searchViaDS: Int = 0
        /// 自带联网按小时的分布：同刻对拍用。
        var hourlyWeb: [Int] = []
    }

    let hasData: Bool
    let usageError: String
    let balance: Double
    let moneyToday: Double
    let peakCost: Double
    let offPeakCost: Double
    let peakPremium: Double
    let dayOffsets: [Int]
    let daily: [Double]
    let yesterdayMoney: Double
    let yesterdayPeak: Double
    let yesterdayOffPeak: Double
    let yesterdayPremium: Double
    let yesterdayWeekday: Int
    let yesterdayHitRate: Double
    let moneyComplete: Bool
    /// 日均是加权平均（Trend），runwayDays 是面板上那个「还能撑 N 天」
    let burnRate: Double
    /// 今天过了多少小时：burnRate 里今天那一段只按这个时长折算，有它才能拿 daily 复核
    let elapsedHours: Double
    let yesterdayMissRate: Double
    let runwayDays: Int
    let requests: Int
    /// 检索：搜索 + 抓取各多少次，以及按 0.005/次 算出来的钱
    let searchCalls: Int
    let fetchCalls: Int
    let toolCost: Double
    let hourToolCalls: [Int]
    /// 子线程：每条来源一份（键是 SubagentLane.id，如 "cc" / "pi"）——
    /// 今天次数、今天 token、今天按小时、近 30 天按天（偏移 → 次数）。
    /// 逐日对独立基准（/tmp/pi-lanes-reference.py）用；历史日必须精确相等。
    var subagents: [String: LaneUsage] = [:]
    let yesterdayRequests: Int
    /// 一次请求平均多少 token：token 总量 ÷ 请求数
    let perRequestTokens: Double
    let miss: Int
    let hit: Int
    let output: Int
    let hitRate: Double
    /// 「比昨天」实际用来做差的那几个数：今天只算到已过去的小时，两边一样长
    let hitRateSameHours: Double
    let yesterdayHitRateSameHours: Double
    let unitPriceSameHours: Double
    let yesterdayUnitPriceSameHours: Double
    let unitPrice: Double
    let yesterdayUnitPrice: Double
    let ratePerHour: Double
    let tone: String
    let models: [Model]
    let hours: [Double]
    /// 命中 / 未命中按小时：核平台那份小时桶跟本机日志对不对得上，只能看这个
    let hourHit: [Int]
    let hourMiss: [Int]
    let yesterdayHourHit: [Int]
    let yesterdayHourMiss: [Int]
    let panelSize: String
    let panelYesterdaySize: String
    let priceVerified: String
    let priceStale: Bool
    /// demo 模式不碰凭据：截图和自检都不该读本机那两串
    let apiKey: String

    // 只有带对应参数时才有
    var statusPNG: String?
    var panelPNG: String?
    var pickerSize: String?
    var settingsSize: String?
}
