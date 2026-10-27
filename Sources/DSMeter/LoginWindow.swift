import AppKit
import WebKit

/// 登录：在 app 自己的窗口里打开 platform.deepseek.com，
/// 用户在网页里登录（手机验证码 / 密码 / 微信扫码都行），
/// 我们从同一个页面的 localStorage 里读 `userToken`——不需要 DevTools，也不需要浏览器调试端口。
///
/// 登录态留在 WKWebView 自己的数据目录（`~/Library/WebKit/app.dsmeter.macos`）：
/// token 过期时再点一次「登录网页读取」，通常还是登录状态，读到就走，不用重新输密码。
/// 不想要这层登录态就点「退出网页登录」，cookie 和 localStorage 一起清掉。
final class LoginWindow: NSObject, NSWindowDelegate {
    static let shared = LoginWindow()

    private var window: NSWindow?
    private var web: WKWebView?
    private var poll: Timer?
    private var onToken: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    /// 上一次验过的候选 token：同一个值只验一次，不刷接口。
    private var lastSeen: String?

    /// 打开登录窗口。读到 token 已经存好了，再回调。
    func present(onToken: @escaping (String) -> Void, onCancel: (() -> Void)? = nil) {
        self.onToken = onToken
        self.onCancel = onCancel
        let window = ensureWindow()
        if web?.url == nil { load() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
    }

    /// 退出网页登录：cookie、localStorage 全删。
    static func clearSession(completion: (() -> Void)? = nil) {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            DispatchQueue.main.async { completion?() }
        }
    }

    /// 自检用：当前网页标题（还没登录时给 --login-check 看页面到底开没开）。
    func pageTitle(_ completion: @escaping (String) -> Void) {
        web?.evaluateJavaScript("document.title + ' · ' + location.pathname") { value, _ in
            completion(value as? String ?? "(unavailable)")
        }
    }

    /// 自检用：把窗口里的网页存成 PNG（README 的登录图）。
    func snapshot(_ completion: @escaping (Data?) -> Void) {
        guard let web else { return completion(nil) }
        web.takeSnapshot(with: WKSnapshotConfiguration()) { image, _ in
            let png = image
                .flatMap { $0.tiffRepresentation }
                .flatMap { NSBitmapImageRep(data: $0) }
                .flatMap { $0.representation(using: .png, properties: [:]) }
            completion(png)
        }
    }

    // MARK: - 窗口

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let rect = NSRect(x: 0, y: 0, width: 480, height: 760)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = T.loginWindowTitle.s
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: rect, configuration: config)
        web.autoresizingMask = [.width, .height]
        window.contentView = web

        self.window = window
        self.web = web
        return window
    }

    private func load() {
        web?.load(URLRequest(url: URL(string: "https://platform.deepseek.com/usage")!))
    }

    // MARK: - 读 token

    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.readToken()
        }
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    private func readToken() {
        web?.evaluateJavaScript("JSON.stringify({p: location.pathname, t: localStorage.getItem('userToken')})") { [weak self] value, _ in
            guard let self, let page = Self.pageState(value) else { return }
            // 没登录的页面里，站点会写一个 {"value":null} 的空壳；这种不算 token。
            guard !page.path.contains("/sign_in"), let token = page.token, token != self.lastSeen else { return }
            self.lastSeen = token
            // 只有真能读到账单才算登录成功；否则继续等（也绝不会把空壳存进去）。
            PlatformClient.verify(token: token) { [weak self] ok in
                guard ok else { return }
                self?.finish(token)
            }
        }
    }

    private func finish(_ token: String) {
        Account.saveConsoleToken(token)
        stopPolling()
        window?.orderOut(nil)
        let callback = onToken
        onToken = nil
        callback?(token)
    }

    private struct PageState {
        var path: String
        var token: String?
    }

    private static func pageState(_ value: Any?) -> PageState? {
        guard
            let raw = value as? String,
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let path = object["p"] as? String ?? ""
        // 不用 Optional.flatMap：老一档的 Swift 编译器在这里推不出类型（CI 上就是栽在这行）。
        var parsed: String?
        if let stored = object["t"] as? String {
            parsed = token(from: stored)
        }
        return PageState(path: path, token: parsed)
    }

    /// 站点把 token 存成一个 JSON 字符串（`{"value":"..."}`），未登录时是 `{"value":null}`；
    /// 万一哪天改成裸串，也能认。
    private static func token(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null" else { return nil }
        guard trimmed.hasPrefix("{") else { return trimmed }
        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = object["value"] as? String,
            !token.isEmpty
        else { return nil }
        return token
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
        onToken = nil
        let cancel = onCancel
        onCancel = nil
        cancel?()
    }
}
