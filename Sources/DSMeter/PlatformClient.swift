import Foundation

/// DeepSeek 开放平台的用量接口（platform.deepseek.com 后台自己用的那几个）。
/// 它不认 sk- 开头的 API key，只认浏览器登录后的 userToken，所以 token 在设置里单独绑定。
enum PlatformClient {
    static let timeZoneSeconds = 28_800 // +08:00

    // MARK: - 某一天：每小时花了多少、每个模型花了多少、缓存命中

    /// 一天的账单。offset = 0 今天、1 昨天；两天走同一套取法，界面上换个日就是换个 offset。
    /// 金额接口失败就算失败；token 接口失败不影响金额（只是那天的模型列表摆不出来）。
    static func fetchDay(offset: Int, completion: @escaping (Result<DayBill, PlatformError>) -> Void) {
        let (start, end) = dayWindow(offset: offset)
        get(endpoint("api/v0/usage/by_api_key/cost", start: start, end: end)) { data in
            switch decode(data, as: CostPayload.self) {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                let currency = payload.data.first { $0.currency == "CNY" } ?? payload.data.first
                var bill = DayBill()
                for series in currency?.series ?? [] {
                    let name = series.model ?? T.modelOther.s
                    for bucket in series.buckets {
                        let value = Double(bucket.cost) ?? 0
                        let hour = PeakHours.hour(of: Date(timeIntervalSince1970: TimeInterval(bucket.time)))
                        bill.hours[hour] += value
                        bill.modelCost[name, default: 0] += value
                    }
                }
                get(endpoint("api/v0/usage/by_api_key/amount", start: start, end: end)) { data in
                    if case .success(let payload) = decode(data, as: AmountPayload.self) {
                        for series in payload.series {
                            var totals = TokenTotals()
                            for bucket in series.buckets {
                                totals.requests += bucket.usage.request
                                totals.miss += bucket.usage.miss
                                totals.hit += bucket.usage.hit
                                totals.response += bucket.usage.response
                                // 第二张柱状图用：按小时把三种 token 加起来（命中 + 未命中 + 输出），跨模型累加
                                let hour = PeakHours.hour(of: Date(timeIntervalSince1970: TimeInterval(bucket.time)))
                                bill.hourTokens[hour] += Double(bucket.usage.hit + bucket.usage.miss + bucket.usage.response)
                            }
                            bill.tokens[series.model ?? T.modelOther.s] = totals
                        }
                    }
                    completion(.success(bill))
                }
            }
        }
    }

    /// 平均值用的窗口。界面上的「近 N 天」直接用它，别两处各写一个数。
    static let averageWindowDays = 30

    /// 平台这两个接口一次最多给 30 天：35 天、36 天的窗口直接报错（2026-10-27 实测）。
    /// 所以日历也只摆这 30 天（4 整周 + 本周到现在）。
    static let calendarDays = 30

    struct Recent {
        /// calendarDays + 1 个数，老的在前面，最后一个 = 今天。
        var daily: [Double] = []
        /// 最近 30 天一共花了多少（跟日历上那些格子对得上，含今天）。
        var total: Double = 0
        /// 完整的那几天平均每天（估「还能撑多久」用，不含今天）。
        var average: Double = 0
    }

    static func fetchRecent(completion: @escaping (Result<Recent, PlatformError>) -> Void) {
        let days = calendarDays
        let end = todayWindow().end
        let start = todayWindow().start - days * 86_400
        get(endpoint("api/v0/usage/by_api_key/cost", start: start, end: end)) { data in
            completion(decode(data, as: CostPayload.self).map { payload in
                let currency = payload.data.first { $0.currency == "CNY" } ?? payload.data.first
                var daily = Array(repeating: 0.0, count: days + 1)
                for series in currency?.series ?? [] {
                    for bucket in series.buckets {
                        let index = (bucket.time - start) / 86_400
                        guard index >= 0, index <= days else { continue }
                        daily[index] += Double(bucket.cost) ?? 0
                    }
                }
                // 今天没过完，算进平均会压低：平均只用前面那 days 个完整天。
                let complete = daily[0..<days].reduce(0, +)
                // 一共多少用日历上那 30 格（含今天），跟用户看到的格子一一对应。
                let shown = daily.dropFirst().reduce(0, +)
                return Recent(daily: daily, total: shown, average: complete / Double(days))
            })
        }
    }

    // MARK: - 近 7 天合计（菜单里看，每 10 分钟刷一次就够）

    static func fetchWeekCost(completion: @escaping (Result<Double, PlatformError>) -> Void) {
        let start = todayWindow().start - 6 * 86_400
        let end = todayWindow().end
        get(endpoint("api/v0/usage/by_api_key/cost", start: start, end: end)) { data in
            completion(decode(data, as: CostPayload.self).map { payload in
                let currency = payload.data.first { $0.currency == "CNY" } ?? payload.data.first
                return (currency?.series ?? []).reduce(0.0) { total, series in
                    total + series.buckets.reduce(0.0) { $0 + (Double($1.cost) ?? 0) }
                }
            })
        }
    }

    /// 候选 token 能不能读账单：能读才算登录成功。登录窗口只用它来防「未登录时站点写的空壳」。
    static func verify(token: String, completion: @escaping (Bool) -> Void) {
        let (start, end) = dayWindow(offset: 0)
        var request = URLRequest(url: endpoint("api/v0/usage/by_api_key/cost", start: start, end: end))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        session.dataTask(with: request) { data, _, _ in
            var ok = false
            if
                let data,
                let envelope = try? JSONDecoder().decode(Envelope<CostPayload>.self, from: data),
                envelope.code == 0,
                envelope.data?.biz_data != nil
            {
                ok = true
            }
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    // MARK: - 数据形状

    /// 一天的账单：24 小时的金额、分模型的金额、分模型的 token 量。
    struct DayBill {
        var hours: [Double] = Array(repeating: 0, count: 24)
        /// 每小时的 token 量（命中 + 未命中 + 输出，跨模型）
        var hourTokens: [Double] = Array(repeating: 0, count: 24)
        var modelCost: [String: Double] = [:]
        var tokens: [String: TokenTotals] = [:]
    }

    struct TokenTotals {
        var requests = 0
        var miss = 0
        var hit = 0
        var response = 0
    }

    // MARK: - 底层

    private static func todayWindow() -> (start: Int, end: Int) { dayWindow(offset: 0) }

    /// offset = 0 今天、1 昨天：北京时区的整天窗口 [0:00, 24:00)。
    private static func dayWindow(offset: Int) -> (start: Int, end: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PeakHours.timeZone
        let day = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        let start = calendar.startOfDay(for: day)
        return (Int(start.timeIntervalSince1970), Int(start.addingTimeInterval(86_400).timeIntervalSince1970))
    }

    private static func endpoint(_ path: String, start: Int, end: Int) -> URL {
        URL(string: "https://platform.deepseek.com/\(path)?start=\(start)&end=\(end)&tz=\(timeZoneSeconds)")!
    }

    /// 临时会话 + 关掉磁盘缓存：账单响应只在内存里，不落到 ~/Library/Caches。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private static func get(_ url: URL, completion: @escaping (Data?) -> Void) {
        guard let token = Account.consoleToken else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        session.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async { completion(data) }
        }.resume()
    }

    private static func decode<T: Decodable>(_ data: Data?, as type: T.Type) -> Result<T, PlatformError> {
        guard let data else { return .failure(.noToken) }
        guard let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data) else {
            return .failure(.badResponse)
        }
        if envelope.code == 40003 || envelope.code == 401 { return .failure(.tokenExpired) }
        guard envelope.code == 0, let payload = envelope.data?.biz_data else {
            return .failure(.badResponse)
        }
        return .success(payload)
    }

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let data: Wrapper?
        struct Wrapper: Decodable { let biz_data: T? }
    }

    private struct CostPayload: Decodable {
        struct Bucket: Decodable { let time: Int; let cost: String }
        struct Series: Decodable { let model: String?; let buckets: [Bucket] }
        struct Currency: Decodable { let currency: String; let series: [Series] }
        let data: [Currency]
    }

    private struct AmountPayload: Decodable {
        struct Usage: Decodable {
            let request: Int
            let hit: Int
            let miss: Int
            let response: Int

            private enum CodingKeys: String, CodingKey {
                case request = "REQUEST"
                case hit = "PROMPT_CACHE_HIT_TOKEN"
                case miss = "PROMPT_CACHE_MISS_TOKEN"
                case response = "RESPONSE_TOKEN"
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                request = (try? c.decodeIfPresent(Int.self, forKey: .request)) ?? 0
                hit = (try? c.decodeIfPresent(Int.self, forKey: .hit)) ?? 0
                miss = (try? c.decodeIfPresent(Int.self, forKey: .miss)) ?? 0
                response = (try? c.decodeIfPresent(Int.self, forKey: .response)) ?? 0
            }
        }
        struct Bucket: Decodable { let time: Int; let usage: Usage }
        struct Series: Decodable { let model: String?; let buckets: [Bucket] }
        let series: [Series]
    }
}

/// 取不到用量时区分三种：没绑 token / token 过期（这两种能自动修）/ 其它。
enum PlatformError: LocalizedError {
    case noToken
    case tokenExpired
    case badResponse

    var needsToken: Bool {
        switch self {
        case .noToken, .tokenExpired: return true
        case .badResponse: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .noToken: return T.noToken.s
        case .tokenExpired: return T.tokenExpired.s
        case .badResponse: return T.platformUnreadable.s
        }
    }
}
