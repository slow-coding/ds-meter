import AppKit

Account.migrateIfNeeded()

let arguments = CommandLine.arguments
if arguments.contains("--probe") || arguments.contains("--probe-peak") || arguments.contains("--notify-check") {
    Probe.run(arguments: arguments)
}

// 只允许一个实例：自启拉起来的那个已经在跑时，别再开第二个菜单栏格子。
let others = NSRunningApplication.runningApplications(withBundleIdentifier: "app.pimeter.macos")
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
