import Foundation
import Security

/// 账号绑定：API Key 读余额，平台控制台 token 读用量。
///
/// 存哪儿：`~/Library/Application Support/DSMeter/account.json`，目录 0700、文件 0600，只有本用户能读。
/// 为什么不用钥匙串：每次重编 app 签名都变，钥匙串会认不出同一个 app，读一次就弹一次密码框。
enum Account {
    /// 老版本把两串凭据放在登录钥匙串里的服务名，只用来搬家。
    private static let legacyService = "app.deepseekmeter.macos"

    /// 自检用：假装这台机器什么都没存（截「第一次打开」那屏）。
    static var ignoreStoredCredentials = false

    static var apiKey: String? {
        if ignoreStoredCredentials { return nil }
        if let stored = stored()["apiKey"], !stored.isEmpty { return stored }
        return envKey()
    }

    static var consoleToken: String? {
        if ignoreStoredCredentials { return nil }
        guard let token = stored()["consoleToken"], !token.isEmpty else { return nil }
        // 旧版登录窗口误存过站点未登录时写的空壳（{"value":null,...}），别把它当 token 发出去。
        if token.hasPrefix("{\"value\":null") { return nil }
        return token
    }

    /// 界面上要显示这两个数是从哪来的，别让人以为已经存好了。
    static var apiKeyOrigin: String {
        if ignoreStoredCredentials { return T.notSet.s }
        if let value = stored()["apiKey"], !value.isEmpty { return T.savedState.s }
        if envKey() != nil { return T.fromEnv.s }
        return T.notSet.s
    }

    static var consoleTokenOrigin: String {
        if ignoreStoredCredentials { return T.notSet.s }
        if let value = stored()["consoleToken"], !value.isEmpty { return T.savedState.s }
        return T.notSet.s
    }

    static func save(apiKey: String, consoleToken: String) {
        var values = stored()
        values["apiKey"] = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        values["consoleToken"] = consoleToken.trimmingCharacters(in: .whitespacesAndNewlines)
        write(values)
    }

    /// 登录窗口读到 token 就直接存，不用再点一次保存。
    static func saveConsoleToken(_ token: String) {
        var values = stored()
        values["consoleToken"] = token.trimmingCharacters(in: .whitespacesAndNewlines)
        write(values)
    }

    /// 退出网页登录：存下来的那串 token 也一起清掉。
    static func forgetConsoleToken() {
        var values = stored()
        values["consoleToken"] = ""
        write(values)
    }

    /// 撤回授权：两串凭据都删掉，app 立刻只剩「没绑定」状态。
    static func forget() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 启动时搬一次旧账：老名字（DeepSeek Meter）那个目录里的凭据搬过来，别让升级丢掉 key。
    /// 再从钥匙串搬一次更早版本留下的两串（搬完就删，之后不再读）。
    static func migrateIfNeeded() {
        moveFromOldName()
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }

        var values: [String: String] = [:]
        if let key = keychainGet("apiKey"), !key.isEmpty { values["apiKey"] = key }
        if let token = keychainGet("consoleToken"), !token.isEmpty { values["consoleToken"] = token }
        guard !values.isEmpty else { return }
        write(values)
        if values["apiKey"] != nil { keychainDelete("apiKey") }
        if values["consoleToken"] != nil { keychainDelete("consoleToken") }
    }

    /// 改名前那版把凭据放在 Application Support/DeepSeekMeter 下；第一次跑新名字时挪过来。
    private static func moveFromOldName() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("DeepSeekMeter/account.json")
        guard
            !FileManager.default.fileExists(atPath: fileURL.path),
            FileManager.default.fileExists(atPath: old.path)
        else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.moveItem(at: old, to: fileURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    // MARK: - 凭据文件

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DSMeter/account.json")
    }

    private static func stored() -> [String: String] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return object
    }

    private static func write(_ values: [String: String]) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func keychainQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: key,
        ]
    }

    private static func keychainGet(_ key: String) -> String? {
        var query = keychainQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    private static func keychainDelete(_ key: String) {
        SecItemDelete(keychainQuery(key) as CFDictionary)
    }

    private static func envKey() -> String? {
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty else { return nil }
        return key
    }
}
