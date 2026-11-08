import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let meter = Meter()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    /// 面板开着时用的节奏：一般只开几秒，多花的就是两三次请求。
    private var panelTimer: Timer?
    private let panelInterval: TimeInterval = 15
    /// 面板开着时盯着「面板以外的那一下点击」。
    /// `.transient` 只管「本 app 内部点了别处」，而菜单栏工具绝大多数时候根本不是 active app（点完全不会 deactivate），
    /// 于是点桌面、点别的 app 面板就不收——他 2026-11-07 报的就是这个。
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPanelRefresh()
            self?.popover.performClose(nil)
        }
        NotificationCenter.default.addObserver(
            forName: .piMeterOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.showSettings()
        }
        setupStatusItem()
        setupPopover()
        meter.onChange = { [weak self] in self?.render() }
        meter.start()
        // 服务状态：feed 自己排自己的节奏（10 分钟一次，失败退让），通知拿不到授权时灯会变红。
        ServiceStatus.shared.start()
        ServiceStatus.shared.$serviceAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        observeSleep()
        render()

        // 第一次跑、什么都没填：直接把面板弹出来（不弹那张设置表），让人看见两条路。
        if Account.apiKey == nil, Account.consoleToken == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.togglePopover() }
        }

        // 改名（DS Meter → PI Meter）换 bundle id 后读不到旧 domain，把旧偏好一次性搬过来。
        migrateDefaultsIfNeeded()
        // 旧 label 的 LaunchAgent 还在就换到新 label，别让自启指着不存在的路径。
        LoginItem.migrateLegacyAgent()

        // 默认开机自启：第一次跑就装上；用户自己关过就不再自动装。
        if UserDefaults.standard.object(forKey: "autoStart") == nil {
            LoginItem.enable()
            UserDefaults.standard.set(true, forKey: "autoStart")
        } else if UserDefaults.standard.bool(forKey: "autoStart"), !LoginItem.isEnabled {
            LoginItem.enable()
        }

        // 自检用：起 app 后自动弹一次面板，没人点鼠标也能看它弹不弹得出来。
        if CommandLine.arguments.contains("--demo-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.togglePopover() }
        }
    }

    // MARK: - 状态栏

    /// 旧 bundle id（app.dsmeter.macos）domain 里已有的键搬到新 domain，搬完写标记，不重复搬。
    private func migrateDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "piMeterMigrated") else { return }
        if let old = defaults.persistentDomain(forName: "app.dsmeter.macos") {
            for (key, value) in old where !["piMeterMigrated"].contains(key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "piMeterMigrated")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = T.statusTooltip.s
    }

    /// 灯：闲时绿、高峰黄（高峰单价 2 倍）、服务出事红（通知拿不到授权时的降级信号）。数字是今天的花费。
    private func render() {
        guard let button = statusItem.button else { return }
        let amount = meter.snap.hasData ? Fmt.money(meter.snap.primaryToday) : "—"
        button.attributedTitle = StatusTitle.make(amount: amount, tone: PeakHours.now.tone,
                                                  serviceAlert: ServiceStatus.shared.serviceAlert)
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - 面板

    private func setupPopover() {
        popover = NSPopover()
        popover.delegate = self
        popover.behavior = .transient
        // 系统的展开动画要 200ms 左右，点开就是「等一下」；关掉它，先出内容。
        popover.animates = false
        let controller = NSHostingController(rootView: MeterPanel(meter: meter))
        // 面板多高由内容说了算（2026-11-08）：NSHostingController 默认**不**把内容的理想尺寸
        // 交给 popover，preferredContentSize 一直是 (0,0)，窗口就自己拿了个尺寸——
        // 实测刚弹出来那一下宿主视图被塞成 420×250（内容要 420×586），切到昨天再切回来
        // 也会差 7～11pt。宿主视图一矮，SwiftUI 只能把里面的东西压下去，顶上「今天花费 /
        // 今日 token」那两个大数（挂着 minimumScaleFactor）就跟着变小——他报的「切昨天今天这块
        // 大小会变」就是这么来的，不是下面把它挤了。加上这一档，容器高度跟着内容长/收。
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        // 预热：把视图先建好、量好，别等第一次点开才排版。
        controller.view.layoutSubtreeIfNeeded()
        _ = controller.view.fittingSize
    }

    private func togglePopover() {
        Timing.click()
        if popover.isShown {
            stopPanelRefresh()
            popover.performClose(nil)
            return
        }
        // 打开这一下：余额实时重取，账单只在这份旧了的时候重取
        meter.refreshOnOpen()
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startOutsideClickMonitor()
        startPanelRefresh()
        Timing.mark("show 返回")
        // 先出窗口再激活：反过来的话要等激活那一步才看得见。
        NSApp.activate(ignoringOtherApps: true)
        Timing.mark("激活完成")
    }

    /// 面板开着的时候每 15 秒取一次（面板一般只开几秒，代价就是两三次请求）；
    /// 关掉、睡下去都立刻停——CPU 和电费都只花在看着它的那几秒里。
    private func startPanelRefresh() {
        panelTimer = Timer.scheduledTimer(withTimeInterval: panelInterval, repeats: true) { [weak self] _ in
            self?.meter.refresh()
        }
    }

    // MARK: - 点面板外面那一下

    /// 全局鼠标监听：只认面板以外的按下（面板内部的点击走不到这里）。
    /// 鼠标类的全局监听不需要辅助功能权限（键盘事件才要），所以这里不会弹权限框。
    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func stopPanelRefresh() {
        panelTimer?.invalidate()
        panelTimer = nil
    }

    // MARK: - 右键菜单

    private func showMenu() {
        let menu = NSMenu()
        let today = meter.snap.hasData ? Fmt.money(meter.snap.moneyToday) : "—"
        let balance = meter.balance.amount.map(Fmt.money) ?? "—"
        menu.addItem(info(L.menuToday(today: today, local: Fmt.money(meter.snap.primaryToday))))
        menu.addItem(info(L.menuBalance(balance)))
        menu.addItem(.separator())
        menu.addItem(action(T.menuRefresh.s, #selector(refreshNow)))
        // 开机自启：勾选状态就是 LaunchAgent 在不在，点了立刻生效
        let autoStart = action(T.menuAutoStart.s, #selector(toggleAutoStart))
        autoStart.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(autoStart)
        let settings = action(T.menuSettings.s, #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(action(T.menuLogin.s, #selector(openLogin)))
        menu.addItem(action(T.menuUsage.s, #selector(openUsagePage)))
        menu.addItem(action(T.menuPricing.s, #selector(openPricingPage)))
        menu.addItem(.separator())
        menu.addItem(action(T.menuQuit.s, #selector(quit)))
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - 设置窗口

    func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: SettingsView(meter: meter))
        let window = NSWindow(contentViewController: controller)
        window.title = "PI Meter"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 动作

    @objc private func refreshNow() { meter.refresh() }

    @objc private func toggleAutoStart() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func openSettings() { showSettings() }

    /// 右键直接开登录窗口：读到 token 就存好、关窗、刷面板。
    @objc private func openLogin() {
        LoginWindow.shared.present { [weak self] _ in self?.meter.reloadAccount() }
    }

    @objc private func openUsagePage() {
        if let url = URL(string: "https://platform.deepseek.com/usage") { NSWorkspace.shared.open(url) }
    }

    @objc private func openPricingPage() {
        NSWorkspace.shared.open(PeakHours.sourceURL)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - 睡眠 / 息屏：停掉轮询，醒来立刻补一次

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemSlept(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemSlept(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemWoke(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(systemWoke(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func systemSlept(_ note: Notification) {
        stopPanelRefresh()
        meter.pause()
    }

    @objc private func systemWoke(_ note: Notification) { meter.resume() }
}

extension AppDelegate: NSPopoverDelegate {
    /// 点外面、按 Esc 都会走到这里（不只是我们自己的 performClose），统一在这停掉快节奏。
    func popoverDidClose(_ notification: Notification) {
        stopPanelRefresh()
        stopOutsideClickMonitor()
        // 面板收了就把那条 30 天也收掉：下次点开不该还开着上回那条。
        NotificationCenter.default.post(name: .piMeterPanelClosed, object: nil)
    }
}

extension Notification.Name {
    /// 面板里的「打开账号…」按钮：面板 hosted 在 AppDelegate 里，用通知喊一声。
    static let piMeterOpenSettings = Notification.Name("PIMeterOpenSettings")
    static let piMeterPanelClosed = Notification.Name("PIMeterPanelClosed")
}
