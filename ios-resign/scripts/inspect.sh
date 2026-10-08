#!/bin/bash
# ios-resign 設定模式的偵察：只讀不寫，列出產生 resign.yaml／resign.local.yaml 需要的事實。
#
#   inspect.sh                    列出目前資料夾底下的 .xcodeproj、Xcode 團隊、配對過的 iPhone
#   inspect.sh <專案.xcodeproj>    另外列出每個會產出 App 的 scheme：bundle ID、團隊、最低 iOS
#
# 產生設定、問使用者確認是 agent 的事（見 SKILL.md）。相容 macOS 內建 /bin/bash 3.2。
set -uo pipefail

section() { printf '\n## %s\n' "$1"; }

section "Xcode"
if xcodebuild -version >/dev/null 2>&1; then
    echo "$(xcodebuild -version | head -1)，iOS SDK $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 讀不到)"
    echo "位置：$(xcode-select -p)"
else
    echo "xcodebuild 跑不起來：Xcode 沒裝、沒接受授權（sudo xcodebuild -license accept），或沒跑首次設定（sudo xcodebuild -runFirstLaunch）"
fi
[ -x /usr/bin/ruby ] && echo "Ruby：$(/usr/bin/ruby -e 'print RUBY_VERSION')（讀 YAML 用）" || echo "Ruby：找不到 /usr/bin/ruby（讀 YAML 要用）"

section "Xcode 登入的團隊"
teams="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null)"
if [ -z "${teams}" ]; then
    echo "沒有：Xcode › Settings › Accounts 還沒登入 Apple ID（要人在螢幕前做，有雙重認證）"
else
    # 每筆是 isFreeProvisioningTeam／teamID／teamName／teamType 四行
    echo "${teams}" | awk -F' = ' '
        /isFreeProvisioningTeam/ { free=$2; sub(/;/,"",free) }
        /teamID/   { id=$2; sub(/;/,"",id) }
        /teamName/ { name=$2; sub(/;$/,"",name) }
        /teamType/ { type=$2; sub(/;$/,"",type); printf "%s  %s  %s%s\n", id, name, type, (free=="1" ? "（免費個人團隊）" : "") }'
fi

section "配對過的 iPhone"
json="$(mktemp -t ios-resign-devices)"
if xcrun devicectl list devices --json-output "${json}" >/dev/null 2>&1; then
    i=0
    while name="$(plutil -extract "result.devices.${i}.deviceProperties.name" raw "${json}" 2>/dev/null)"; do
        if [ "$(plutil -extract "result.devices.${i}.hardwareProperties.platform" raw "${json}" 2>/dev/null)" = "iOS" ] \
            && [ "$(plutil -extract "result.devices.${i}.hardwareProperties.reality" raw "${json}" 2>/dev/null)" = "physical" ]; then
            printf '%s  udid=%s  iOS %s  %s  連線=%s\n' "${name}" \
                "$(plutil -extract "result.devices.${i}.hardwareProperties.udid" raw "${json}" 2>/dev/null)" \
                "$(plutil -extract "result.devices.${i}.deviceProperties.osVersionNumber" raw "${json}" 2>/dev/null || echo ?)" \
                "$(plutil -extract "result.devices.${i}.hardwareProperties.marketingName" raw "${json}" 2>/dev/null)" \
                "$(plutil -extract "result.devices.${i}.connectionProperties.tunnelState" raw "${json}" 2>/dev/null)"
        fi
        i=$((i + 1))
    done
    echo "（開發者模式要接通後才讀得到，重簽時腳本會逐支檢查）"
else
    echo "devicectl 讀不到裝置清單"
fi
rm -f "${json}"

if [ $# -eq 0 ]; then
    section "目前資料夾底下的 Xcode 專案"
    find . -maxdepth 5 -name '*.xcodeproj' -not -path '*/.claude/*' -not -path '*/DerivedData/*' -not -path '*/Pods/*' 2>/dev/null \
        | sed 's#^\./##' | sort
    exit 0
fi

proj="$1"
[ -d "${proj}" ] || { echo "找不到 ${proj}" >&2; exit 1; }
section "${proj} 的 scheme（只列會產出 App 的）"
schemes="$(xcodebuild -list -project "${proj}" 2>/dev/null | sed -n '/Schemes:/,$p' | tail -n +2 | sed 's/^ *//' | grep -v '^$')"
[ -n "${schemes}" ] || { echo "讀不到 scheme（共用 scheme 沒勾 Shared？）"; exit 0; }
# 從 fd 3 讀，xcodebuild 才不會把迴圈的輸入吃掉
while IFS= read -r -u 3 s; do
    settings="$(xcodebuild -project "${proj}" -scheme "${s}" -sdk iphoneos -showBuildSettings 2>/dev/null </dev/null)"
    get() { echo "${settings}" | sed -n "s/^ *$1 = //p" | head -1; }
    [ "$(get WRAPPER_EXTENSION)" = "app" ] || continue
    printf -- '- scheme: %s\n  bundle_id: %s\n  team: %s\n  configuration: %s\n  最低 iOS: %s\n  App 名稱: %s\n' \
        "${s}" "$(get PRODUCT_BUNDLE_IDENTIFIER)" "$(get DEVELOPMENT_TEAM)" "$(get CONFIGURATION)" \
        "$(get IPHONEOS_DEPLOYMENT_TARGET)" "$(get PRODUCT_NAME)"
done 3<<<"${schemes}"
