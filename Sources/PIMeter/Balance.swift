import Foundation

struct BalanceState {
    var amount: Double?
    var fetchedAt: Date?
    var error: String?
}

struct BalanceResponse: Decodable {
    struct Info: Decodable {
        let currency: String
        let total_balance: String
    }
    let is_available: Bool
    let balance_infos: [Info]
}

enum BalanceClient {
    /// 关掉磁盘缓存：余额响应只在内存里。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    static func fetch(completion: @escaping (BalanceState) -> Void) {
        guard let key = Account.apiKey else {
            completion(BalanceState(amount: nil, fetchedAt: nil, error: T.noApiKey.s))
            return
        }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        session.dataTask(with: request) { data, _, transportError in
            var state: BalanceState
            if
                let data,
                let decoded = try? JSONDecoder().decode(BalanceResponse.self, from: data),
                let info = decoded.balance_infos.first(where: { $0.currency == "CNY" }) ?? decoded.balance_infos.first,
                let value = Double(info.total_balance)
            {
                state = BalanceState(amount: value, fetchedAt: Date(), error: nil)
            } else {
                state = BalanceState(amount: nil, fetchedAt: nil, error: transportError == nil ? T.balanceUnreadable.s : T.networkError.s)
            }
            DispatchQueue.main.async { completion(state) }
        }.resume()
    }
}
