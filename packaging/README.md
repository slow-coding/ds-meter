# 打包与分发

这里只放「怎么把 app 交到别人手上」的东西，代码和规则不在这里。

## 一个产物，两条通道

- **dmg**：`dist/DS-Meter-<版本>.dmg`，universal（arm64 + x86_64），**ad-hoc 签名**（`codesign --sign -`），没有任何人的证书，也没有公证。
- **Homebrew cask**：`dist/ds-meter.rb`，指向同一个 dmg，带 sha256。实测 brew 装出来虽然带 quarantine 标记，但 macOS 不弹窗（包管理器这一类）；浏览器下载的 dmg 会弹。

## 在本地打一版

```bash
./scripts/package-release.sh                 # 出 dmg + SHA256SUMS
REPO=owner/ds-meter ./scripts/package-release.sh   # 顺带出 cask（URL 用 owner/ds-meter）
```

产物进 `dist/`，不进 Git（`.gitignore` 已经挡住）。

## 发版（CI）

推一个 tag 就行，GitHub Actions 在干净的 macOS runner 上编（没有任何证书、任何 secret）：

```bash
# VERSION 和 tag 要对得上
echo 1.0.0 > VERSION && git commit -am "1.0.0" && git tag v1.0.0 && git push && git push --tags
```

workflow 会：编 universal → ad-hoc 签名 → 打 dmg → 算 sha256 → 生成 cask → 建 Release，资产是 `DS-Meter-<版本>.dmg`、`SHA256SUMS`、`ds-meter.rb`。

## 更新 Homebrew tap

cask 要放在一个 tap 仓库里（比如 `homebrew-ds-meter`），结构就一个文件：

```
homebrew-ds-meter/
└── Casks/
    └── ds-meter.rb
```

每次发版：把 Release 里的 `ds-meter.rb` 拷进 `Casks/`，提交。用户这样装（不用先 `brew tap`）：

```bash
brew tap <账号>/ds-meter
brew trust <账号>/ds-meter
brew install --cask ds-meter
```

以后想自动化：在那个 tap 仓库里加一个 workflow，用 `workflow_dispatch` 收 release 产物，或者给主仓一个只对 tap 有写权限的 deploy key。别把个人 token 放进主仓的 secrets。

## 为什么不签名

签名的包会挂在某个人或某个组织的证书下，每个拷贝都能 `codesign -dvvv` 查出来。这个项目选择不签：谁都不挂，代价是直连下载的人要放行一次 Gatekeeper，或者走 brew。

想改成签名分发，需要的不是代码，是：

1. 一个 Apple Developer Program 账号（99 美元/年，组织账号还要 D-U-N-S）；
2. Developer ID Application 证书；
3. CI 里 `codesign` → `notarytool submit --wait` → `stapler staple`；
4. 想清楚这个证书代表谁。
