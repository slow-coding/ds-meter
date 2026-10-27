import AppKit
import SwiftUI

/// 小小的设置页：三格——通用（开自启、刷新节奏、语言）、账号（两串凭据）、关于（价目与数据说明）。
/// 以前一页从上排到下，滚都不用滚就一屏塞满；分三格之后每格只放一类东西。
struct SettingsView: View {
    @ObservedObject var meter: Meter

    /// 自检出图用：直接打开某一格；`demo` 时不填真凭据（截图会进 README，不能带 key）。
    private let fillsCredentials: Bool

    init(meter: Meter, startTab: Int = 0, fillsCredentials: Bool = true) {
        self.meter = meter
        self.fillsCredentials = fillsCredentials
        let tabs: [Tab] = [.general, .account, .about]
        _tab = State(initialValue: tabs[min(max(startTab, 0), tabs.count - 1)])
    }

    @State private var tab: Tab = .general
    @State private var apiKey = ""
    @State private var token = ""
    @State private var status: String?
    @State private var busy = false
    @State private var autoStart = LoginItem.isEnabled

    private let bodyFont = Font.system(size: 11)
    private let monoFont = Font.system(size: 12, design: .monospaced)
    private let tabWidth: CGFloat = 430
    private let tabHeight: CGFloat = 304

    enum Tab: Hashable { case general, account, about }

    var body: some View {
        // 自己拿分段控件当页签，不用 TabView：macOS 那个页签在弹层和离屏渲染里都不好控（会顶出一条空白），
        // 而面板上「今日 / 昨天」就是分段控件，这里跟它保持一致。
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $tab) {
                Text(T.tabGeneral.s).tag(Tab.general)
                Text(T.tabAccount.s).tag(Tab.account)
                Text(T.tabAbout.s).tag(Tab.about)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Group {
                switch tab {
                case .general: general
                case .account: account
                case .about: about
                }
            }
            .frame(width: tabWidth, height: tabHeight, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .onAppear {
            guard fillsCredentials else { return }
            apiKey = Account.apiKey ?? ""
            token = Account.consoleToken ?? ""
        }
    }

    // MARK: - 通用

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(T.autoStart.s, isOn: $autoStart)
                    .toggleStyle(.switch)
                    .font(bodyFont)
                    .onChange(of: autoStart) { enabled in
                        LoginItem.setEnabled(enabled)
                    }
                Text(T.autoStartNote.s).font(bodyFont).foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(T.refreshTitle.s).font(bodyFont).foregroundStyle(.secondary)
                Picker("", selection: $meter.interval) {
                    Text(T.refreshPower.s).tag(TimeInterval(300))
                    Text(T.refreshDefault.s).tag(TimeInterval(120))
                    Text(T.refreshFrequent.s).tag(TimeInterval(30))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(T.refreshNote.s).font(bodyFont).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(T.languageTitle.s).font(bodyFont).foregroundStyle(.secondary)
                    Text(L.languageLine()).font(bodyFont)
                    Spacer(minLength: 0)
                }
                Text(T.languageNote.s).font(bodyFont).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - 账号

    private var account: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(T.apiKeyTitle.s).font(bodyFont).foregroundStyle(.secondary)
                TextField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(monoFont)
                Text(Account.apiKeyOrigin).font(bodyFont).foregroundStyle(.tertiary)
                Text(T.apiKeyNote.s).font(bodyFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(T.tokenTitle.s).font(bodyFont).foregroundStyle(.secondary)
                TextField("userToken", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(monoFont)
                HStack(spacing: 10) {
                    Button(T.tokenLogin.s) { openLogin() }
                        .disabled(busy)
                    Button(T.tokenLogout.s) { forgetWebLogin() }
                        .buttonStyle(.link)
                    Text(Account.consoleTokenOrigin).font(bodyFont).foregroundStyle(.tertiary)
                }
                Text(T.tokenLoginNote.s).font(bodyFont).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(T.tokenNote.s).font(bodyFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Text(status ?? " ").font(bodyFont).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Button(T.forget.s) { confirmForget() }
                Button(T.save.s) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - 关于

    private var about: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(T.pricingTitle.s).font(bodyFont).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(T.openPricing.s) { NSWorkspace.shared.open(PeakHours.sourceURL) }
                        .buttonStyle(.link)
                }
                Text(T.pricingRule.s).font(bodyFont).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("\(T.priceLine.s) \(PeakHours.verifiedOn)").font(bodyFont).foregroundStyle(.tertiary)
                    if PeakHours.isPriceStale {
                        Text(T.priceStaleNote.s).font(bodyFont).foregroundStyle(.orange)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(T.dataTitle.s).font(bodyFont).foregroundStyle(.secondary)
                Text(T.dataRead.s)
                Text(T.dataStore.s)
                Text(T.dataSend.s)
                Text(T.dataNoStore.s)
                Text(T.dataDisclaimer.s)
            }
            .font(bodyFont)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    // MARK: - 动作

    private func save() {
        Account.save(apiKey: apiKey, consoleToken: token)
        meter.reloadAccount()
        status = T.saved.s
    }

    /// 撤回授权：删光凭据，界面立刻回到「没绑定」。
    private func confirmForget() {
        let alert = NSAlert()
        alert.messageText = T.forgetTitle.s
        alert.informativeText = T.forgetBody.s
        alert.addButton(withTitle: T.delete.s)
        alert.addButton(withTitle: T.cancel.s)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Account.forget()
        apiKey = ""
        token = ""
        meter.reloadAccount()
        status = T.deleted.s
    }

    /// 在 app 自己的窗口里登录，读到 token 就存好了。
    private func openLogin() {
        busy = true
        status = T.loginInProgress.s
        LoginWindow.shared.present { found in
            busy = false
            token = found
            meter.reloadAccount()
            status = T.loginDone.s
        } onCancel: {
            busy = false
            status = T.loginCancelled.s
        }
    }

    /// 退出网页登录：网页的 cookie / localStorage + 存下来的 token 一起清掉。
    private func forgetWebLogin() {
        busy = true
        LoginWindow.clearSession {
            Account.forgetConsoleToken()
            token = ""
            meter.reloadAccount()
            busy = false
            status = T.loginSignedOut.s
        }
    }
}
