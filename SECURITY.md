# Security / 安全说明

这个 app 读你自己的 DeepSeek 用量，然后把数字画在菜单栏上。下面写清它碰什么、不碰什么，以及你怎么自己验。

## 承诺（每条都能在代码里对）

- **没有服务器**：仓库里没有后端，没有账号体系，没有统计上报，没有第三方 SDK，没有自动更新通道。
- **只连两个域名**：`api.deepseek.com`（查余额）、`platform.deepseek.com`（读账单）。没有第三个。
- **不读你的内容**：不读对话、不读会话日志、不读别的 app 的数据。
- **凭据只在本机**：`~/Library/Application Support/DSMeter/account.json`，目录 `0700`、文件 `0600`；网页登录态在 `~/Library/WebKit/app.dsmeter.macos`。设置里两颗按钮分别清掉。
- **不写日志**：没有 `NSLog` / `os_log` / 日志文件；账单响应只在内存里，磁盘缓存关掉了（`URLSessionConfiguration.ephemeral` + `urlCache = nil`）。
- **不发签名包**：Release 里的 dmg 是 ad-hoc 签名（`codesign --sign -`），没有开发者的身份，也没有公证。

## 威胁模型（诚实说边界）

- 登录态等于你账号的钥匙。**Mac 被攻破，它就能被读走**——跟浏览器里的 cookie 同一级风险。所以给了「退出网页登录」，不用的时候点一下。
- 未签名的 dmg 第一次打开会被 Gatekeeper 拦一次；放行之后系统不会再问。
- 账单接口不是公开 API，随时可能变；变了只是取不到数，不会改本地状态。

## 自己验

```bash
./scripts/security-audit.sh                 # 查仓库：凭据形态、历史、域名、依赖、日志调用
./scripts/security-audit.sh <二进制路径>     # 再把二进制里的字符串扫一遍
.build/release/DSMeter --probe              # 打印它当前掌握的所有数字
```

- 网络：用 Little Snitch / LuLu 之类的工具看它只连那两个域名。
- 代码：`Sources/` 两千多行，读一遍比信一段说明快。

## 发版门禁

每一版都必须过：

1. `scripts/security-audit.sh`（CI 里 `audit` 工作流，push / PR 都跑）；
2. 打 tag 出包时，`release` 工作流先跑体检，再编；
3. 产物带 `SHA256SUMS`，cask 里的 sha256 由 CI 从同一个 dmg 算出来。

## 报告问题

发现安全问题请用 GitHub 的 **Private vulnerability reporting**（仓库 → Security → Advisories → Report a vulnerability），不要开公开 issue。

---

# Security (English)

This app reads your own DeepSeek usage and draws it in the menu bar. Here is exactly what it touches and how to verify it.

- **No server**: no backend, no accounts, no telemetry, no third-party SDK, no auto-update channel.
- **Two hosts only**: `api.deepseek.com` (balance) and `platform.deepseek.com` (billing).
- **Never reads your content**: no conversations, no session logs, no other apps' data.
- **Credentials stay local**: `~/Library/Application Support/DSMeter/account.json` (dir `0700`, file `0600`); web sign-in state in `~/Library/WebKit/app.dsmeter.macos`. Both can be cleared from Settings.
- **No logs**: no `NSLog` / `os_log` / log files; billing responses live in memory only (ephemeral session, disk cache disabled).
- **Unsigned builds**: releases are ad-hoc signed (`codesign --sign -`), no developer identity, no notarization.

**Threat model**: the sign-in token is an account key. If your Mac is compromised, it can be read — same risk class as browser cookies. That is why "Sign out of web" exists. Unsigned builds are blocked once by Gatekeeper before the first launch. The billing endpoint is undocumented and may change; if it does, the app simply stops reading.

**Verify it yourself**: run `./scripts/security-audit.sh`, `--probe`, and watch network traffic (Little Snitch/LuLu). The source is ~2.6k lines.

**Release gate**: every push/PR runs `scripts/security-audit.sh` in CI; the release workflow runs it before packaging; assets ship with `SHA256SUMS`, and the cask sha256 is computed by CI from the same dmg.

**Reporting**: use GitHub Private vulnerability reporting (Security → Advisories → Report a vulnerability), not a public issue.
