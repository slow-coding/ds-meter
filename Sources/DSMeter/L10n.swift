import Foundation

/// 界面语言：跟系统走（含「系统设置 → 语言与地区 → 应用程序」里单独给这个 App 指定语言）。
///
/// 不用 .lproj / Localizable.strings：这个 App 只有两份文案、一个可执行文件，
/// 打包脚本是自己拼的 .app，多一层资源包只会多一个「装的时候忘了拷」的坑。
/// 两边都用 switch 写，编译器保证每个 key 中英文都有——漏了编不过。
enum Lang {
    case zh, en

    /// 系统语言。`AppleLanguages` 里第一条就是当前对这个 App 生效的语言。
    /// `DSM_LANG=en` / `DSM_LANG=zh` 可以强行指定，自检出英文截图时用。
    static let current: Lang = {
        if let forced = ProcessInfo.processInfo.environment["DSM_LANG"], !forced.isEmpty {
            return forced.lowercased().hasPrefix("zh") ? .zh : .en
        }
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return (preferred.first ?? "en").lowercased().hasPrefix("zh") ? .zh : .en
    }()
}

/// 一条文案。`T.balance.s` 拿到当前语言的那一句。
enum T {
    // 面板
    case balance, today, yesterday, last30, pickDay, hidePicker
    case balanceUnavailable, balanceHelp, tokenCount
    case offPeak, peak, offPeakDash, peakDash, peakAllOffPeak
    case hit, miss, hitDash, missDash
    case loginTitle, loginExpiredTitle, loginBody, loginAction
    case setupTitle, setupBody, loginExpiredBody, setupBalanceOnly, loginStaysLocal
    case vsYesterday, vsPreviousDay, previousDay
    case runway, runwayNoData, priceLine
    case hourChart, tokenLayer, unitPrice, unitPriceHelp

    // 菜单
    case menuRefresh, menuSettings, menuLogin, menuUsage, menuPricing, menuQuit, menuAutoStart, statusTooltip

    // 设置：通用
    case tabGeneral, tabAccount, tabAbout
    case autoStart, autoStartNote
    case refreshTitle, refreshPower, refreshDefault, refreshFrequent, refreshNote
    case languageTitle, languageFollow, languageNote

    // 设置：账号
    case apiKeyTitle, apiKeyNote
    case tokenTitle, tokenNote, tokenLogin, tokenLogout, tokenLoginNote
    case save, forget, saved, deleted
    case forgetTitle, forgetBody, delete, cancel
    case loginInProgress, loginDone, loginCancelled, loginSignedOut
    case loginWindowTitle

    // 设置：关于
    case pricingTitle, openPricing, pricingRule, priceStaleNote, dataTitle
    case dataRead, dataStore, dataSend, dataNoStore, dataDisclaimer

    // 状态与错误
    case notSet, fromEnv, noApiKey, networkError, balanceUnreadable, platformUnreadable
    case tokenExpired, noToken, noTokenHint, usageUnavailable, modelOther
    case todayLabel, nowPeak, nowOffPeak, savedState

    var s: String { Lang.current == .zh ? zh : en }

    private var zh: String {
        switch self {
        case .balance: return "余额"
        case .today: return "今日"
        case .yesterday: return "昨天"
        case .last30: return "近 30 天"
        case .pickDay: return "选日期"
        case .hidePicker: return "收起最近 30 天"
        case .balanceUnavailable: return "取不到余额"
        case .balanceHelp: return "这是本机取数的时间。余额接口是实时的；下面的账单来自平台，平台那边本身还有约 5 分钟延迟。"
        case .tokenCount: return "token"
        case .offPeak: return "闲时"
        case .peak: return "高峰"
        case .offPeakDash: return "闲时 —"
        case .peakDash: return "高峰 —"
        case .peakAllOffPeak: return "高峰 全天闲时"
        case .hit: return "命中"
        case .miss: return "未命中"
        case .hitDash: return "命中 —"
        case .loginTitle: return "还没登录"
        case .loginExpiredTitle: return "登录过期了"
        case .loginBody: return "余额是用你存的 API Key 查的；今天花了多少、分模型、命中率，要登录一次。"
        case .loginAction: return "登录网页读取"
        case .setupTitle: return "还没连接"
        case .setupBody: return "登录一次，就能看今天花了多少、每小时、分模型、命中率。"
        case .setupBalanceOnly: return "只看余额？填一个 API Key"
        case .loginStaysLocal: return "登录态只存这台 Mac，只发给 platform.deepseek.com"
        case .loginExpiredBody: return "重新登录一次，账单就回来了。余额不受影响。"
        case .missDash: return "未命中 —"
        case .vsYesterday: return "比昨天"
        case .vsPreviousDay: return "比前一天"
        case .previousDay: return "前一天"
        case .runway: return "余额还能撑"
        case .runwayNoData: return "跑满一整天之后才有「平均每天」"
        case .priceLine: return "价格"
        case .hourChart: return "上面一层是每小时花了多少（绿闲时、橙高峰，淡的是还没到的时段），下面一层是同一小时的 token 量；灰的是前一天同一小时"
        case .tokenLayer: return "token"
        case .unitPrice: return "每亿 token"
        case .unitPriceHelp: return "那天的花费 ÷ 那天的 token 量（命中 + 未命中 + 输出）× 1 亿。高峰时段长、缓存没命中，这个数就高。"
        case .menuRefresh: return "刷新"
        case .menuSettings: return "设置…"
        case .menuLogin: return "登录网页…"
        case .menuUsage: return "打开用量页"
        case .menuPricing: return "打开价格页"
        case .menuQuit: return "退出"
        case .menuAutoStart: return "开机自动启动"
        case .statusTooltip: return "DeepSeek 今日花费 · 点开看明细 · 右键菜单"
        case .tabGeneral: return "通用"
        case .tabAccount: return "账号"
        case .tabAbout: return "关于"
        case .autoStart: return "开机自动启动"
        case .autoStartNote: return "装一个 LaunchAgent，登录时拉起；关掉就删掉它。"
        case .refreshTitle: return "刷新"
        case .refreshPower: return "省电 · 5 分钟"
        case .refreshDefault: return "默认 · 2 分钟"
        case .refreshFrequent: return "最频繁 · 30 秒"
        case .refreshNote: return "账单本身有约 5 分钟延迟；面板开着时另按 15 秒取；睡眠和息屏时都不取。两分钟一取 = 每小时约 60 次请求，跟开着一个平台的用量页一个量级；连续失败会自动拉长间隔（最长 15 分钟一次）。"
        case .languageTitle: return "语言"
        case .languageFollow: return "跟随系统"
        case .languageNote: return "改系统语言，或在「系统设置 → 语言与地区 → 应用程序」里单给本 App 指定，重开 App 生效。"
        case .apiKeyTitle: return "API Key · 读余额"
        case .apiKeyNote: return "这个 key 只能查余额。花费和分模型的账单走下面那串平台 Token。"
        case .tokenTitle: return "平台 Token · 读账单"
        case .tokenNote: return "这串等于你账号的登录态；只存本机（凭据文件只有你能读），只发给 platform.deepseek.com。"
        case .tokenLogin: return "登录网页读取"
        case .tokenLogout: return "退出网页登录"
        case .tokenLoginNote: return "点上面的按钮，在弹出的网页里登录（手机验证码 / 密码 / 微信扫码都行），登录态自己读过来。"
        case .save: return "保存"
        case .forget: return "删除已存凭据"
        case .saved: return "已保存，正在重新取余额"
        case .deleted: return "已删除，现在没有存任何凭据"
        case .forgetTitle: return "删除已存的凭据？"
        case .forgetBody: return "本机那两串凭据会删掉。之后余额和用量都取不到，要等你重新填。"
        case .delete: return "删除"
        case .cancel: return "取消"
        case .loginWindowTitle: return "登录 DeepSeek 开放平台"
        case .loginInProgress: return "在弹出的网页里登录…"
        case .loginDone: return "登录好了，已保存"
        case .loginCancelled: return "没登录，什么都没存"
        case .loginSignedOut: return "已退出网页登录，下次要重新登录"
        case .pricingTitle: return "计费规则"
        case .openPricing: return "打开价格页 ↗"
        case .pricingRule: return "高峰：北京时间工作日 9–12、14–18（法定节假日除外）；空闲价是高峰的一半。"
        case .priceStaleNote: return "之后没再看，点开确认一下"
        case .dataTitle: return "数据说明"
        case .dataRead: return "读：余额走 api.deepseek.com（官方公开接口），账单走 platform.deepseek.com（平台网页自己在用的接口）。不读会话日志，不读对话内容。"
        case .dataStore: return "存：凭据在 ~/Library/Application Support/DSMeter/account.json（只有本用户能读），不进日志。"
        case .dataSend: return "发：只发上面那两个域名。没有别的服务器，没有统计上报，没有第三方 SDK。"
        case .dataNoStore: return "不存：账单明细只在内存里；网页登录态在 ~/Library/WebKit/app.dsmeter.macos，可以一键清掉。"
        case .dataDisclaimer: return "非官方工具，与 DeepSeek 官方无关。"
        case .notSet: return "没绑定"
        case .fromEnv: return "临时：来自环境变量，没保存"
        case .noApiKey: return "没绑定 API Key"
        case .networkError: return "网络不通"
        case .balanceUnreadable: return "余额返回看不懂"
        case .platformUnreadable: return "平台返回看不懂"
        case .tokenExpired: return "平台 Token 过期了"
        case .noToken: return "还没绑定平台 Token"
        case .noTokenHint: return "还没绑定平台 Token：右键 → 设置"
        case .usageUnavailable: return "取不到用量"
        case .modelOther: return "其他"
        case .todayLabel: return "今天"
        case .nowPeak: return "现在 高峰"
        case .nowOffPeak: return "现在 闲时"
        case .savedState: return "已保存"
        }
    }

    private var en: String {
        switch self {
        case .balance: return "Balance"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last30: return "30 days"
        case .pickDay: return "Pick a day"
        case .hidePicker: return "Hide the last 30 days"
        case .balanceUnavailable: return "Balance unavailable"
        case .balanceHelp: return "When this Mac last fetched. The balance API is live; billing data below comes from the platform and lags about 5 minutes."
        case .tokenCount: return "tokens"
        case .offPeak: return "Off-peak"
        case .peak: return "Peak"
        case .offPeakDash: return "Off-peak —"
        case .peakDash: return "Peak —"
        case .peakAllOffPeak: return "Peak — off-peak all day"
        case .hit: return "Cache hit"
        case .miss: return "Cache miss"
        case .hitDash: return "Cache hit —"
        case .loginTitle: return "Not signed in"
        case .loginExpiredTitle: return "Sign-in expired"
        case .loginBody: return "Balance comes from your saved API key. Daily spend, models and cache hit need one sign-in."
        case .loginAction: return "Sign in on web"
        case .setupTitle: return "Not connected"
        case .setupBody: return "Sign in once to see today's spend, hourly, models and cache hit."
        case .setupBalanceOnly: return "Balance only? Add an API key"
        case .loginStaysLocal: return "Sign-in stays on this Mac, only sent to platform.deepseek.com"
        case .loginExpiredBody: return "Sign in again and billing comes back. Balance is unaffected."
        case .missDash: return "Cache miss —"
        case .vsYesterday: return "vs yesterday"
        case .vsPreviousDay: return "vs previous day"
        case .previousDay: return "previous day"
        case .runway: return "Balance lasts"
        case .runwayNoData: return "Needs a full day of data for the daily average"
        case .priceLine: return "Prices"
        case .hourChart: return "Top: spend per hour (green off-peak, orange peak, faded = not yet). Below: tokens for the same hour. Grey is the same hour yesterday."
        case .tokenLayer: return "tokens"
        case .unitPrice: return "Per 100M tokens"
        case .unitPriceHelp: return "The day's spend ÷ its tokens (cache hit + miss + output) × 100M. More peak hours or more cache misses push it up."
        case .menuRefresh: return "Refresh"
        case .menuSettings: return "Settings…"
        case .menuLogin: return "Sign in on the web…"
        case .menuUsage: return "Open usage page"
        case .menuPricing: return "Open pricing page"
        case .menuQuit: return "Quit"
        case .menuAutoStart: return "Launch at login"
        case .statusTooltip: return "DeepSeek spend today · click for details · right-click for menu"
        case .tabGeneral: return "General"
        case .tabAccount: return "Account"
        case .tabAbout: return "About"
        case .autoStart: return "Launch at login"
        case .autoStartNote: return "Installs a LaunchAgent; turning it off removes it."
        case .refreshTitle: return "Refresh"
        case .refreshPower: return "Power saving · 5 min"
        case .refreshDefault: return "Default · 2 min"
        case .refreshFrequent: return "Most frequent · 30 sec"
        case .refreshNote: return "Billing lags about 5 minutes. While the panel is open it refreshes every 15 seconds; sleep and screen-off pause it. Every 2 minutes is about 60 requests an hour — same as leaving the platform usage page open. Repeated failures back off up to 15 minutes."
        case .languageTitle: return "Language"
        case .languageFollow: return "Follows the system"
        case .languageNote: return "Change the system language, or set one just for this app in System Settings → Language & Region → Applications; restart the app to apply."
        case .apiKeyTitle: return "API key · balance only"
        case .apiKeyNote: return "This key can only read the balance. Spend and per-model billing come from the platform token below."
        case .tokenTitle: return "Platform token · billing"
        case .tokenNote: return "It is your account session. Stored only on this Mac (in a file only you can read), sent only to platform.deepseek.com."
        case .tokenLogin: return "Sign in on the web"
        case .tokenLogout: return "Sign out"
        case .tokenLoginNote: return "Press the button, sign in on the page that opens (SMS code, password or WeChat QR), and the session is read back automatically."
        case .save: return "Save"
        case .forget: return "Delete saved credentials"
        case .saved: return "Saved, refreshing balance"
        case .deleted: return "Deleted — nothing stored now"
        case .forgetTitle: return "Delete the stored credentials?"
        case .forgetBody: return "Both credentials on this Mac will be removed. Balance and usage stay unavailable until you enter them again."
        case .delete: return "Delete"
        case .cancel: return "Cancel"
        case .loginWindowTitle: return "Sign in to DeepSeek Platform"
        case .loginInProgress: return "Signing in on the page…"
        case .loginDone: return "Signed in and saved"
        case .loginCancelled: return "Not signed in — nothing stored"
        case .loginSignedOut: return "Signed out of the web session"
        case .pricingTitle: return "Pricing"
        case .openPricing: return "Open pricing page ↗"
        case .pricingRule: return "Peak: Beijing time weekdays 9–12 and 14–18 (public holidays excepted); off-peak is half the peak price."
        case .priceStaleNote: return "not checked since — take a look"
        case .dataTitle: return "Data"
        case .dataRead: return "Reads: balance from api.deepseek.com (public API), billing from platform.deepseek.com (the API the platform site itself uses). No session logs, no conversations."
        case .dataStore: return "Stores: credentials in ~/Library/Application Support/DSMeter/account.json (readable only by you), never logged."
        case .dataSend: return "Sends: only to those two domains. No other server, no analytics, no third-party SDK."
        case .dataNoStore: return "Kept in memory only: billing details. The web session lives in ~/Library/WebKit/app.dsmeter.macos and can be cleared in one click."
        case .dataDisclaimer: return "Unofficial tool, not affiliated with DeepSeek."
        case .notSet: return "not set"
        case .fromEnv: return "temporary, from environment"
        case .noApiKey: return "No API key"
        case .networkError: return "Network error"
        case .balanceUnreadable: return "Unexpected balance response"
        case .platformUnreadable: return "Unexpected platform response"
        case .tokenExpired: return "Platform token expired"
        case .noToken: return "No platform token yet"
        case .noTokenHint: return "No platform token: right-click → Settings"
        case .usageUnavailable: return "Usage unavailable"
        case .modelOther: return "other"
        case .todayLabel: return "Today"
        case .nowPeak: return "Peak now"
        case .nowOffPeak: return "Off-peak now"
        case .savedState: return "Saved"
        }
    }
}

/// 带参数的几句：数、日期、单位要拼进去，单独放，别在调用处拼中英混杂的串。
enum L {
    /// "11:45 更新" / "updated 11:45"
    static func updated(_ clock: String) -> String {
        Lang.current == .zh ? "\(clock) 更新" : "updated \(clock)"
    }

    /// token 的单位：中文用万 / 亿，英文用 M / B（换算的除数也不一样）。
    static func tokenUnit(_ top: Double) -> (divisor: Double, suffix: String) {
        switch Lang.current {
        case .zh:
            if top >= 100_000_000 { return (100_000_000, "亿") }
            if top >= 10_000 { return (10_000, "万") }
            return (1, "")
        case .en:
            if top >= 1_000_000_000 { return (1_000_000_000, "B") }
            if top >= 1_000_000 { return (1_000_000, "M") }
            if top >= 1_000 { return (1_000, "K") }
            return (1, "")
        }
    }

    /// "11.1 亿 token" / "11.1B tokens"
    static func tokenTotal(_ number: String, suffix: String) -> String {
        let head = suffix.isEmpty ? number : (Lang.current == .zh ? "\(number) \(suffix)" : "\(number)\(suffix)")
        return "\(head) \(T.tokenCount.s)"
    }

    /// 柱子/总量上那个数：三位以上不留小数（"1609" 而不是 "1609.0"）。
    static func trimDecimal(_ value: Double) -> String {
        let text = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return text
    }

    /// 高峰那一格的悬停说明。整句一起写：以前在调用处拼「半句 + 倍数 + 。
    /// 结果英文模式下句尾挂着一个中文句号。
    static func peakHelp() -> String {
        let multiplier = PeakHours.multiplierLabel
        return Lang.current == .zh
            ? "高峰：北京时间工作日 9–12、14–18（法定节假日除外），单价是闲时的 \(multiplier)。"
            : "Peak: Beijing time weekdays 9–12 and 14–18 (public holidays excepted). Unit price is \(multiplier) the off-peak price."
    }

    /// "余额还能撑 10 天" / "Balance lasts 10 days"
    static func runway(_ days: Int) -> String {
        Lang.current == .zh ? "\(T.runway.s) \(days) 天" : "\(T.runway.s) \(days) days"
    }

    /// 每亿单价后面那个对照：「（昨天 ¥5.82）」/ "(yesterday ¥5.82)"。
    /// 不另起一行、不写百分点变化：单价差几个百分点没人读得出来。
    static func unitPriceReference(_ money: String, relation: String) -> String {
        switch Lang.current {
        case .zh:
            return "（\(relation) \(money)）"
        case .en:
            // 「Yesterday」是按钮上的写法，嵌进括号里要小写才不像句中另起一句。
            return "(\(relation.prefix(1).lowercased())\(relation.dropFirst()) \(money))"
        }
    }

    /// 高峰那一格的金额。中文把倍数写在括号里，英文用 "2× rate"。
    static func peakMoney(_ money: String, multiplier: String) -> String {
        Lang.current == .zh ? "\(T.peak.s) \(money)（\(multiplier)价）" : "\(T.peak.s) \(money) (\(multiplier) rate)"
    }

    /// "2 倍" / "2×"
    static func multiplier(_ value: Double) -> String {
        let number = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return Lang.current == .zh ? "\(number) 倍" : "\(number)×"
    }

    /// 周一…周日 / Mon…Sun（索引：0 = 周一）
    static func weekday(_ index: Int) -> String {
        let zh = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return Lang.current == .zh ? zh[index % 7] : en[index % 7]
    }

    /// 菜单顶上那两行：给他一眼看到的两个数。
    static func menuToday(today: String, local: String) -> String {
        Lang.current == .zh
            ? "今日 \(today) · pi 明细 \(local)"
            : "Today \(today) · this Mac \(local)"
    }

    /// "价格 12 天没更新 ↗" / "Prices not updated in 12 days ↗"
    static func priceStale(_ days: Int) -> String {
        Lang.current == .zh ? "价格 \(days) 天没更新 ↗" : "Prices not updated in \(days) days ↗"
    }

    static func menuBalance(_ balance: String) -> String {
        Lang.current == .zh ? "余额 \(balance)" : "Balance \(balance)"
    }

    /// 设置里那行「语言：跟随系统（中文）」
    static func languageLine() -> String {
        let name = Lang.current == .zh ? "中文" : "English"
        return Lang.current == .zh ? "跟随系统（\(name)）" : "Follows the system (\(name))"
    }
}
