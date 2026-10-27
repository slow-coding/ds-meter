# 隐私说明（DS Meter）

这个 app 把你自己这台 Mac 上的 AI 花费显示在菜单栏上。它没有服务器，没有账号体系，没有统计上报，也没有第三方 SDK。非官方工具，跟 DeepSeek 无关。

## 它拿到什么

| 东西 | 从哪来 | 干什么用 |
| --- | --- | --- |
| API Key（`sk-…`） | 你填的 | 向 `api.deepseek.com/user/balance` 查余额 |
| 登录态（`userToken`） | 你在 app 里的登录窗口登录后，它从页面自己的 localStorage 里读 | 向 `platform.deepseek.com` 读账单：今日、每小时、分模型、命中率 |

登录窗口就是 app 里的一个浏览器（WKWebView），打开 `platform.deepseek.com` 的登录页。手机号、验证码、密码、微信扫码都在你和 DeepSeek 之间，app 不读你输入的内容。

读到 token 之后，app 会先拿账单接口验一次，验得过才存；没登录时站点写的 `{"value":null}` 空壳验不过，不会被当成 token。

## 存在哪

- 两串凭据：`~/Library/Application Support/DSMeter/account.json`，目录 0700、文件 0600。不进日志。
  - 为什么不用钥匙串：自编译的 app 每次签名都可能变，钥匙串会认不出同一个 app，读一次弹一次密码框。老版本存在钥匙串里的那条会启动时搬进这个文件，之后不再读它。
- 网页登录态：`~/Library/WebKit/app.dsmeter.macos`（cookie、localStorage）。设置里「退出网页登录」会把它们一起删掉。
- 刷新间隔这个偏好：`UserDefaults`。
- 账单响应只在内存里，关掉了磁盘缓存。

## 发给谁

两个地方：`https://api.deepseek.com/user/balance`（余额）、`https://platform.deepseek.com/api/v0/usage/*`（账单）。

没有别的网络请求，也没有自动更新。

## 不会做什么

- 不读你的对话内容，不读模型的输入输出，不读会话日志，不读别的 app 的数据。
- 不把任何数据传到开发者这边（没有这样的服务器）。
- 不写 `~/Library/LaunchAgents`（开机自启用的是 LaunchAgent，只在你打开这个开关时写，关掉就删）。

## 撤回

- 设置里「退出网页登录」→ 网页登录态和存下来的 token 一起删；再点「删除已存凭据」→ 连 `sk-` key 一起删。
- `scripts/uninstall.sh` 把 app、自启、偏好、凭据、网页登录态、缓存全部清掉。
