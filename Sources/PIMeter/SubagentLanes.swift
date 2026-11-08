import SwiftUI

/// 子线程的每条来源：名字、根目录、认哪些行、免费还是计费、颜色。
/// **子线程的定义：跳到 pi 之外的那个 Agent 里跑掉的调用**（Claude Code 是第一种）。
/// pi 自己的原生子代理不算——它们跑在 pi 里面、钱记在同一张 DeepSeek 账单上，也没跳出这一层。
///
/// 以后加一条新来源（别的外部 Agent），只往 `all` 里加一条定义、再给它一个 `Kind` case，
/// 面板逻辑不用动：每一来源各自一排细柱、各自一行字，各自归集。
///
/// 口径总注（从 ClaudeCode.swift 整段搬来）：
///
/// Claude Code（免费 / 订阅）——扫本机 `~/.claude/projects/**/*.jsonl`，按北京日、按小时数出来。
/// 那些调用走年费订阅、一分钱不花（¥0），面板上只回答一个问题：它替 DeepSeek 账单分担了多少。
/// 1) 递归扫全部 .jsonl（里面有 subagents/、subagents/workflows/ 子目录）；
/// 2) 只认 `type == "assistant"` 的行，token 取 message.usage（这里只用次数）；
/// 3) 按 message.id 全局去重——同一个 id 在文件里会重复出现（流式重复），
///    实测不去重会多算 2.28 倍（6366 对 2792）；
/// 4) 时间用行里的 timestamp（UTC）按北京时区（+8）切天切小时，不用文件 mtime；
/// 5) 模型分类：`deepseek*` 不算子线程（那半已经记在 DeepSeek 账单里，不能重复计）；
///    `<synthetic>` 是客户端本地块，直接跳过；其余（glm-*、claude-*、未知）都算子线程。
///
/// 只读本地文件，不发请求、不写日志。按（路径, mtime, size）缓存每个文件解析出的桶，
/// refresh 只重解析变了的文件。
struct SubagentLane: Identifiable {
    enum Kind {
        /// Claude Code 的行格式与去重规则（见上）。
        case claudeCode
    }

    let id: String
    /// 家目录下的相对路径，各来源各扫各的根。
    let root: String
    /// true = 这些调用已在 DeepSeek 账单里：钱栏写「已在账单」，不算占比。
    let billed: Bool
    let kind: Kind

    var title: String {
        switch kind {
        case .claudeCode: return T.laneCC.s
        }
    }

    var help: String {
        switch kind {
        case .claudeCode: return T.subagentHelp.s
        }
    }

    /// 这个路径算不算。
    func matches(_ path: String) -> Bool {
        switch kind {
        case .claudeCode:
            return true
        }
    }

    static let all: [SubagentLane] = [
        SubagentLane(
            id: "cc", root: ".claude/projects", billed: false, kind: .claudeCode
        ),
    ]
}

/// 一条来源的日志扫描与聚合。结构跟原 ClaudeCodeLog 一致，只是根目录、认行、去重按 lane 走。
final class SubagentLog {
    struct Day {
        var calls = 0
        /// 命中：cache_read_input_tokens（计价按命中价）。
        var hitTokens = 0
        /// 未命中：input + cache_creation（DeepSeek 不收缓存写入费，新写的按未命中价算，偏保守）。
        var missTokens = 0
        /// 输出：output_tokens（Anthropic 把 thinking 放在 output 里）。
        var outTokens = 0
        /// token 总量：hit + miss + out（跟基准脚本同口径，柱子、占比、probe 都用它）。
        var tokens: Int { hitTokens + missTokens + outTokens }
        var hours = [Int](repeating: 0, count: 24)
        /// 每小时多少 token。柱子上画的是这个，不是次数：他 2026-11-07 明确要「token 数，不是调用次数」。
        var hourTokens = [Int](repeating: 0, count: 24)
        /// 每小时的命中 / 未命中 / 输出：闲时高峰按小时判，计价不能拿整天平均价。
        var hourHit = [Int](repeating: 0, count: 24)
        var hourMiss = [Int](repeating: 0, count: 24)
        var hourOut = [Int](repeating: 0, count: 24)
        /// CC 自带联网工具（WebSearch / WebFetch）的次数：走订阅、不进 DeepSeek 账单，单列不并进 calls。
        /// 口径同 /tmp/ref_ccweb.py：type=="assistant" 行里 message.content[] 的 tool_use 块，
        /// 按（message.id, tool_use.id）全局去重，与 token 那套按 message.id 的去重互不相干。
        var webCalls = 0
        /// 走 DeepSeek key 的检索脚本（Bash 里调 search.py / fetch.py）：已在账单里，单独存，不并进 webCalls。
        var searchViaDS = 0
        /// 每小时多少次自带联网：这轮先不画柱子，留给自检对拍和以后画。
        var hourWeb = [Int](repeating: 0, count: 24)
    }

    /// 一个文件解析完的全部结果：桶 + 它贡献的那些 id（去重要跨文件看时缓存里得留着）。
    private struct FileCache {
        var modified: Date
        var size: Int
        var days: [String: Day]
        var ids: Set<String>
        /// 联网工具的去重键（message.id|tool_use.id），跟 token 那套分开。
        var webIds: Set<String>
    }

    let lane: SubagentLane

    init(lane: SubagentLane) {
        self.lane = lane
    }

    /// cc 是全局按 message.id 去重（id 在文件间重复才算同一次）；pi 是按（文件, id）去重，
    /// 跨文件同 id 不冲突，所以 pi 不看全局集。
    private var dedupAcrossFiles: Bool { lane.kind == .claudeCode }

    private var cache: [String: FileCache] = [:]
    /// 北京日 "yyyy-MM-dd" → 那天的桶。
    private var days: [String: Day] = [:]
    private(set) var loaded = false
    private var loading = false
    /// `days` / `cache` 在扫描那个后台队列上写，面板在主线程读；字典不是线程安全的，读写都过这把锁。
    private let lock = NSLock()
    /// 扫完（含增量）回调一次，Meter 拿它把数并进 snap。
    var onChange: (() -> Void)?
    private lazy var queue = DispatchQueue(label: "pimeter.subagent.scan.\(lane.id)", qos: .utility)

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = PeakHours.timeZone
        return formatter
    }()

    /// 那个偏移（0 = 今天）对应的北京日 key。
    static func key(offset: Int, from date: Date = Date()) -> String {
        dayFormatter.string(from: PeakHours.daysBefore(offset, from: date))
    }

    /// 手上这份快照：31 个桶，拷一份比让面板去猜「扫描写完没有」便宜得多。
    private func snapshot() -> [String: Day] {
        lock.lock()
        defer { lock.unlock() }
        return days
    }

    /// 看某天的桶；那天一条都没有就给 nil（面板据此整排不摆）。
    func day(offset: Int) -> Day? {
        snapshot()[Self.key(offset: offset)]
    }

    /// 近 30 天每天多少次（heatmap 对照用），偏移 → 次数。
    func dailyCalls() -> [Int: Int] {
        let today = snapshot()
        var result: [Int: Int] = [:]
        for offset in 0...30 {
            let key = Self.key(offset: offset)
            if let day = today[key], day.calls > 0 {
                result[offset] = day.calls
            }
        }
        return result
    }

    /// 有没有任何一天的数（一个文件都没有时面板整排、整行都不出现）。
    var isEmpty: Bool {
        snapshot().values.allSatisfy { $0.calls == 0 }
    }

    /// 平时走这条：后台扫，扫完在主线程回调。
    func refreshAsync() {
        guard !loading else { return }
        loading = true
        queue.async { [weak self] in
            guard let self else { return }
            self.scan()
            DispatchQueue.main.async {
                self.loading = false
                self.loaded = true
                self.onChange?()
            }
        }
    }

    /// 自检（--probe）走这条：当前线程扫完再画图。
    func loadSynchronously() {
        scan()
        loaded = true
    }

    // MARK: - 扫描

    private func scan() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(lane.root, isDirectory: true)
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var paths: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" && lane.matches(url.path) {
            paths.append(url.path)
        }
        // 去重是全局按顺序的：同一个 id 先出现在哪个文件，账就记在哪个文件那次。
        // 固定按路径排序，增量和全量走同一套顺序，两边的数才一致。
        paths.sort()

        var seen = Set<String>()
        var seenWeb = Set<String>()
        var merged: [String: Day] = [:]
        var nextCache: [String: FileCache] = [:]
        for path in paths {
            let attributes = (try? manager.attributesOfItem(atPath: path)) ?? [:]
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            let size = (attributes[.size] as? Int) ?? 0
            if let cached = cache[path], cached.modified == modified, cached.size == size {
                for (key, day) in cached.days {
                    merge(day, into: &merged[key])
                }
                if dedupAcrossFiles {
                    seen.formUnion(cached.ids)
                    seenWeb.formUnion(cached.webIds)
                }
                nextCache[path] = cached
                continue
            }
            let parsed = parseFile(path: path, seen: &seen, seenWeb: &seenWeb)  // 顺带把新 id 并进全局 seen
            for (key, day) in parsed.days {
                merge(day, into: &merged[key])
            }
            nextCache[path] = FileCache(modified: modified, size: size, days: parsed.days, ids: parsed.ids, webIds: parsed.webIds)
        }
        lock.lock()
        cache = nextCache
        days = merged
        lock.unlock()
    }

    private func merge(_ day: Day, into target: inout Day?) {
        if target == nil { target = Day() }
        target!.calls += day.calls
        target!.hitTokens += day.hitTokens
        target!.missTokens += day.missTokens
        target!.outTokens += day.outTokens
        for hour in 0..<24 {
            target!.hours[hour] += day.hours[hour]
            guard day.hourTokens[hour] > 0 else { continue }
            target!.hourTokens[hour] += day.hourTokens[hour]
            target!.hourHit[hour] += day.hourHit[hour]
            target!.hourMiss[hour] += day.hourMiss[hour]
            target!.hourOut[hour] += day.hourOut[hour]
        }
        target!.webCalls += day.webCalls
        target!.searchViaDS += day.searchViaDS
        for hour in 0..<24 where day.hourWeb[hour] > 0 {
            target!.hourWeb[hour] += day.hourWeb[hour]
        }
    }

    /// 解析一个文件。`seen` / `seenWeb` 进出都是全局 id 集（只有 cc 用）：重复出现的行不计数，新 id 记进去给后面的文件用。
    private func parseFile(path: String, seen: inout Set<String>, seenWeb: inout Set<String>) -> (days: [String: Day], ids: Set<String>, webIds: Set<String>) {
        var result: [String: Day] = [:]
        var ids = Set<String>()
        var webIds = Set<String>()
        guard let raw = FileManager.default.contents(atPath: path),
              let text = String(data: raw, encoding: .utf8) else { return (result, ids, webIds) }
        var localSeen = Set<String>()
        var localSeenWeb = Set<String>()
        let priorSeen = seen  // 闭包里不能碰 inout 参数，先拷一份只读的
        let priorSeenWeb = seenWeb
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byLines) { line, _, _, _ in
            guard let line else { return }
            let parsed = Self.parseLine(line, kind: self.lane.kind)
            // 联网工具那套先记：不看模型（deepseek 的行里也可能调 Bash 脚本）、不看 usage 有没有，
            // 去重键也跟 token 那套分开——同一条 assistant 消息里并行发好几个 tool_use 是常态，全都要数。
            for tool in parsed.tools {
                if self.dedupAcrossFiles {
                    guard !priorSeenWeb.contains(tool.key), !localSeenWeb.contains(tool.key) else { continue }
                } else {
                    guard !localSeenWeb.contains(tool.key) else { continue }
                }
                localSeenWeb.insert(tool.key)
                webIds.insert(tool.key)
                guard let (bucket, hour) = Self.beijingBucket(parsed.timestamp) else { continue }
                var day = result[bucket] ?? Day()
                if tool.isWeb {
                    day.webCalls += 1
                    day.hourWeb[hour] += 1
                } else {
                    day.searchViaDS += 1
                }
                result[bucket] = day
            }
            guard let payload = parsed.line else { return }
            // cc：deepseek-* 那半已记在账单里、<synthetic> 是本地块，都不进子线程；pi 的模型照实记。
            if self.lane.kind == .claudeCode, !Self.countsAsSubagent(model: payload.model) { return }
            let key = payload.id ?? ""
            if self.dedupAcrossFiles {
                guard !priorSeen.contains(key), !localSeen.contains(key) else { return }
            } else {
                guard !localSeen.contains(key) else { return }
            }
            localSeen.insert(key)
            ids.insert(key)
            guard let (bucket, hour) = Self.beijingBucket(payload.timestamp) else { return }
            var day = result[bucket] ?? Day()
            day.calls += 1
            day.hitTokens += payload.hit
            day.missTokens += payload.miss
            day.outTokens += payload.out
            day.hours[hour] += 1
            day.hourTokens[hour] += payload.tokens
            day.hourHit[hour] += payload.hit
            day.hourMiss[hour] += payload.miss
            day.hourOut[hour] += payload.out
            result[bucket] = day
        }
        seen.formUnion(ids)
        seenWeb.formUnion(webIds)
        return (result, ids, webIds)
    }

    struct Line {
        var id: String?
        var model: String
        var timestamp: String?
        /// 该来源口径下的 token 总量。
        var tokens: Int
        /// 命中 / 未命中 / 输出三类，计价用（hit + miss + out == tokens）。
        var hit: Int
        var miss: Int
        var out: Int
    }

    /// 联网工具的一次命中：去重键（message.id|tool_use.id）+ 归哪路（true = 自带 web，false = 走 DeepSeek 的脚本）。
    struct ToolHit {
        let key: String
        let isWeb: Bool
    }

    /// 一行解析出来的全部东西：token 那条（可没有）+ 联网工具块（可多个）。JSON 只解析一次，两套口径共用。
    struct ParsedLine {
        var line: Line?
        var tools: [ToolHit]
        var timestamp: String?
    }

    /// 一行里要的字段。Claude Code：type=="assistant"，usage 的四项带 `_tokens` 后缀，
    /// id 取 message.id（缺了退顶层 uuid）。
    static func lineUsage(_ line: String, kind: SubagentLane.Kind) -> Line? {
        parseLine(line, kind: kind).line
    }

    static func parseLine(_ line: String, kind: SubagentLane.Kind) -> ParsedLine {
        var result = ParsedLine(line: nil, tools: [], timestamp: nil)
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return result }
        let message = dictionary["message"] as? [String: Any] ?? [:]
        result.timestamp = dictionary["timestamp"] as? String
        // 联网工具：只在 cc 的行里认（pi 没有 WebSearch/WebFetch 这套）。
        if kind == .claudeCode, dictionary["type"] as? String == "assistant" {
            let messageID = (message["id"] as? String) ?? ""
            if let content = message["content"] as? [Any] {
                for block in content {
                    guard let tool = block as? [String: Any], tool["type"] as? String == "tool_use" else { continue }
                    let name = tool["name"] as? String ?? ""
                    let input = tool["input"] as? [String: Any] ?? [:]
                    let isWeb: Bool
                    if name == "WebSearch" || name == "WebFetch" {
                        isWeb = true
                    } else if name == "Bash" {
                        let command = input["command"] as? String ?? ""
                        guard command.contains("search.py") || command.contains("fetch.py") else { continue }
                        isWeb = false
                    } else {
                        continue
                    }
                    result.tools.append(ToolHit(key: "\(messageID)|\(tool["id"] as? String ?? "")", isWeb: isWeb))
                }
            }
        }
        let usage: [String: Any]
        switch kind {
        case .claudeCode:
            guard dictionary["type"] as? String == "assistant" else { return result }
            usage = message["usage"] as? [String: Any] ?? [:]
            guard !usage.isEmpty else { return result }
        }
        func field(_ key: String) -> Int { usage[key] as? Int ?? 0 }
        let tokens: Int
        let hit: Int
        let miss: Int
        let out: Int
        switch kind {
        case .claudeCode:
            hit = field("cache_read_input_tokens")
            miss = field("input_tokens") + field("cache_creation_input_tokens")
            out = field("output_tokens")
            tokens = hit + miss + out
        }
        let id: String?
        switch kind {
        case .claudeCode:
            id = (message["id"] as? String) ?? (dictionary["uuid"] as? String)
        }
        result.line = Line(id: id,
                           model: message["model"] as? String ?? "",
                           timestamp: dictionary["timestamp"] as? String, tokens: tokens,
                           hit: hit, miss: miss, out: out)
        return result
    }

    /// 模型分类：deepseek* 已在账单、<synthetic> 是本地块，都不算子线程；其余都算。
    /// 同一条规则基准脚本在用，两边必须一字不差。
    static func countsAsSubagent(model: String) -> Bool {
        let name = model.lowercased()
        if name == "<synthetic>" { return false }
        if name.hasPrefix("deepseek") { return false }
        return true
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterWhole = ISO8601DateFormatter()

    /// timestamp（UTC）→（北京日 key，小时）。带不带毫秒都要认。
    static func beijingBucket(_ timestamp: String?) -> (String, Int)? {
        guard let timestamp else { return nil }
        let date = isoFormatter.date(from: timestamp) ?? isoFormatterWhole.date(from: timestamp)
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PeakHours.timeZone
        return (dayFormatter.string(from: date), calendar.component(.hour, from: date))
    }
}
