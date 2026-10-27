import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let meter = Meter()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    /// 面板开着时用的节奏：一般只开几秒，多花的就是两三次请求。
    private var panelTimer: Timer?
    private let panelInterval: TimeInterval = 15

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
            forName: .dsMeterOpenSettings,
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
        observeSleep()
        render()

        // 第一次跑、什么都没填：直接把面板弹出来（不弹那张设置表），让人看见两条路。
        if Account.apiKey == nil, Account.consoleToken == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.togglePopover() }
        }

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

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = T.statusTooltip.s
    }

    /// 灯：闲时绿、高峰黄（高峰单价 2 倍）。数字是今天的花费。
    private func render() {
        guard let button = statusItem.button else { return }
        let amount = meter.snap.hasData ? Fmt.money(meter.snap.primaryToday) : "—"
        button.attributedTitle = StatusTitle.make(amount: amount, tone: PeakHours.now.tone)
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
        startPanelRefresh()
        Timing.mark("show 返回")
        // 先出窗口再激活：反过来的话要等激活那一步才看得见。
        NSApp.activate(ignoringOtherApps: true)
        Timing.mark("激活完成")
    }

    /// 面板开着的时候每 15 秒取一次（面板一般只开几秒，代价就是两三次请求）；
    /// 关掉、睡下去都立刻停——CPU 和电费都只花在看着它的那几秒里。
    private func startPanelRefresh() {
        panelTimer?.invalidate()
        panelTimer = Timer.scheduledTimer(withTimeInterval: panelInterval, repeats: true) { [weak self] _ in
            self?.meter.refresh()
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
        window.title = "DS Meter"
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
    }
}

extension Notification.Name {
    /// 面板里的「打开账号…」按钮：面板 hosted 在 AppDelegate 里，用通知喊一声。
    static let dsMeterOpenSettings = Notification.Name("DSMeterOpenSettings")
}
