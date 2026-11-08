import Foundation

/// 界面语言：跟系统走（含「系统设置 → 语言与地区 → 应用程序」里单独给这个 App 指定语言）。
///
/// 不用 .lproj / Localizable.strings：这个 App 只有两份文案、一个可执行文件，
/// 打包脚本是自己拼的 .app，多一层资源包只会多一个「装的时候忘了拷」的坑。
/// 两边都用 switch 写，编译器保证每个 key 中英文都有——漏了编不过。
enum Lang {
    case zh, en

    /// 系统语言。`AppleLanguages` 里第一条就是当前对这个 App 生效的语言。
    /// `PIM_LANG=en` / `PIM_LANG=zh` 可以强行指定，自检出英文截图时用。
    static let current: Lang = {
        if let forced = ProcessInfo.processInfo.environment["PIM_LANG"], !forced.isEmpty {
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
    case hourChart, tokenLayer, unitPrice, unitPriceHelp, requestHelp, perRequest, requests
    case toolCalls, toolCallsHelp
    case subagent, subagentHelp
    case laneCC, inBill
    /// 全天闲时那天，闲时/高峰两根条塌成的一行。
    case allDayOffPeakNote
    /// 服务状态块（2026-11-07）：header 左侧、右侧三种状态、内容行、hover 说明。
    case serviceStatus, serviceOK, serviceJitter, serviceStatusHelp
    /// 服务状态灯条右端那句口径 + feed 覆盖不到那天的 hover。
    case last30Days, noFeedCoverage
    case perHour
    /// 总 token 那个括号里的词（「合计」）。
    case altogether
    /// hero 左边大数的抬头：看今天/昨天用固定词，更早用「短日期 + 花费」（2026-11-07 改）。
    case todaySpend, yesterdaySpend
    /// hero 右边大数（当天 token 总量）的抬头。
    case todayTokens, yesterdayTokens
    /// 30 天那条柱顶金额的单位，缀在刻度行右端说一次口径。
    case unitYuan
    /// 分模型那格的抬头。
    case byModel
    /// hero token 括号里的档名：计费（主智能体，走 DeepSeek 账单）。
    case billedTokens
    /// hero 钱括号里全天闲时那天的档名。
    case heroAllOffPeak
    /// 账单这侧的那一排（DeepSeek）。上排叫主智能体、下排叫子智能体，是他自己定的一对词。
    case mainThread

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
        case .allDayOffPeakNote: return "全天闲时（2 倍价的时段一个都没有）"
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
        case .runwayNoData: return "要三整天的账单才估得出日均"
        case .priceLine: return "价格"
        case .hourChart: return "上面一层是每小时花了多少（琥珀浅 = 闲时半价、琥珀深 = 高峰双倍，最淡的是还没到的时段），下面一层是同一小时的 token 量（青 = 主线程、顶上那一段绿 = 子智能体）；浅灰的是前一天同一小时。"
        case .tokenLayer: return "token"
        case .unitPrice: return "每亿 token"
        case .requests: return "完成任务"
        case .perRequest: return "每次"
        case .requestHelp: return "平台记的请求数：一次 API 调用算一次（工具每转一圈算一次，子代理跑的也算），账单接口只给这个总数，拆不出哪几次是我自己问的。后面的「每次」= 那天的钱 ÷ 那天的请求数、那天的 token ÷ 那天的请求数。"
        case .toolCalls: return "检索"
        case .toolCallsHelp: return "搜索与网页抓取按次计费，每次 0.005 元，不看返回几条、也不看要不要正文。平台账单接口只给次数（tool-search / tool-fetch），这笔钱是按单价乘出来的。右边那个「＋ CC N 次」是 Claude Code 自带的联网工具（WebSearch / WebFetch），走订阅、不进这笔钱，也不并进左边的次数。"
        case .subagent: return "子智能体"
        case .subagentHelp: return "Claude Code 那边的调用量：年费订阅、一分钱不花（¥0）。只统计非 deepseek 的模型——模型名是 deepseek-* 的那半已经记在 DeepSeek 账单里，不重复计。按天按小时从本机日志数出来，右边是它占「子智能体 + DeepSeek 请求」的份额。「省 ¥」是这些调用若走 DeepSeek flash 付费 API 要花多少钱：按每条记录发生的小时分闲时/高峰，命中/未命中/输出分别计价，命中率用日志里实测的 cache_read 比例（不另假设），不含检索费。这层的 token 在下面那根 token 柱上是顶上那一段绿色（主线程是青的），柱高是那个小时的总量；每小时的拆分把鼠标停在柱子上看，全天总量看右边。"
        case .laneCC: return "Claude Code"
        case .inBill: return "已在账单"
        case .serviceStatus: return "服务状态"
        case .serviceOK: return "正常"
        case .serviceJitter: return "波动"
        case .serviceStatusHelp: return "DeepSeek 现在的服务状态：右上角那颗灯就是当前状态（正常 / 降级 / 部分中断，事件进行中会带「已 n 分钟」），点它跳 status.deepseek.com。feed 每 10 分钟拉一次（Atom，只取内容、不带凭据，官方说了算）。"
        case .last30Days: return "最近 30 天"
        case .noFeedCoverage: return "feed 未覆盖"
        case .perHour: return "次/小时"
        case .altogether: return "共"
        case .todaySpend: return "今天花费"
        case .todayTokens: return "今日 token"
        case .yesterdaySpend: return "昨天花费"
        case .yesterdayTokens: return "昨天 token"
        case .unitYuan: return "元"
        case .byModel: return "分模型"
        case .billedTokens: return "计费"
        case .heroAllOffPeak: return "全天闲时"
        case .mainThread: return "主智能体"
        case .unitPriceHelp: return "左边：那天的花费 ÷ 那天的 token 量（命中 + 未命中 + 输出）× 1 亿；高峰时段长、缓存没命中，这个数就高。右边：每亿 token 摊到多少次「完成任务」（= 1 亿 ÷ 每次的 token 量），括号里是前一天截到同一时刻的数。一次 API 调用算完成一次（工具每转一圈、子代理跑的都在里面）。"
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
        case .dataRead: return "读：余额走 api.deepseek.com（官方公开接口），账单走 platform.deepseek.com（平台网页自己在用的接口），服务状态走 status.deepseek.com（官方状态页，只取内容、不带凭据）。子智能体那层读本机 ~/.claude/projects 的调用记录——只数次数和模型名，不看内容，不出本机。"
        case .dataStore: return "存：凭据在 ~/Library/Application Support/PIMeter/account.json（只有本用户能读），不进日志。"
        case .dataSend: return "发：只发上面那两个域名。没有别的服务器，没有统计上报，没有第三方 SDK。"
        case .dataNoStore: return "不存：账单明细只在内存里；网页登录态在 ~/Library/WebKit/app.pimeter.macos，可以一键清掉。"
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
        case .allDayOffPeakNote: return "Off-peak all day (no 2× priced hours)"
        case .hit: return "Hit"
        case .miss: return "Miss"
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
        case .runwayNoData: return "Needs three full days of billing"
        case .priceLine: return "Prices"
        case .hourChart: return "Top: spend per hour (light amber = off-peak half price, deep amber = peak double, faintest = not yet). Below: tokens for the same hour (teal = main agent, the green top segment = sub-agent). The pale grey is the same hour yesterday."
        case .tokenLayer: return "tokens"
        case .unitPrice: return "Per 100M tokens"
        case .requests: return "Tasks"
        case .perRequest: return "Each"
        case .requestHelp: return "Requests as the platform counts them: one per API call — every tool round and every subagent run; the billing API only gives this total. “Each” is that day's spend ÷ requests, and that day's tokens ÷ requests."
        case .toolCalls: return "Lookups"
        case .toolCallsHelp: return "Search and page fetches are billed per call at ¥0.005 each — not per result, not by content size. The billing API only reports the counts (tool-search / tool-fetch); the money here is count × price. The \"＋ CC N\" on the right is Claude Code's own web tools (WebSearch / WebFetch) — covered by the subscription, not part of this money or this count."
        case .subagent: return "Sub-agent"
        case .subagentHelp: return "Calls made by Claude Code: covered by the annual subscription, ¥0. Only non-DeepSeek models count here — calls with a deepseek-* model are already on the DeepSeek bill, never counted twice. Counted per day and hour from local logs; the figure on the right is its share of sub-agent + DeepSeek requests. “Saved ¥” is what these calls would cost on the DeepSeek flash API: split into off-peak/peak by the hour each record happened, priced separately for cache hit / miss / output, with the hit rate taken from the logged cache_read (no extra assumption); tool fees not included. Its tokens are the top segment of the token bar above — match the colour; the bar's height is still that hour's total. Hover a bar for the per-hour split, the day's total is on the right."
        case .laneCC: return "Claude Code"
        case .inBill: return "in bill"
        case .serviceStatus: return "Service status"
        case .serviceOK: return "OK"
        case .serviceJitter: return "Degraded"
        case .serviceStatusHelp: return "DeepSeek's current status: the light at the top right (operational / degraded / partial outage — an ongoing incident shows \"n min\"). Click it to open status.deepseek.com. The feed is fetched every 10 minutes (Atom, content only, no credentials — the official page decides)."
        case .last30Days: return "Last 30 days"
        case .noFeedCoverage: return "outside feed coverage"
        case .perHour: return "per hour"
        case .altogether: return "total"
        case .todaySpend: return "Spent today"
        case .todayTokens: return "Tokens today"
        case .yesterdaySpend: return "Spent yesterday"
        case .yesterdayTokens: return "Tokens yesterday"
        case .unitYuan: return "¥"
        case .byModel: return "By model"
        case .billedTokens: return "Billed"
        case .heroAllOffPeak: return "Off-peak all day"
        case .mainThread: return "Main agent"
        case .unitPriceHelp: return "Left: the day's spend ÷ its tokens (cache hit + miss + output) × 100M — more peak hours or cache misses push it up. Right: completed tasks per 100M tokens (100M ÷ tokens per call), with the previous day cut to the same hour in brackets. One API call counts as one task, tool rounds and subagent runs included."
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
        case .dataRead: return "Reads: balance from api.deepseek.com (public API), billing from platform.deepseek.com (the API the platform site itself uses). The subagent layer counts calls from ~/.claude/projects on this Mac — counts and model names only, no content, never leaves the machine."
        case .dataStore: return "Stores: credentials in ~/Library/Application Support/PIMeter/account.json (readable only by you), never logged."
        case .dataSend: return "Sends: only to those two domains. No other server, no analytics, no third-party SDK."
        case .dataNoStore: return "Kept in memory only: billing details. The web session lives in ~/Library/WebKit/app.pimeter.macos and can be cleared in one click."
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

    /// token 的单位固定，2026-11-08 他定的：面板上只出现亿（英文 B），不出现万 / K / M。
    static func tokenUnit(_ top: Double) -> (divisor: Double, suffix: String) {
        switch Lang.current {
        case .zh: return (100_000_000, "亿")
        case .en: return (1_000_000_000, "B")
        }
    }

    /// token 总量带单位，量级由调用方定（同一块里的几个总数要同一个量级，见 MeterPanel.headerUnit）：
    /// "1.1 亿 token" / "110M tokens"。默认版按这个数自己挑，两处不要混用。
    static func tokenSize(_ tokens: Int, unit: (divisor: Double, suffix: String)) -> String {
        let number = trimDecimal(Double(tokens) / unit.divisor)
        let head = unit.suffix.isEmpty ? number : (Lang.current == .zh ? "\(number) \(unit.suffix)" : "\(number)\(unit.suffix)")
        return "\(head) \(T.tokenCount.s)"
    }

    /// hero 抬头看更早的日子：跟短日期拼（"11-06 花费" / "11-06 spend"），词跟今天/昨天那对同源。
    static func heroDatedSpend(_ day: String) -> String {
        Lang.current == .zh ? "\(day) 花费" : "\(day) spend"
    }

    static func heroDatedTokens(_ day: String) -> String {
        Lang.current == .zh ? "\(day) token" : "\(day) tokens"
    }

    /// 叠起来那根 token 柱子的悬停：「12:00 · 主智能体 2.5 亿 token · Claude Code 0.1 亿 token」。
    /// 一根柱子是两层加起来的，分开说才看得出谁多。
    static func stackBarHelp(hour: Int, parts: [(String, String)]) -> String {
        ([String(format: "%02d:00", hour)] + parts.map { "\($0.0) \($0.1)" }).joined(separator: " · ")
    }

    /// 括号里那个「连子智能体一共」：「合计 1.4 亿 token」/「1.4B tokens total」。
    static func tokenAll(_ total: String) -> String {
        Lang.current == .zh ? "\(T.altogether.s) \(total)" : "\(total) \(T.altogether.s)"
    }

    /// 「每亿 token 摊到多少次」："完成任务 595 个" / "595 tasks"。
    /// "检索 133 次" / "133 lookups"
    static func toolCalls(_ count: Int) -> String {
        let number = Fmt.count(count)
        return Lang.current == .zh ? "\(T.toolCalls.s) \(number) 次" : "\(number) \(T.toolCalls.s.lowercased())"
    }

    /// "185 次" / "185"
    static func toolCallCount(_ count: Int) -> String {
        let number = Fmt.count(count)
        return Lang.current == .zh ? "\(number) 次" : number
    }

    /// 括号里的拆法："搜索 124 · 抓取 9"
    static func toolCallsBreakdown(search: Int, fetch: Int) -> String {
        let s = Fmt.count(search), f = Fmt.count(fetch)
        return Lang.current == .zh ? "搜索 \(s) · 抓取 \(f)" : "\(s) search · \(f) fetch"
    }

    /// 检索层 header 的小尾巴："＋ CC 15 次" / "＋ CC 15"。
    /// Claude Code 自带联网那几次：单列口径，不并进账单那 75 次。
    static func ccWebCalls(_ count: Int) -> String {
        let number = Fmt.count(count)
        return Lang.current == .zh ? "＋ CC \(number) 次" : "＋ CC \(number)"
    }

    static func tasksPer100M(_ count: Int) -> String {
        let number = Fmt.count(count)
        return Lang.current == .zh ? "\(T.requests.s) \(number) 个" : "\(number) tasks"
    }

    /// 后面那个对照：「（昨天 588 个）」/ "(yesterday 588)"。
    static func tasksPer100MReference(_ count: String, relation: String) -> String {
        switch Lang.current {
        case .zh:
            return "（\(relation) \(count) 个）"
        case .en:
            return "(\(relation.prefix(1).lowercased())\(relation.dropFirst()) \(count))"
        }
    }

    /// 柱子/总量上那个数：≥100 取整；≥1 一位小数；>0 且 <1 两位小数（"0.04"）；0 就是 "0"。
    /// 2026-11-08 单位固定成亿之后，小于 1 亿的数靠两位小数撑住（0.04 亿 = 400 万 token）。
    static func trimDecimal(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 1 { return String(format: "%.1f", value) }
        if value > 0 { return String(format: "%.2f", value) }
        return "0"
    }

    /// 高峰那一格的悬停说明。整句一起写：以前在调用处拼「半句 + 倍数 + 。
    /// 结果英文模式下句尾挂着一个中文句号。
    static func peakHelp() -> String {
        let multiplier = PeakHours.multiplierLabel
        return Lang.current == .zh
            ? "高峰：北京时间工作日 9–12、14–18（法定节假日除外），单价是闲时的 \(multiplier)。"
            : "Peak: Beijing time weekdays 9–12 and 14–18 (public holidays excepted). Unit price is \(multiplier) the off-peak price."
    }

    /// 节假日表过期那一句（只在悬停里，按年份说）。
    static func holidayStale(year: Int) -> String {
        Lang.current == .zh
            ? "\(year) 年法定节假日表待更新，节假日先按周末/工作日估算。"
            : "The \(year) public-holiday table is out of date; holidays fall back to the weekday rule."
    }

    /// "余额还能撑 10 天" / "Balance lasts 10 days"
    static func runway(_ days: Int) -> String {
        Lang.current == .zh ? "\(T.runway.s) \(days) 天" : "\(T.runway.s) \(days) days"
    }

    /// 后面那截小字：「（按今天这个速度 11 天）」。只在今天明显更快（或明显更慢）时才出现。
    static func runwayAtPace(_ days: Int) -> String {
        Lang.current == .zh ? "（按近一周 \(days) 天）" : "(\(days) days at this week's rate)"
    }

    /// 「还能撑几天」的悬停说明。得说清楚它不是 30 天除一下，也不是把趋势往后推，
    /// 还要说清楚后面那截小字为什么可能更短（今天已经花到这个份上了）。
    static func runwayHelp() -> String {
        Lang.current == .zh
            ? "余额 ÷ 现在的日均。日均不是 30 天平均，也不往后推趋势：最近两周每天花了多少，越近权重越大（半衰期一天半，最近一周占九成六），今天只算已经过掉的那几个小时。后面那截「按今天这个速度」是今天已花的钱按已过时长折成整天，用来追当天的变化——加权日均再快也要等一天过去才动。"
            : "Balance ÷ the current daily burn. Not a 30-day average, and no trend extrapolated forward: daily spend over the last two weeks, each day back counting half as much as the next (half-life 1.5 days, the last week carries 96%), with today counted only up to the current hour. The ‘today’s pace’ figure is today's spend scaled to a full day, so a jump shows up the same day."
    }

    /// 「今天花费」那行括号尾巴：「· 省 ¥23.34」/ "· ¥23.34 saved"。
    /// 不带括号（2026-11-08 挪到花费下面那块空里，写成括号就像一句旁注，现在它是这行第三个数）。
    static func savedMoney(_ money: String) -> String {
        Lang.current == .zh ? "省 \(money)" : "\(money) saved"
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

    /// 命中那一列的悬停说明：命中率怎么算、括号里那串是什么单位、比的是哪一段。
    static func hitHelp() -> String {
        Lang.current == .zh
            ? "命中率 = 命中 ÷（命中 + 未命中）。括号里是跟前一天比的百分点差。今天还没过完，两边都只算已经走完的整点，所以比的是同样长的一段。"
            : "Cache hit rate = hit ÷ (hit + miss). The bracket is the change vs the previous day, in percentage points. Today is not over yet, so both sides only count completed hours — the same stretch on each day."
    }

    /// 命中率后面那串括号：(比昨天 +2.2%) / (vs yesterday +2.2%)
    static func hitDelta(_ delta: String, relation: String) -> String {
        Lang.current == .zh ? "（\(relation) \(delta)）" : "(\(relation) \(delta))"
    }

    /// 高峰档的档名（倍数含在内），金额另算一节：下面那根条用它整段；hero 括号拆开用（见 peakSuffix）。
    static var peakName: String {
        Lang.current == .zh ? "\(T.peak.s)（\(PeakHours.multiplierLabel)价）" : "\(T.peak.s) (\(PeakHours.multiplierLabel) rate)"
    }

    /// hero 钱括号里跟在金额后面的倍数：「高峰 ¥49.41（2 倍价）」——档名干净、数字贴着档名，倍数缀在最后。
    static var peakSuffix: String {
        Lang.current == .zh ? "（\(PeakHours.multiplierLabel)价）" : " (\(PeakHours.multiplierLabel) rate)"
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

    // MARK: - 服务状态（2026-11-07）

    /// header 右侧：「部分中断 · 已 17 分钟」/ "Partial outage · 17 min"。开不满 1 分钟按 1 分钟说。
    static func serviceOngoing(minutes: Int) -> String {
        let minutes = max(1, minutes)
        return Lang.current == .zh ? "部分中断 · 已 \(minutes) 分钟" : "Partial outage · \(minutes) min"
    }

    /// feed 里的状态词翻成面板用词：原词（monitoring…）保留给 hover 说口径。
    static func serviceStatusWord(_ status: String) -> String {
        switch status {
        case "investigating": return Lang.current == .zh ? "调查中" : "investigating"
        case "identified": return Lang.current == .zh ? "已定位" : "identified"
        case "resolved": return Lang.current == .zh ? "已解决" : "resolved"
        default: return Lang.current == .zh ? "正在监控" : "monitoring"
        }
    }

    /// 无事件时的本机一行已删（2026-11-07 他不要本机探测上屏），serviceLocal 一并撤了。

    /// 灯条一格的收尾："18:48 已恢复" / "resolved 18:48"。
    static func serviceRecovered(_ clock: String) -> String {
        Lang.current == .zh ? "\(clock) 已恢复" : "resolved \(clock)"
    }
}
