import Foundation

/// 打开面板的耗时打点。只在显式传 `--timing` 时打到 stderr，不写任何文件、不落盘。
enum Timing {
    private static var start: CFAbsoluteTime = 0
    private static var enabled: Bool { CommandLine.arguments.contains("--timing") }

    static func click() {
        guard enabled else { return }
        start = CFAbsoluteTimeGetCurrent()
        write("点下")
    }

    static func mark(_ label: String) {
        guard enabled, start > 0 else { return }
        let delta = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        write("\(label): +\(delta)ms")
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
