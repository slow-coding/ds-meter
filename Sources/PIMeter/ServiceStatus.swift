import Foundation
import UserNotifications

/// 服务状态（2026-11-07）：两个口径，官方事件优先，本机探测兜底。
///   1. 官方状态页的 Atom feed（status.deepseek.com/feed.atom，Flashduty 托管）：
///      正常 10 分钟拉一次；失败先 1 分钟、再翻倍到 10 分钟封顶。超时 8 秒。
///   2. 本机探测：每次查余额记一笔（成功与否、耗时），只留最近 60 分钟、上限 120 条。
/// 跟 Meter 那条 120 秒刷新完全解耦：这里自己排自己的节奏，不占余额那把尺。
/// feed 读不到时不报错——面板只写本机实测那半句，不出现「连不上」（2026-11-07 定稿）。
final class ServiceStatus: ObservableObject {
    struct FeedEvent {
        var id: String
        var title: String
        var updated: Date
        /// monitoring / investigating / identified / resolved，原样留着给 hover 说口径。
        var status: String
    }

    struct Probe {
        var at: Date
        var ok: Bool
        var ms: Double
    }

    /// 一次事故：同一 id（feed 里的链接）的若干条 entry 折成一行。
    /// start = 该事件最早一条 updated，end = 最晚一条；最晚一条不是 resolved 就算进行中。
    /// feed 没有严重级字段，partial / degraded 从标题里认（「部分中断」/「降级」）。
    struct Incident {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var ongoing: Bool
        var severity: String
        /// 最晚一条 entry 的原始状态词（investigating…），hover 说口径用。
        var statusWord: String
    }

    /// 一天在灯条里的状态。
    enum DayState {
        case normal     // 在 feed 覆盖范围内、那天没事
        case degraded   // 那天落在降级事件里（黄）
        case partial    // 那天落在部分中断事件里（橙）
        case uncovered  // feed 覆盖不到那天（更淡的灰，不假装正常）
    }

    struct DayCell {
        var offset: Int
        var state: DayState
        var ongoing: Bool
        var incident: Incident?
    }

    static let shared = ServiceStatus()

    @Published private(set) var event: FeedEvent?
    /// 最近这批 entry 折出来的事故，新的在前。灯条按天落事件就用它（2026-11-07 改）。
    @Published private(set) var incidents: [Incident] = []
    /// feed 里最早一条 entry 的时间：比它早的日子算「覆盖不到」，灯条上给更淡的灰。
    @Published private(set) var coverageStart: Date?
    /// feed 这一次有没有读到。false 不代表服务有问题——可能只是这台机器到状态页的路不通，
    /// 所以它不进面板文案，只给 --status-live 取证用。
    @Published private(set) var feedReadable = false
    /// 官方有进行中事件、且通知这条路走不通时置 true：菜单栏那颗灯变红（绿=闲时、黄=高峰、红=服务出问题）。
    @Published private(set) var serviceAlert = false
    /// 最近 60 分钟的本机探测（主线程读写：余额回调本来就在主线程）。
    @Published private(set) var probes: [Probe] = []

    /// 通知授权实测过拿不到时置 true：之后不再反复弹授权，直接走灯变红的降级。
    private(set) var notificationsUnavailable = false
    /// 自检（--probe --status-live）置 false：自检不该替用户发系统通知。
    var notificationsEnabled = true

    private var timer: Timer?
    private var fetching = false
    /// 至少完整试过一次（成功或失败都算）：--status-live 靠它判断「等够了没有」。
    @Published private(set) var attemptedOnce = false
    /// 下一次拉 feed 的最早时间。失败退让：60 → 120 → … → 600 封顶；成功重置回 600。
    private var nextAttempt = Date.distantPast
    private var backoff: TimeInterval = 60
    /// 发过通知的事件 id：同一个事件不重复提醒；事件翻成 resolved 不发「恢复」通知。
    private var notifiedEventID: String?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil // feed 内容只在内存里，跟余额那套同一规矩
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - 生命周期

    func start() {
        refreshIfNeeded()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshIfNeeded()
        }
    }

    /// 到点才拉。退让节奏全在 nextAttempt / backoff 两个字段里。
    func refreshIfNeeded() {
        guard !fetching, Date() >= nextAttempt else { return }
        fetching = true
        var request = URLRequest(url: URL(string: "https://status.deepseek.com/feed.atom")!)
        request.timeoutInterval = 8
        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            // 解析放后台：XMLParser 对 17KB 的 feed 不慢，但主线程一行都不多占。
            let parsed = Self.parse(data)
            DispatchQueue.main.async {
                self.fetching = false
                self.attemptedOnce = true
                if let entries = parsed, let event = entries.first {
                    self.feedReadable = true
                    self.backoff = 600
                    self.nextAttempt = Date().addingTimeInterval(600)
                    self.event = event
                    self.incorporate(entries)
                    self.notifyIfNeeded(event)
                    self.clearAlertIfResolved(event)
                } else {
                    self.feedReadable = false
                    // 失败先 1 分钟，再翻倍到 10 分钟封顶；读不到时不动 event，面板照常写本机实测。
                    self.backoff = min(600, self.backoff * 2)
                    self.nextAttempt = Date().addingTimeInterval(self.backoff)
                }
            }
        }.resume()
    }

    // MARK: - 本机探测

    /// 余额每次取完记一笔。ok 的口径：这条请求本身走通了（error == nil 才算；
    /// 没 API Key 是配置问题，不该算「服务不行」）。
    func recordProbe(ok: Bool, ms: Double) {
        var next = probes
        next.append(Probe(at: Date(), ok: ok, ms: ms))
        // 只留最近 60 分钟，最多 120 条：面板那句话的口径就是「最近 1 小时」。
        let cutoff = Date().addingTimeInterval(-3600)
        next = next.filter { $0.at >= cutoff }
        if next.count > 120 { next = Array(next.suffix(120)) }
        probes = next
    }

    /// 没有官方事件时看本机：最近 15 分钟有失败、或单次超过 8 秒，就算「波动」。
    var jitterVisible: Bool {
        let cutoff = Date().addingTimeInterval(-15 * 60)
        let recent = probes.filter { $0.at >= cutoff }
        return recent.contains { !$0.ok || $0.ms > 8000 }
    }

    // MARK: - 通知

    private func notifyIfNeeded(_ event: FeedEvent) {
        // resolved 不发（恢复正常不发），同一事件只发一次。
        guard event.status != "resolved", notifiedEventID != event.id else { return }
        notifiedEventID = event.id
        serviceAlert = true
        guard notificationsEnabled else { return }
        if notificationsUnavailable { return }
        // 先探 bundle：UNUserNotificationCenter 在无 bundle 的裸二进制上会直接抛异常（--probe 就是这样跑的）。
        guard Bundle.main.bundleIdentifier != nil else {
            notificationsUnavailable = true
            return
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    // 拿不到授权：降级成灯变红，不许静默失败——serviceAlert 已经置了，这里只记结论。
                    self.notificationsUnavailable = true
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = Lang.current == .zh ? "DeepSeek 服务事件" : "DeepSeek service event"
                content.body = event.title
                let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
                center.add(request)
            }
        }
    }

    /// 事件翻成 resolved：灯回到原色。resolved 状态下一次刷新时顺手清。
    private func clearAlertIfResolved(_ event: FeedEvent) {
        if event.status == "resolved" { serviceAlert = false }
    }

    // MARK: - 30 天灯条

    /// 最近 30 天，一天一格：那天落在哪个事件里、覆盖到了没。
    /// 天的边界按 PeakHours.timeZone（北京）切，跟面板上「今天」是同一套日历。
    func dayCells(count: Int = 30) -> [DayCell] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PeakHours.timeZone
        var cells: [DayCell] = []
        for offset in 0..<count {
            let day = calendar.startOfDay(for: PeakHours.daysBefore(offset))
            let covered = coverageStart.map { day >= calendar.startOfDay(for: $0) } ?? false
            // 一天落多个事件时取最严重的那档（partial > degraded），不是后解析到的覆盖前面的
            // （2026-11-07 实测：同一天有「性能下降」和「部分中断」两条，first 会按 feed 顺序摆错）。
            var hit: Incident?
            var worstRank = 0
            for incident in incidents {
                let end = incident.ongoing ? Date() : incident.end
                guard calendar.startOfDay(for: incident.start) <= day,
                      day <= calendar.startOfDay(for: end) else { continue }
                let rank = incident.severity == "partial" ? 2 : 1
                if rank > worstRank {
                    worstRank = rank
                    hit = incident
                }
            }
            let state: DayState
            if let hit {
                state = hit.severity == "partial" ? .partial : .degraded
            } else {
                state = covered ? .normal : .uncovered
            }
            cells.append(DayCell(offset: offset, state: state,
                                 ongoing: hit?.ongoing ?? false, incident: hit))
        }
        return cells
    }

    /// 截图用假事件：只走 --probe --demo / TapCheck 这条数据路径，真 feed 一行不碰。
    /// 三个事件错开日子，灯条上才有橙有黄；coverageStart 铺满 30 天，其余格子给淡绿而不是灰。
    func loadDemoIncidents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PeakHours.timeZone
        func at(_ offset: Int) -> Date {
            calendar.startOfDay(for: PeakHours.daysBefore(offset)).addingTimeInterval(14 * 3600)
        }
        func incident(offset: Int, title: String, severity: String) -> Incident {
            let moment = at(offset)
            return Incident(id: "demo-\(offset)", title: title, start: moment, end: moment,
                            ongoing: false, severity: severity, statusWord: "resolved")
        }
        incidents = [
            incident(offset: 3, title: "DeepSeek 网页/API 性能下降", severity: "degraded"),
            incident(offset: 11, title: "DeepSeek 网页 部分中断", severity: "partial"),
            incident(offset: 24, title: "DeepSeek 网页/API 性能下降", severity: "degraded"),
        ]
        coverageStart = at(29)
    }

    /// entry 折事故（2026-11-07）：按 id 分组，最早 updated = 开始、最晚 = 更新，
    /// 最晚一条不是 resolved 就算进行中。feed 只覆盖最近两个多月，更早的日子靠 coverageStart 露馅。
    private func incorporate(_ entries: [FeedEvent]) {
        var byID: [String: [FeedEvent]] = [:]
        for entry in entries {
            byID[entry.id, default: []].append(entry)
        }
        let built = byID.values.map { group -> Incident in
            let sorted = group.sorted { $0.updated < $1.updated }
            let latest = sorted[sorted.count - 1]
            let status = latest.status.isEmpty ? "unknown" : latest.status
            return Incident(id: latest.id, title: latest.title,
                            start: sorted[0].updated, end: latest.updated,
                            ongoing: status != "resolved",
                            severity: Self.severity(of: latest.title),
                            statusWord: status)
        }
        incidents = built.sorted { $0.start > $1.start }
        coverageStart = entries.map(\.updated).min()
    }

    /// feed 没给严重级字段，从标题认：部分中断 → 橙，降级 → 黄，认不出按降级算（宁可标浅）。
    private static func severity(of title: String) -> String {
        if title.contains("部分中断") || title.lowercased().contains("outage") { return "partial" }
        return "degraded"
    }

    // MARK: - feed 解析

    /// 全部 entry（最新在最前）：灯条要铺 30 天，只留一条不够。
    private static func parse(_ data: Data?) -> [FeedEvent]? {
        guard let data else { return nil }
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard !delegate.events.isEmpty else { return nil }
        return delegate.events.map { event in
            var event = event
            if event.status.isEmpty { event.status = "unknown" }
            return event
        }
    }

    private final class FeedParser: NSObject, XMLParserDelegate {
        var events: [FeedEvent] = []
        private var inEntry = false
        private var currentElement = ""
        private var text = ""
        private var title = ""
        private var link = ""
        private var updatedText = ""
        private var summary = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            currentElement = name
            text = ""
            if name == "entry" {
                inEntry = true
                title = ""; link = ""; updatedText = ""; summary = ""
            } else if inEntry, name == "link", link.isEmpty {
                link = attributes["href"] ?? ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inEntry else { return }
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard inEntry else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "title" where title.isEmpty: title = trimmed
            case "updated": updatedText = trimmed
            case "summary": summary = trimmed
            case "entry":
                // summary 是转义过的 HTML（"…<strong>Status:</strong> monitoring…"），
                // XMLParser 已把实体还原，这里一个正则把状态抠出来。
                let status = Self.status(in: summary)
                let date = Self.date(from: updatedText) ?? Date()
                events.append(FeedEvent(id: link.isEmpty ? updatedText : link,
                                        title: title, updated: date, status: status))
                inEntry = false
            default: break
            }
        }

        private static func status(in summary: String) -> String {
            guard let range = summary.range(of: "Status:</strong>") else { return "" }
            let tail = summary[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let word = tail.prefix { $0.isLetter }
            return word.lowercased()
        }

        /// "2026-11-07T15:56:12+08:00"，个别条目带小数秒，两种格式都试。
        private static func date(from text: String) -> Date? {
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: text) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: text)
        }
    }
}
