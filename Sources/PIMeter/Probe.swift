import AppKit
import SwiftUI
import UserNotifications

/// 命令行自检：把数字打出来，把面板存成 PNG。
///   PIMeter --probe [--snapshot 目录] [--status 目录]
///   PIMeter --probe --demo --snapshot 目录   假数据出图（不读凭据）
///   PIMeter --probe --login-check [--snapshot 目录]   打开登录窗口，看页面开没开
enum Probe {
    /// 出图倍数：`--scale N` 改，默认 2（retina）。
    private static var captureScale: CGFloat = 2

    /// 昨天同一时刻的未命中率：取不到就是 -1。写成函数是为了不在字典字面量里塞 Optional.flatMap。
    private static func yesterdayMissRate(_ snap: Snapshot) -> Double {
        guard let day = snap.days[1], let hit = day.hitRate else { return -1 }
        return 1 - hit
    }

    /// --status-live 里每天那格的日期（MM-dd）和状态名。面板灯条同一份，取证对照用。
    static func probeDayText(offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        formatter.timeZone = PeakHours.timeZone
        return formatter.string(from: PeakHours.daysBefore(offset))
    }

    static func probeStateName(_ state: ServiceStatus.DayState) -> String {
        switch state {
        case .normal: return "normal"
        case .degraded: return "degraded"
        case .partial: return "partial"
        case .uncovered: return "uncovered"
        }
    }

    static func run(arguments: [String]) -> Never {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        // 登录窗口自检：只打开、不登录（没有账号也不该替人登录），把页面存一张图。
        // 自检：那条 30 天开着的时候，在面板别处点一下，看它收没收。
        // 合成一次真点击走窗口（不是调函数），所以必须跑真的 NSApp.run：没起事件循环时
        // 窗口不是 key，SwiftUI 收不到点击（这个坑踩过，见 --tap 实现）。
        // 节假日判定的自检：五天五个期望（国庆 / 普通工作日 / 调休上班的周六 / 普通周五 / 表外的年份）。
        if arguments.contains("--probe-peak") {
            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            parser.timeZone = PeakHours.timeZone
            let cases: [(day: String, expect: String)] = [
                ("2026-10-01", "闲时"), // 周四，国庆
                ("2026-10-08", "高峰"), // 周四，普通工作日
                ("2026-02-14", "闲时"), // 周六，调休上班，仍是周末 → 闲时
                ("2026-11-06", "高峰"), // 周五，普通工作日
                ("2027-01-04", "高峰"), // 周一，表里没有 2027 → 退回星期几规则
            ]
            var failed = false
            for entry in cases {
                guard let date = parser.date(from: entry.day) else {
                    print("\(entry.day): 日期解析失败")
                    failed = true
                    continue
                }
                let peak = PeakHours.isPeak(hour: 10, weekday: PeakHours.weekday(of: date), day: entry.day)
                // 两条入口必须同答：带星期几的（账单、柱子）和带时刻的（灯、now）。
                let peakViaDate = PeakHours.isPeak(hour: 10, on: date)
                let actual = peak ? "高峰" : "闲时"
                let ok = actual == entry.expect && peakViaDate == peak
                failed = failed || !ok
                print("\(entry.day) 10:00 → \(actual)（期望 \(entry.expect)）\(ok ? "✓" : "✗")  灯那条入口：\(peakViaDate ? "高峰" : "闲时")")
            }
            print("holidaysStaleYear: \(PeakHours.holidaysStaleYear.map(String.init) ?? "nil")")
            exit(failed ? 5 : 0)
        }

        // 通知自检：必须用户手动跑这条命令才会走到这里（自启 / 菜单栏路径不经过 Probe），
        // 所以请求授权、弹测试通知都只发生在人主动调它的时候。
        if arguments.contains("--notify-check") {
            NotifyCheck.run()
        }

        if arguments.contains("--tap-check") {
            let point = arguments.firstIndex(of: "--tap-check").flatMap { index -> CGFloat? in
                guard index + 1 < arguments.count, let y = Double(arguments[index + 1]) else { return nil }
                return CGFloat(y)
            } ?? 240
            TapCheck.run(point: point)
            exit(0)
        }

        if arguments.contains("--login-check") {
            let dir: String? = arguments.firstIndex(of: "--snapshot").flatMap {
                $0 + 1 < arguments.count ? arguments[$0 + 1] : nil
            }
            LoginWindow.shared.present { found in
                print("{\"login\":\"token \(found.count) chars\"}")
                exit(0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                LoginWindow.shared.snapshot { png in
                    if let dir, let png {
                        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("login.png"))
                    }
                    LoginWindow.shared.pageTitle { title in
                        print("{\"login\":\"no token\",\"page\":\"\(title)\"}")
                        exit(3)
                    }
                }
            }
            NSApp.run()
            exit(3)
        }

        // 服务状态自检：feed 有没有读到、最新事件、本机探测样本。
        // 验收只认这条命令——同一台机器 curl 到 status.deepseek.com 会被 reset（000），
        // URLSession 却是 200，两条路结论相反，别拿 curl 当可达性判据。
        if arguments.contains("--status-live") {
            ServiceStatus.shared.notificationsEnabled = false // 自检不替用户发通知
            ServiceStatus.shared.refreshIfNeeded()
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline, !ServiceStatus.shared.attemptedOnce {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            let status = ServiceStatus.shared
            // JSON 一律走 JSONSerialization（2026-11-07）：手拼字符串不转义引号，
            // 事件标题里自带双引号时整段不是合法 JSON，json.load 直接报错。
            var payload: [String: Any] = [
                "feedRead": status.feedReadable,
                "probeCount": status.probes.count,
                "notificationsEnabled": status.notificationsEnabled,
                "probeSamples": status.probes.suffix(5).map { ["ok": $0.ok, "ms": Int($0.ms.rounded())] },
            ]
            if let event = status.event {
                payload["event"] = [
                    "title": event.title,
                    "status": event.status,
                    "updated": Fmt.clock(event.updated),
                    "minutes": Int(Date().timeIntervalSince(event.updated) / 60),
                ]
            } else {
                payload["event"] = NSNull()
            }
            // 最近 30 天一天一格（2026-11-07 灯条）：面板就是拿这份画的。
            payload["days"] = status.dayCells().map { cell in
                [
                    "date": Self.probeDayText(offset: cell.offset),
                    "state": Self.probeStateName(cell.state),
                    "ongoing": cell.ongoing,
                ] as [String: Any]
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                print(text)
            } else {
                print("{\"error\": \"status-live: JSONSerialization failed\"}")
            }
            fflush(stdout)
            exit(0)
        }

        let demo = arguments.contains("--demo")
        let fresh = arguments.contains("--fresh")
        // 出图倍数：默认 2（retina）。docs 里那张还要缩到 banner 里，用 3 才不糊（--scale 3）。
        if let index = arguments.firstIndex(of: "--scale"), index + 1 < arguments.count,
           let value = Double(arguments[index + 1]), value > 0 {
            captureScale = CGFloat(value)
        }
        if fresh { Account.ignoreStoredCredentials = true }
        let loggedOut = arguments.contains("--logged-out")
        let meter = Meter()
        if demo {
            // 假数据：README 截图用，不碰网络、不读凭据
            meter.loadDemo()
            ServiceStatus.shared.loadDemoIncidents() // 灯条上要有色，README 那张才看得见事件
            if loggedOut { meter.showLoggedOut() }
        } else if fresh {
            // 第一次打开的机器：什么都没存，余额是「—」，面板只摆设置入口
        } else {
            meter.loadSynchronously()
            // 纵轴的尺子要用「今天 + 前两天」那三天的最大小时花费，三天的账先取齐再画，
            // 否则第一张图会按取到一半的尺子画，跟第二张对不上。
            meter.selectDaySynchronously(2)
            meter.selectDaySynchronously(0)
        }
        func select(_ day: Int) {
            if demo { meter.selectDemoDay(day) } else { meter.selectDaySynchronously(day) }
        }
        let panel = render(meter: meter, appearance: nil)
        let panelLight = render(meter: meter, appearance: NSAppearance(named: .aqua))
        // 昨天那张：拿它跟今天那张比，切日时该不动的地方有没有动
        select(1)
        let panelYesterday = render(meter: meter, appearance: nil)
        // 再出一张「选中 5 天前」的面板：看历史那天长什么样
        select(5)
        let panelDay = render(meter: meter, appearance: nil)
        // 30 天那条展开的样子（点日期钮之后原地长出来的那块）
        let panelPicker = render(meter: meter, appearance: nil, pickerOpen: true)
        // 设置页三格：字最长的英文也要放得下，中英各出一张
        let settingsGeneral = renderSettings(meter: meter, tab: 0, appearance: nil, demo: demo)
        let settingsAccount = renderSettings(meter: meter, tab: 1, appearance: nil, demo: demo)
        let settingsAbout = renderSettings(meter: meter, tab: 2, appearance: nil, demo: demo)
        let panelPickerLight = render(meter: meter, appearance: NSAppearance(named: .aqua), pickerOpen: true)
        select(0)

        var report = ProbeReport(
            hasData: meter.snap.hasData,
            usageError: meter.snap.error ?? "",
            balance: meter.balance.amount ?? -1,
            moneyToday: meter.snap.moneyToday,
            peakCost: meter.snap.peakCost,
            offPeakCost: meter.snap.offPeakCost,
            peakPremium: meter.snap.peakPremium,
            dayOffsets: meter.snap.days.keys.sorted(),
            daily: meter.snap.daily.map { ($0 * 100).rounded() / 100 },
            yesterdayMoney: meter.snap.days[1]?.money ?? -1,
            yesterdayPeak: meter.snap.days[1]?.peak ?? -1,
            yesterdayOffPeak: meter.snap.days[1]?.offPeak ?? -1,
            yesterdayPremium: meter.snap.days[1]?.premium ?? -1,
            yesterdayWeekday: meter.snap.days[1]?.weekday ?? -1,
            yesterdayHitRate: meter.snap.days[1]?.hitRate ?? -1,
            moneyComplete: meter.snap.moneyComplete,
            burnRate: meter.snap.burnRate ?? -1,
            elapsedHours: (PeakHours.hourFraction(of: Date()) * 100).rounded() / 100,
            yesterdayMissRate: yesterdayMissRate(meter.snap),
            runwayDays: meter.runwayDays ?? -1,
            requests: meter.snap.today.requests,
            searchCalls: meter.snap.today.searchCalls,
            fetchCalls: meter.snap.today.fetchCalls,
            toolCost: meter.snap.today.toolCost,
            hourToolCalls: meter.snap.today.hourToolCalls,
            yesterdayRequests: meter.snap.days[1]?.requests ?? -1,
            perRequestTokens: meter.snap.today.requests > 0
                ? Double(meter.snap.today.tokenTotal) / Double(meter.snap.today.requests)
                : -1,
            miss: meter.snap.today.miss,
            hit: meter.snap.today.hit,
            output: meter.snap.today.output,
            hitRate: meter.snap.today.hitRate ?? -1,
            hitRateSameHours: meter.snap.comparisonHitRates(selected: 0)?.current ?? -1,
            yesterdayHitRateSameHours: meter.snap.comparisonHitRates(selected: 0)?.previous ?? -1,
            unitPriceSameHours: meter.snap.comparisonUnitPrices(selected: 0)?.current ?? -1,
            yesterdayUnitPriceSameHours: meter.snap.comparisonUnitPrices(selected: 0)?.previous ?? -1,
            unitPrice: meter.snap.today.unitPricePer100M ?? -1,
            yesterdayUnitPrice: meter.snap.days[1]?.unitPricePer100M ?? -1,
            ratePerHour: meter.snap.ratePerHour ?? -1,
            tone: PeakHours.now.label,
            models: meter.snap.today.models.map { .init(name: $0.name, tokens: $0.tokens, cny: $0.cost) },
            hours: meter.snap.today.hours.map { ($0 * 100).rounded() / 100 },
            hourHit: meter.snap.today.hourHit,
            hourMiss: meter.snap.today.hourMiss,
            yesterdayHourHit: meter.snap.days[1]?.hourHit ?? [],
            yesterdayHourMiss: meter.snap.days[1]?.hourMiss ?? [],
            panelSize: "\(panel.size)",
            panelYesterdaySize: "\(panelYesterday.size)",
            priceVerified: PeakHours.verifiedOn,
            priceStale: PeakHours.isPriceStale,
            apiKey: demo ? "demo" : Account.apiKeyOrigin
        )

        // 子线程按来源：今天那份从 DayCost.subagents 来，按天那份从 Snapshot.laneDaily 来。
        for lane in SubagentLane.all {
            let today = meter.snap.today.subagents[lane.id]
            report.subagents[lane.id] = ProbeReport.LaneUsage(
                calls: today?.calls ?? 0,
                tokens: today?.tokens ?? 0,
                hourly: today?.hours ?? [],
                daily: meter.snap.laneDaily[lane.id] ?? [:],
                equivalent: today.map { DeepSeekQuote.saved(of: $0, in: meter.snap.today) } ?? 0,
                webCalls: today?.webCalls ?? 0,
                searchViaDS: today?.searchViaDS ?? 0,
                hourlyWeb: today?.hourWeb ?? []
            )
        }

        // 设置窗口那张图（README 用）：离屏渲染，字段是空的
        if arguments.contains("--settings-shot") {
            let host = NSHostingView(rootView: SettingsView(meter: meter, startTab: 1, fillsCredentials: false))
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            let container = PanelBackground(frame: NSRect(x: 0, y: 0, width: 470, height: max(200, size.height)))
            host.frame = container.bounds
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            container.layoutSubtreeIfNeeded()
            if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
                let dir = URL(fileURLWithPath: arguments[index + 1])
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? capture(container).png.write(to: dir.appendingPathComponent("settings.png"))
            }
            exit(0)
        }

        if let index = arguments.firstIndex(of: "--status"), index + 1 < arguments.count {
            let dir = URL(fileURLWithPath: arguments[index + 1])
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let png = statusShot(amount: Fmt.money(meter.snap.moneyToday), tone: PeakHours.now.tone) {
                let file = dir.appendingPathComponent("status.png")
                try? png.write(to: file)
                report.statusPNG = file.path
            }
        }

        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            let dir = URL(fileURLWithPath: arguments[index + 1])
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("panel.png")
            try? panel.png.write(to: file)
            if loggedOut { try? panel.png.write(to: dir.appendingPathComponent("login-cta.png")) }
            try? panelLight.png.write(to: dir.appendingPathComponent("panel-light.png"))
            try? panelDay.png.write(to: dir.appendingPathComponent("panel-day5.png"))
            try? panelYesterday.png.write(to: dir.appendingPathComponent("panel-yesterday.png"))
            try? panelPicker.png.write(to: dir.appendingPathComponent("panel-picker.png"))
            try? panelPickerLight.png.write(to: dir.appendingPathComponent("panel-picker-light.png"))
            report.pickerSize = "\(panelPicker.size)"
            try? settingsGeneral.png.write(to: dir.appendingPathComponent("settings-general.png"))
            try? settingsAccount.png.write(to: dir.appendingPathComponent("settings-account.png"))
            try? settingsAbout.png.write(to: dir.appendingPathComponent("settings-about.png"))
            report.settingsSize = "\(settingsGeneral.size)"
            report.panelPNG = file.path
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        } catch {
            // 出不来就明说，别静悄悄给一份空 JSON——自检工具坏掉比它不存在更麻烦。
            FileHandle.standardError.write("probe: 报告序列化失败 \(error)\n".data(using: .utf8)!)
            exit(4)
        }
        exit(0)
    }

    /// 把状态栏那一格画下来（不需要屏幕录制权限：渲染的是自己的按钮）。
    private static func statusShot(amount: String, tone: PeakHours.Tone) -> Data? {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        guard let button = item.button else { return nil }
        button.attributedTitle = StatusTitle.make(amount: amount, tone: tone)
        button.sizeToFit()
        let size = NSSize(width: max(40, button.frame.width + 8), height: 24)
        let container = PanelBackground(frame: NSRect(origin: .zero, size: size))
        container.appearance = NSAppearance(named: .aqua)
        let label = NSTextField(labelWithAttributedString: StatusTitle.make(amount: amount, tone: tone))
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 4, y: (size.height - label.frame.height) / 2)
        container.addSubview(label)
        container.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        container.cacheDisplay(in: container.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// 设置页：三格各出一张，看中英文都不挤、字不截。
    private static func renderSettings(meter: Meter, tab: Int, appearance: NSAppearance?,
                                       demo: Bool) -> (size: NSSize, png: Data) {
        let content = NSHostingView(rootView: SettingsView(meter: meter, startTab: tab, fillsCredentials: !demo))
        content.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
        content.layoutSubtreeIfNeeded()
        let fitted = content.fittingSize
        let width = max(320, fitted.width.rounded())
        let height = max(240, fitted.height.rounded())
        content.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let container = PanelBackground(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        if let appearance { container.appearance = appearance }
        container.layoutSubtreeIfNeeded()
        return capture(container)
    }

    private static func render(meter: Meter, appearance: NSAppearance?,
                               pickerOpen: Bool = false) -> (size: NSSize, png: Data) {
        // 离屏渲染时只给容器换了 appearance，SwiftUI 的 colorScheme 认的还是 NSApp 那一套
        // （本机是深色），不显式指的话浅色那张图里「按明暗换色」的部分（Style.delta）会照深色画。
        var root = AnyView(MeterPanel(meter: meter, pickerStartOpen: pickerOpen))
        if let appearance, let scheme = colorScheme(of: appearance) {
            root = AnyView(root.environment(\.colorScheme, scheme))
        }
        let content = NSHostingView(rootView: root)
        content.frame = NSRect(x: 0, y: 0, width: 480, height: 700)
        content.layoutSubtreeIfNeeded()
        let fitted = content.fittingSize
        let width = max(200, fitted.width.rounded())
        let height = max(80, fitted.height.rounded())
        content.frame = NSRect(x: 0, y: 0, width: width, height: height)

        // 弹层背后是系统的窗口底色，PNG 里补上，否则深色模式下白字落在透明底上什么也看不见。
        let container = PanelBackground(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        if let appearance { container.appearance = appearance }
        container.layoutSubtreeIfNeeded()
        return capture(container)
    }

    /// NSAppearance → SwiftUI 的 colorScheme（只有明暗两种要分）。
    private static func colorScheme(of appearance: NSAppearance) -> ColorScheme? {
        switch appearance.name {
        case .aqua: return .light
        case .darkAqua: return .dark
        default: return nil
        }
    }

    /// 把一块视图按 captureScale 倍存成 PNG（默认 2 倍）。
    private static func capture(_ view: NSView) -> (size: NSSize, png: Data) {
        let width = view.bounds.width
        let height = view.bounds.height
        let scale: CGFloat = captureScale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return (view.frame.size, Data()) }
        rep.size = NSSize(width: width, height: height)
        view.cacheDisplay(in: view.bounds, to: rep)
        return (view.frame.size, rep.representation(using: .png, properties: [:]) ?? Data())
    }
}

/// 自检出图用的底：面板在真窗口里是 popover 材质，PNG 里没有窗口，补一层窗口底色上去，
/// 否则深色模式下白字落在透明底上什么都看不见。
private final class PanelBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

/// 通知自检（--notify-check）：请求授权 → 等 3 秒回读 → 打印 UNAuthorizationStatus 和能不能弹 → 发一条测试通知。
/// 入口只在 Probe.run 里，而 Probe 只由 --probe / --notify-check 命令进——开机自启走的是 AppDelegate，
/// 不会经过这里，所以不会自己弹。
private final class NotifyCheck: NSObject, UNUserNotificationCenterDelegate {
    static func run() -> Never {
        // 裸二进制没有 bundle id，UNUserNotificationCenter 会直接抛异常：先探，探不到如实说。
        guard Bundle.main.bundleIdentifier != nil else {
            print("notify-check: no bundle id (bare binary) — authorization cannot be requested")
            fflush(stdout)
            exit(4)
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = NotifyCheck() // 前台也弹：本命令跑着时应用就在前台
        center.requestAuthorization(options: [.alert]) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            center.getNotificationSettings { settings in
                DispatchQueue.main.async {
                    let names = ["notDetermined", "denied", "authorized", "provisional", "ephemeral"]
                    let raw = settings.authorizationStatus.rawValue
                    let name = raw < names.count ? names[raw] : "unknown(\(raw))"
                    let canPresent = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
                    print("UNAuthorizationStatus: \(name) (\(raw))")
                    print("alertSetting: \(settings.alertSetting.rawValue) (2 = enabled)")
                    print("canPresent: \(canPresent)")
                    let content = UNMutableNotificationContent()
                    content.title = "PI Meter 通知自检"
                    content.body = "看到这条说明通知链路通了。"
                    center.add(UNNotificationRequest(identifier: "notify-check", content: content, trigger: nil)) { error in
                        if let error {
                            print("notification add failed: \(error.localizedDescription)")
                        } else {
                            print("notification sent")
                        }
                        fflush(stdout)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
                    }
                }
            }
        }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        print("notify-check: timed out waiting for authorization flow")
        fflush(stdout)
        exit(5)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

/// 自检：面板底下点一下，那条 30 天收不收。
private final class TapCheck: NSObject, NSApplicationDelegate {
    static func run(point: CGFloat) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let check = TapCheck()
        check.pointFromTop = point
        app.delegate = check
        app.run()
    }

    /// 从面板顶边往下量多少（点）。窗口按面板实际尺寸开，坐标才一一对得上——
    /// 窗口比内容高的时候 VStack 会在里面居中，按窗口坐标算出来的点全错位。
    private var pointFromTop: CGFloat = 240
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        let meter = Meter()
        meter.loadDemo()
        ServiceStatus.shared.loadDemoIncidents()
        let hosting = NSHostingView(rootView: MeterPanel(meter: meter, pickerStartOpen: true))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: size.width, height: size.height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let opened = hosting.fittingSize.height
            let point = CGPoint(x: 200, y: opened - self.pointFromTop)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1
                ) {
                    window.sendEvent(event)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let after = hosting.fittingSize.height
                print("{\"fromTop\": \(Int(self.pointFromTop)), \"opened\": \(Int(opened)), "
                      + "\"afterTap\": \(Int(after)), \"collapsed\": \(after < opened - 20)}")
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
    }
}
