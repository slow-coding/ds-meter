# DS Meter

![banner](docs/banner.png?v=1.0.3)

菜单栏里一格：一颗灯 + 今天花了多少钱。灯绿 = 闲时（半价），灯黄 = 高峰（双倍）。点开是明细。

**完全本地运行**：没有服务器、没有账号体系、没有统计上报；你的 key 和登录态只在这台 Mac 上。

**中文** · [English](#english)

> 非官方工具，跟 DeepSeek 官方没关系。用量读的是平台网页自己在用的账单接口，没有公开文档，随时可能变。

## 30 秒上手

**最快**：从 [Releases](../../releases) 下 `DS-Meter-<版本>.dmg`，拖进「应用程序」，打开。第一次会被系统拦一次（没有开发者签名），放行方法见下面「装」。

**用 Homebrew**：`brew install --cask <账号>/ds-meter/ds-meter`，不用放行。

**自己编**（要先有 Xcode 命令行工具）：

```bash
git clone https://github.com/slow-coding/ds-meter && cd ds-meter && ./scripts/build-app.sh
open "/Applications/DS Meter.app"
```

然后：菜单栏那格 → 「登录网页读取」→ 登录 → 出数。

点菜单栏那格，面板从上面掉下来：余额、今天 / 昨天、那天的每小时柱子和 token、闲时 / 高峰各花了多少、缓存命中率、每亿 token 的单价（那天花了多少 ÷ 那天的 token 量，跟前一天比着看）、分模型、还能撑几天。没登录时那里是一句话加一颗按钮。

日期按钮把最近 30 天铺成一条柱条，点哪天看哪天。

## 安全：全本地，没有服务器

- **没有任何服务器**。这个项目没有后端、没有账号体系、没有统计上报、没有第三方 SDK、没有自动更新通道。
- **只连两个域名**：`api.deepseek.com`（查余额）、`platform.deepseek.com`（读账单）。没有第三个。
- **凭据只存本机**：`~/Library/Application Support/DSMeter/account.json`，目录 `0700`、文件 `0600`，只有你这个用户能读；网页登录态在 `~/Library/WebKit/app.dsmeter.macos`。设置里「删除已存凭据 / 退出网页登录」分别清掉。
- **不读你的内容**：不读对话、不读会话日志、不读别的 app 的数据。账单响应只在内存里（磁盘缓存关掉了），不落盘。
- **可以自己核**：源码两千多行，`--probe` 会把当前所有数字打出来；Little Snitch 之类的工具看它只连那两个域名。
- **诚实的边界**：登录态等于你账号的钥匙，Mac 被攻破就能被读走——跟浏览器里的 cookie 是同一级风险。所以给了「退出网页登录」，也建议不用时点一下。
- 完整的安全说明、威胁模型和自查命令见 [`SECURITY.md`](SECURITY.md)；每次 push / PR / 发版都会跑 `scripts/security-audit.sh`。

## 它怎么工作（三句话）

1. **余额**：app 拿你填的 `sk-` key，去问官方余额接口「这个账户还有多少钱」。这是公开接口。
2. **账单**：DeepSeek 没有开放账单 API；网页的用量页靠浏览器里的一串登录凭证取数。app 在自己的窗口里让你登录一次，拿到那串凭证，之后替你去读同一份账单。
3. **所以**：不登录只有余额；登录了才有今天花了多少、每小时、分模型、命中率。凭证只存本机，只发给 `platform.deepseek.com`。

## 装

三种方式，同一个 app。**都不带开发者签名**：`Signature=adhoc`，证书不属于任何人，也没有公证。dmg 是 CI 在干净机器上编的；自己编就是你自己机器上的签名。

### 方式一：dmg

1. 从 [Releases](../../releases) 下载 `DS-Meter-<版本>.dmg`，拖进「应用程序」。
2. 第一次打开会被拦一次（没有开发者签名，正常现象）：
   - macOS 15+：系统设置 → 隐私与安全 → 滚到底 → 「仍要打开」；
   - 或者终端：`xattr -dr com.apple.quarantine "/Applications/DS Meter.app"`。
3. 想核对下载有没有被换过：

```bash
shasum -a 256 ~/Downloads/DS-Meter-1.0.0.dmg
# 和 Release 里的 SHA256SUMS 对一下
```

dmg 是 universal（Apple Silicon + Intel），macOS 13+。

### 方式二：Homebrew

```bash
brew tap slow-coding/ds-meter
brew trust slow-coding/ds-meter      # 新版 Homebrew 要求显式信任第三方 tap
brew install --cask ds-meter
```

升级：`brew upgrade --cask ds-meter`。

> 实测（macOS 27 + Homebrew 7）：brew 装出来的 app 虽然带 `com.apple.quarantine`，但系统对包管理器这一类不弹窗，直接能开；浏览器下载的 dmg 会弹。这条行为随 macOS 版本变，真被拦了就按方式一放行。
>
> cask 放在个人 tap 里，Homebrew 官方不审核。它只指向同一个 dmg，`sha256` 由 CI 从那个 dmg 算出来，和 Release 里的 `SHA256SUMS` 一致。

### 方式三：源码

要求：

| 要什么 | 怎么确认 | 怎么装 |
| --- | --- | --- |
| macOS 13 或更新 | `sw_vers -productVersion` | 系统更新 |
| Xcode 命令行工具（`swift`、`clang`、`git` 都在里面） | `xcode-select -p` 有输出 | `xcode-select --install`，弹窗里点安装；约 2–5 GB，5–15 分钟 |
| 2 GB 空闲磁盘 | — | — |

不需要 Node、Python、Homebrew，也不需要付费的 Apple 开发者账号。

```bash
git clone https://github.com/slow-coding/ds-meter
cd ds-meter
./scripts/build-app.sh     # 编 + 装进 /Applications，约 10 秒
open "/Applications/DS Meter.app"
```

`xcode-select --install` 必须等它装完再编，否则会报 `swift: command not found`。

### 关于签名

- 分发的包是 **ad-hoc 签名**（`codesign --sign -`）：能校验完整性，但没有身份——所以系统会拦一次，也没有人能通过签名追到某个开发者。
- 不提供公证（notarization）：那需要 99 美元/年的 Apple Developer Program，而且等于让所有用户信任一张个人证书。
- 自己编也一样是 ad-hoc；想固定签名就用自己的证书：`SIGN_ID="Apple Development: 你的名字 (XXXXXXXXXX)" ./scripts/build-app.sh`。
- 本地编出来的 app 没有 `com.apple.quarantine` 标记，Gatekeeper 不会拦。

第一次运行会在「登录项」里注册开机自启，可以关。卸载：`./scripts/uninstall.sh`（应用、自启、凭据、登录态、缓存一起清）。

### 常见问题

- `swift: command not found` → 命令行工具没装好，重跑 `xcode-select --install`。
- `xcodebuild: error: tool requires Xcode` → 装了完整 Xcode 但没同意协议：`sudo xcodebuild -license accept`。
- 「已损坏，无法打开」→ 先 `xattr -dr com.apple.quarantine "/Applications/DS Meter.app"`；还不行就是包在传输里坏了，用 sha256 对一下。
- 想只在终端里跑、不装 app：`swift build -c release` 之后用 `.build/release/DSMeter`。

## 两种用法

**登录（推荐）**：看账单。菜单栏 → 登录网页读取，或者直接在面板上点那颗按钮。

**只填 API Key**：只看余额。右键 → 账号… → 贴 `sk-` 开头的 key。设置页一共三格：通用（自启、刷新、语言）、账号（两串凭据）、关于（价目与数据说明）。

两个都不填时，第一次启动会自动弹面板，只有两行字和一颗按钮（上图第 2 张）。

## 数据从哪来

| 显示 | 来源 | 精度 |
| --- | --- | --- |
| 余额 | `api.deepseek.com/user/balance`（`sk-`） | 实时，到分 |
| 今天 / 每小时 / 分模型 / 命中率 / 近 30 天 / 还能撑几天 | `platform.deepseek.com/api/v0/usage/by_api_key/{cost,amount}`（登录态） | 跟网页用量页同源，滞后约 5 分钟 |

## 已知限制

- 账单接口一次最多给 30 天，日期条只有 30 天，更早的要上网页看。
- 认不出法定节假日：节假日那天的「高峰」会多算一倍价。
- 只统计登录那个账号的账单；余额是账号级的。
- 平台账单本身滞后约 5 分钟，别拿它对秒。
- 登录态会过期，过期后点一次「登录网页读取」重登。
- 接口不是公开 API：改了路径或加了风控，这工具就取不到数；默认 2 分钟一次，连续失败自动退避（最长 15 分钟一次）。

## 计费规则

高峰：北京时间**工作日** 9–12、14–18，单价双倍；其余时段、周末、节假日全天是闲时价（高峰的一半）。

元 / 百万 tokens（闲时 → 高峰）：

- `deepseek-flash`：命中 0.02 → 0.04、未命中 1 → 2、输出 4 → 8
- `deepseek-v4-pro`：命中 0.15 → 0.30、未命中 4.5 → 9、输出 13.5 → 27

价格页：https://api-docs.deepseek.com/zh-cn/quick_start/pricing

## 开发

```bash
swift build -c release

.build/release/DSMeter --probe                                  # 真数据打一遍数字
.build/release/DSMeter --probe --demo --snapshot /tmp/dsm --status /tmp/dsm   # 假数据出图
.build/release/DSMeter --probe --demo --logged-out --snapshot /tmp/dsm        # 「还没登录」那屏
.build/release/DSMeter --probe --fresh --snapshot /tmp/dsm                    # 「第一次打开」那屏
.build/release/DSMeter --probe --fresh --settings-shot --snapshot /tmp/dsm    # 设置页
.build/release/DSMeter --probe --login-check --snapshot /tmp/dsm              # 登录窗口自检
.build/release/DSMeter --probe --demo --scale 3 --snapshot /tmp/dsm \
  && cp /tmp/dsm/panel.png docs/panel.png                                      # README 那张面板图（假数据）
swift scripts/make-banner.swift                                                # 重新生成 banner
```

README 里的图全部来自 `--demo`（假数据），不放真机截图：余额、今日花费、token 量、菜单栏、壁纸一旦进了仓库和 git 历史就是公开的，删掉也还按 SHA 取得到。

## License

MIT，见 `LICENSE`。

---

# English

A menu bar item: a dot + today's spend. Green = off-peak (half price), yellow = peak (double). Click for details.

**Runs entirely locally**: no server, no account system, no telemetry. Your key and sign-in token never leave this Mac.

> Unofficial tool, not affiliated with DeepSeek. Usage numbers come from the same billing endpoint the platform's own web page uses. It is undocumented and may change at any time.

## Quick start

**Fastest**: grab `DS-Meter-<version>.dmg` from [Releases](../../releases), drag it into Applications, open it. macOS blocks it once (no developer signature); see Install below for the one-time override.

**With Homebrew**: `brew install --cask <user>/ds-meter/ds-meter` — no Gatekeeper prompt.

**Build it yourself**:

```bash
git clone https://github.com/slow-coding/ds-meter && cd ds-meter && ./scripts/build-app.sh
open "/Applications/DS Meter.app"
```

Then: menu bar → **Sign in on web** → sign in → done.

Click the menu bar item and the panel drops down: balance, today / yesterday, that day's hourly bars and tokens, peak vs off-peak spend, cache-hit rate, cost per 100M tokens for that day (its spend ÷ its tokens, next to the day before), per-model cost, and how many days the balance lasts. Before signing in it shows one sentence and one button.

The date button unrolls the last 30 days as a strip; click a day to inspect it.

## Security: all local, no server

- **No backend at all.** No server, no accounts, no telemetry, no third-party SDK, no auto-update channel.
- **Two hosts, period**: `api.deepseek.com` (balance) and `platform.deepseek.com` (billing).
- **Credentials stay on disk, for you only**: `~/Library/Application Support/DSMeter/account.json`, directory `0700`, file `0600`; the web sign-in state lives in `~/Library/WebKit/app.dsmeter.macos`. Both can be wiped from Settings.
- **Your content is never read**: no conversations, no session logs, no other apps' data. Billing responses live in memory only (disk cache is disabled).
- **Verify it yourself**: ~2.6k lines of source, `--probe` prints every number it holds, Little Snitch shows only those two hosts.
- **Honest limit**: the sign-in token is effectively an account key. If your Mac is compromised, it can be read — same risk class as browser cookies. That is why "Sign out of web" exists.
- Full security notes, threat model and self-check commands: [`SECURITY.md`](SECURITY.md). `scripts/security-audit.sh` runs on every push, PR and release.

## How it works (in three sentences)

1. **Balance**: the app asks DeepSeek's public balance endpoint with the `sk-` key you provide.
2. **Billing**: DeepSeek has no public billing API. Its usage page reads data using a sign-in token stored in the browser. The app opens its own sign-in window once, takes that token, and reads the same billing numbers for you.
3. **Therefore**: without signing in you only get the balance; with it you get today's spend, hourly bars, per-model costs and cache-hit rate.

## Install

Three ways, same app. **None of them carries a developer signature**: `Signature=adhoc`, no team, no notarization. The dmg is built by CI on a clean runner; building locally signs with your own machine.

### Option 1: dmg

1. Download `DS-Meter-<version>.dmg` from [Releases](../../releases), drag it into Applications.
2. The first launch is blocked once (no developer signature; expected):
   - macOS 15+: System Settings → Privacy & Security → scroll down → "Open Anyway";
   - or in a terminal: `xattr -dr com.apple.quarantine "/Applications/DS Meter.app"`.
3. Check the download if you want:

```bash
shasum -a 256 ~/Downloads/DS-Meter-1.0.0.dmg
# compare with SHA256SUMS in the release
```

The dmg is universal (Apple Silicon + Intel), macOS 13+.

### Option 2: Homebrew

```bash
brew tap slow-coding/ds-meter
brew trust slow-coding/ds-meter      # recent Homebrew requires explicit trust for third-party taps
brew install --cask ds-meter
```

Upgrade with `brew upgrade --cask ds-meter`.

> Measured on macOS 27 + Homebrew 7: the app installed by brew does carry `com.apple.quarantine`, but macOS does not prompt for package-manager downloads; browser downloads do. This behaviour changes across macOS releases — if you do get blocked, use the override in Option 1.
>
> The cask lives in a personal tap and is not reviewed by Homebrew. It points to the same dmg; its `sha256` is computed by CI from that dmg and matches `SHA256SUMS`.

### Option 3: from source

| Need | Check | Install |
| --- | --- | --- |
| macOS 13 or later | `sw_vers -productVersion` | system update |
| Xcode command line tools (`swift`, `clang`, `git`) | `xcode-select -p` prints a path | `xcode-select --install` (2–5 GB, 5–15 min) |
| ~2 GB free disk | — | — |

No Node, no Python, no Homebrew, no paid Apple Developer account.

```bash
git clone https://github.com/slow-coding/ds-meter
cd ds-meter
./scripts/build-app.sh
open "/Applications/DS Meter.app"
```

Wait for `xcode-select --install` to finish before building, or you will get `swift: command not found`.

### About signing

- Distributed builds are **ad-hoc signed** (`codesign --sign -`): integrity is verifiable, identity is not. That is why macOS asks once, and why no one can trace a build back to a developer.
- No notarization: that needs the $99/year Apple Developer Program, and it would ask every user to trust one person's certificate.
- Building locally is ad-hoc too; bring your own certificate with `SIGN_ID="Apple Development: Your Name (XXXXXXXXXX)" ./scripts/build-app.sh` if you want a stable identity.
- A locally built app has no `com.apple.quarantine` flag, so Gatekeeper stays out of the way.

The first run registers a login item (can be turned off). Uninstall with `./scripts/uninstall.sh`, which removes the app, the login item, credentials, the web sign-in state and caches.

### Troubleshooting

- `swift: command not found` → command line tools are missing: rerun `xcode-select --install`.
- `xcodebuild: error: tool requires Xcode` → full Xcode installed but license not accepted: `sudo xcodebuild -license accept`.
- "App is damaged" → run `xattr -dr com.apple.quarantine "/Applications/DS Meter.app"` first; if it persists, the download is corrupt — check sha256.
- Just want the binary, no app: `swift build -c release`, then run `.build/release/DSMeter`.

## Two ways to use it

**Sign in (recommended)**: full billing view. Menu bar → Sign in on web, or press the button in the panel.

**API key only**: balance only. Right-click → Account… → paste your `sk-` key. Settings has three tabs: General (login item, refresh rate, language), Account (the two credentials), About (pricing and data notes).

With neither configured, the first launch opens the panel by itself with one explanation and one button.

## Where the numbers come from

| Shown | Source | Precision |
| --- | --- | --- |
| Balance | `api.deepseek.com/user/balance` (`sk-`) | live, to the cent |
| Today / hourly / per-model / cache hit / last 30 days / runway | `platform.deepseek.com/api/v0/usage/by_api_key/{cost,amount}` (sign-in) | same data as the web usage page, ~5 min behind |

## Known limits

- The billing endpoint returns at most 30 days at a time.
- Public holidays are not detected: a holiday treated as a workday overprices the peak segment by 2×.
- Only the signed-in account's billing; balance is account-wide.
- Billing data lags ~5 minutes.
- The sign-in expires; press the button again to refresh it.
- The endpoint is undocumented. Paths or rate limits may change; if so, the app stops reading (2-minute polling with exponential backoff, 15 minutes max).

## Pricing reference

Peak: Beijing time, **workdays** 9–12 and 14–18, double price. Everything else is off-peak (half of peak).

CNY per million tokens (off-peak → peak):

- `deepseek-flash`: hit 0.02 → 0.04, miss 1 → 2, output 4 → 8
- `deepseek-v4-pro`: hit 0.15 → 0.30, miss 4.5 → 9, output 13.5 → 27

Price page: https://api-docs.deepseek.com/zh-cn/quick_start/pricing

## Development

```bash
swift build -c release

.build/release/DSMeter --probe                                               # real data, print numbers
.build/release/DSMeter --probe --demo --snapshot /tmp/dsm --status /tmp/dsm  # demo data, render PNGs
.build/release/DSMeter --probe --demo --logged-out --snapshot /tmp/dsm       # the "not signed in" screen
.build/release/DSMeter --probe --fresh --snapshot /tmp/dsm                   # the "first launch" screen
.build/release/DSMeter --probe --fresh --settings-shot --snapshot /tmp/dsm   # the settings window
.build/release/DSMeter --probe --login-check --snapshot /tmp/dsm             # opens the sign-in window
.build/release/DSMeter --probe --demo --scale 3 --snapshot /tmp/dsm \
  && cp /tmp/dsm/panel.png docs/panel.png                                     # the README panel image (demo data)
swift scripts/make-banner.swift                                              # regenerate the banner

./scripts/package-release.sh                                                 # build a dmg + SHA256SUMS
REPO=owner/ds-meter ./scripts/package-release.sh                             # also emit the Homebrew cask
```

Packaging details live in [`packaging/README.md`](packaging/README.md).

All images in the README are rendered from `--demo` (fake data). No real screenshots: balance, spend, token counts, menu bar and wallpaper are public the moment they land in a repo, and stay retrievable by SHA after removal.

## License

MIT — see `LICENSE`.
