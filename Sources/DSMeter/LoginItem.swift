import Foundation

/// 开机自启：写一个 LaunchAgent（`~/Library/LaunchAgents`），由系统在登录时拉起。
/// 不用 SMAppService——它要求签名和队伍匹配，开发签名会被拒；LaunchAgent 只要路径对就稳。
enum LoginItem {
    static let label = "app.dsmeter.macos"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    static func enable() -> Bool {
        let appPath = "/Applications/DS Meter.app"
        let executable = "\(appPath)/Contents/MacOS/DSMeter"
        guard FileManager.default.fileExists(atPath: executable) else { return false }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array><string>\(executable)</string></array>
            <key>RunAtLoad</key><true/>
            <key>ProcessType</key><string>Interactive</string>
            <key>LimitLoadToSessionType</key><string>Aqua</string>
        </dict>
        </plist>
        """
        let directory = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? plist.data(using: .utf8)?.write(to: plistURL, options: .atomic)) != nil else { return false }
        reload()
        return true
    }

    /// 开关存一处：菜单勾选和设置里的开关都走这里，别各写一份 UserDefaults。
    static func setEnabled(_ enabled: Bool) {
        if enabled { enable() } else { disable() }
        UserDefaults.standard.set(enabled, forKey: "autoStart")
    }

    static func disable() {
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    /// 重新加载一次：改了 plist（比如应用换了路径）之后让系统重新读。
    private static func reload() {
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
