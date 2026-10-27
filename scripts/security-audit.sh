#!/bin/bash
# 安全体检：发版前必须过。查工作区、全部 git 对象（含历史）、网络域名白名单、外部依赖、可选查一个二进制。
#   ./scripts/security-audit.sh            # 查仓库
#   ./scripts/security-audit.sh <binary>   # 再查一个二进制里的字符串
# 有命中就退出码 1。
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
# 凭据形态 / 身份 / 家目录 / 邮箱。
# 身份那几条要拆开写：整串出现在这个脚本里，扫描会把自己也当命中。
name_xu='Xu'' Zheng'
name_cn='郑''旭'
cert_serial='962''JAF'
team_id='EJV''RL'
pattern="sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.|/Users/[A-Za-z0-9._-]+|$cert_serial|$team_id|$name_xu|$name_cn|@qq\.com|@kingdee\.com"

say() { printf '%s\n' "$*"; }

say "1) 工作区"
hits=$(grep -rInaE "$pattern" \
    --exclude-dir=.git --exclude-dir=dist --exclude-dir=.build --exclude-dir=.lab . 2>/dev/null || true)
if [ -n "$hits" ]; then say "$hits"; say "  ✗ 有命中"; fail=1; else say "  ✓ 无凭据 / 身份 / 家目录"; fi

say "2) 全部 git 对象（含历史，解压后扫）"
count=0
while read -r sha; do
    if git cat-file blob "$sha" 2>/dev/null | grep -aqE "$pattern"; then
        say "  ✗ HIT $sha"
        fail=1
        count=$((count + 1))
    fi
done <<< "$(git cat-file --batch-all-objects --batch-check='%(objectname) %(objecttype)' | awk '$2=="blob"{print $1}')"
[ "$count" -eq 0 ] && say "  ✓ 历史里也没有"

say "3) 网络域名白名单"
allowed="api.deepseek.com platform.deepseek.com api-docs.deepseek.com github.com www.apple.com 127.0.0.1"
domains=$(grep -rhoE "https?://[A-Za-z0-9._-]+" Sources scripts .github packaging README.md 2>/dev/null \
    | sed -E 's#https?://##' | sort -u)
bad=0
for d in $domains; do
    case " $allowed " in
        *" $d "*) ;;
        *) say "  ✗ 未列入白名单: $d"; bad=1; fail=1 ;;
    esac
done
[ "$bad" -eq 0 ] && say "  ✓ 只有 $(printf '%s' "$domains" | wc -w | tr -d ' ') 个已知域名"

say "4) 依赖与入库文件"
if grep -q "dependencies:" Package.swift 2>/dev/null; then say "  ✗ Package.swift 里有外部依赖"; fail=1; else say "  ✓ 无外部依赖"; fi
if git ls-files | grep -qE '(^|/)(account\.json|\.env)$|\.(p12|pem|key)$'; then
    say "  ✗ 凭据文件进了仓库"; fail=1
else
    say "  ✓ 没有凭据文件进仓库"
fi
if git ls-files | grep -qE '^dist/'; then say "  ✗ dist/ 被提交了"; fail=1; else say "  ✓ 打包产物没进仓库"; fi

say "5) 程序不写日志"
if grep -rnE "(NSLog|os_log|Logger\()" Sources >/dev/null 2>&1; then
    say "  ✗ 代码里有系统日志调用"; fail=1
else
    say "  ✓ 没有 NSLog / os_log / Logger"
fi
if grep -rnE "write\(to: URL\(fileURLWithPath: \"/tmp" Sources >/dev/null 2>&1; then
    say "  ✗ 有往 /tmp 写文件的代码"; fail=1
else
    say "  ✓ 不往 /tmp 写文件"
fi

if [ "${1:-}" != "" ]; then
    say "6) 二进制：$1"
    if strings -a "$1" | grep -aqE "$pattern"; then say "  ✗ 二进制里有命中"; fail=1; else say "  ✓ 干净"; fi
fi

say ""
if [ "$fail" -eq 0 ]; then say "体检通过"; else say "体检没通过，别发版"; fi
exit "$fail"
