#!/bin/bash
# ios-resign：用本機 Xcode 登入的 Apple ID 編譯、簽章，裝到設定好的 iPhone 並打開。
# 免費帳號的描述檔 7 天到期，到期就重跑。設定讀專案的 resign.yaml＋同資料夾的 resign.local.yaml。
#
#   resign.sh                         在專案資料夾（或子資料夾）裡跑：預設版本、本機設定列的全部手機
#   resign.sh <手機名稱或UDID> ...      只裝指定的手機（不分大小寫）
#   resign.sh --variant dev           指定版本
#   resign.sh --config <resign.yaml>  不在專案資料夾時指定設定檔
#   resign.sh --build-only            只編譯簽章，不碰手機
#   resign.sh --list                  列出設定（版本、手機），不編譯
#   resign.sh --allow-over-limit      手機自簽 App 已滿 3 個也照裝（例如其中有付費團隊簽的）
#
# 結束碼是 SKILL.md 的對照表，改這裡要同步改那裡：
#   10 設定  11 Xcode  12 建置前指令  13 手機連不到／沒配對  14 開發者模式  15 團隊
#   16 指定的手機不在設定  17 自簽 App 名額滿  18 缺 Ruby  20 編譯簽章  30 安裝
#   31 已裝好但要在手機上信任開發者  32 已裝好但手機鎖著  33 已裝好但打不開（原因不明）
# 多支手機逐支處理，某支失敗不影響其他支；結束碼取第一個失敗的碼。
# 必須相容 macOS 內建的 /bin/bash 3.2。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBY="${IOS_RESIGN_RUBY:-/usr/bin/ruby}"
CACHE="${IOS_RESIGN_CACHE:-${HOME}/Library/Caches/ios-resign}"

step() { echo "▶ $*"; }
fail() { local code=$1; shift; echo "✖ $*" >&2; echo "RESIGN_EXIT=${code}" >&2; exit "${code}"; }
lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# ---- 參數 ----
CONFIG="" VARIANT="" BUILD_ONLY=0 LIST=0 OVER_LIMIT=0 PICKS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG="${2:-}"; shift 2 ;;
        --variant) VARIANT="${2:-}"; shift 2 ;;
        --build-only) BUILD_ONLY=1; shift ;;
        --list) LIST=1; shift ;;
        --allow-over-limit) OVER_LIMIT=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        --*) fail 10 "不認得的參數 $1" ;;
        *) PICKS="${PICKS}$(lower "$1")"$'\n'; shift ;;   # 換行分隔：手機名稱可能有空格
    esac
done

# ---- 1. 找設定檔：沒指定就從目前資料夾往上找到 git 根目錄為止 ----
if [ -z "${CONFIG}" ]; then
    dir="$(pwd)"
    while :; do
        [ -f "${dir}/resign.yaml" ] && { CONFIG="${dir}/resign.yaml"; break; }
        [ -e "${dir}/.git" ] || [ "${dir}" = "/" ] && break
        dir="$(dirname "${dir}")"
    done
    [ -n "${CONFIG}" ] || fail 10 "目前資料夾往上找不到 resign.yaml：不在專案裡就用 --config 指定，或先跑設定模式"
fi
[ -f "${CONFIG}" ] || fail 10 "找不到設定檔 ${CONFIG}"
[ -x "${RUBY}" ] || fail 18 "找不到 ${RUBY}（讀 YAML 要用 macOS 內建的 Ruby）"

if [ "${LIST}" -eq 1 ]; then
    "${RUBY}" "${SCRIPT_DIR}/config.rb" list "${CONFIG}" || fail 10 "設定檔讀不了"
    exit 0
fi
env_out="$("${RUBY}" "${SCRIPT_DIR}/config.rb" env "${CONFIG}" "${VARIANT}")" || fail 10 "設定檔讀不了（原因見上一行）"
eval "${env_out}"
[ -n "${RESIGN_TEAM}" ] || fail 10 "resign.yaml 缺 team（個人團隊 ID，設定模式會幫你查）"
step "專案：${RESIGN_NAME}，版本 ${RESIGN_VARIANT}（scheme ${RESIGN_SCHEME}）"

# 加路徑雜湊：同名資料夾（例如不同 repo 的 worktree）才不會共用 DerivedData、拿到別人的 .app
WORK="${CACHE}/$(basename "${RESIGN_ROOT}")-$(printf '%s' "${RESIGN_ROOT}" | shasum | cut -c1-8)-${RESIGN_VARIANT}"
DERIVED="${WORK}/DerivedData"
mkdir -p "${WORK}"

# ---- 2. Xcode：讀專案實際的設定，順便核對 bundle ID ----
settings="$(xcodebuild -project "${RESIGN_PROJECT}" -scheme "${RESIGN_SCHEME}" -configuration "${RESIGN_CONFIGURATION}" \
    -sdk iphoneos -showBuildSettings 2>/dev/null)" || fail 11 "xcodebuild 讀不到專案設定（Xcode 沒裝好，或 scheme ${RESIGN_SCHEME} 不存在）"
setting() { echo "${settings}" | sed -n "s/^ *$1 = //p" | head -1; }
need="$(setting IPHONEOS_DEPLOYMENT_TARGET)"
have="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"
[ -n "${have}" ] || fail 11 "找不到 Xcode 的 iOS SDK"
[ -z "${need}" ] || [ "${have%%.*}" -ge "${need%%.*}" ] || fail 11 "Xcode 太舊：iOS SDK ${have}，專案要 ${need} 以上"
step "Xcode：$(xcodebuild -version | head -1)，iOS SDK ${have}"
project_bundle="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
BUNDLE_ARG=()
if [ "${RESIGN_BUNDLE_ID}" != "${project_bundle}" ]; then
    # 只有本機設定刻意改 bundle ID（例如分享出去的版本各簽各的）才從命令列覆蓋；
    # 命令列的值會套到所有 target，專案有 App 擴充功能時會衝突，所以預設不帶
    [ "${RESIGN_BUNDLE_OVERRIDE:-0}" = "1" ] \
        || fail 10 "resign.yaml 的 bundle_id（${RESIGN_BUNDLE_ID}）跟專案實際的（${project_bundle}）不一樣，改其中一邊讓它們一致"
    BUNDLE_ARG=("PRODUCT_BUNDLE_IDENTIFIER=${RESIGN_BUNDLE_ID}")
fi

# ---- 3. 團隊：預設只准用免費個人團隊（同一個 Apple ID 底下可能還有公司團隊） ----
teams="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null)"
grep -q "teamID = ${RESIGN_TEAM};" <<<"${teams}" || fail 15 "Xcode 沒登入擁有團隊 ${RESIGN_TEAM} 的 Apple ID"
if [ "${RESIGN_ALLOW_PAID_TEAM:-0}" != "1" ]; then
    grep -A2 "teamID = ${RESIGN_TEAM};" <<<"${teams}" | grep -q 'Personal Team' \
        || fail 15 "團隊 ${RESIGN_TEAM} 不是免費個人團隊，拒絕簽章（真的要用就在設定寫 allow_paid_team: \"true\"）"
fi

# ---- 4. 建置前指令（專案自己的前置步驟，例如編 Rust） ----
if [ -n "${RESIGN_PREBUILD}" ]; then
    step "建置前指令：${RESIGN_PREBUILD}"
    (cd "${RESIGN_ROOT}" && /bin/bash -c "${RESIGN_PREBUILD}") || fail 12 "建置前指令失敗：${RESIGN_PREBUILD}"
fi

build() {  # $1 destination, $2 log
    xcodebuild -project "${RESIGN_PROJECT}" -scheme "${RESIGN_SCHEME}" -configuration "${RESIGN_CONFIGURATION}" \
        -destination "$1" -derivedDataPath "${DERIVED}" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
        DEVELOPMENT_TEAM="${RESIGN_TEAM}" ${BUNDLE_ARG[@]+"${BUNDLE_ARG[@]}"} \
        build >"$2" 2>&1
}
summarize() {
    echo "---- 錯誤摘要 ----" >&2
    grep -E "error:|Error Domain|maximum number|No Account|No profiles|locked|not been registered" "$1" | sort -u | head -15 >&2
}
# 產物資料夾不一定跟 configuration 同名（target 沒有那個設定時 Xcode 會退回預設的，例如 Release），
# 所以在這個專案專屬的 DerivedData 裡取最新的那個 .app
app_path() { ls -td "${DERIVED}"/Build/Products/*-iphoneos/*.app 2>/dev/null | head -1; }
expiry_of() { security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null; }

# ---- 5. 只編譯 ----
if [ "${BUILD_ONLY}" -eq 1 ]; then
    log="${WORK}/build-generic.log"
    step "只編譯簽章，不碰手機；完整紀錄在 ${log}"
    build "generic/platform=iOS" "${log}" || { summarize "${log}"; fail 20 "編譯或簽章失敗"; }
    app="$(app_path)"
    [ -d "${app}" ] || fail 20 "編譯成功但找不到 .app"
    echo "✔ 只編譯模式完成：${app}（描述檔到期 $(expiry_of "${app}")）"
    exit 0
fi

# ---- 6. 選手機 ----
[ "${RESIGN_DEVICE_COUNT}" -gt 0 ] || fail 10 "resign.local.yaml 沒有列任何手機（設定模式會幫你列），或改用 --build-only"
TARGETS="" NAMES_KNOWN=""   # TARGETS：一行一支「udid|名稱」
i=0
while [ "${i}" -lt "${RESIGN_DEVICE_COUNT}" ]; do
    eval "dn=\${RESIGN_DEVICE_NAME_${i}}; du=\${RESIGN_DEVICE_UDID_${i}}"
    NAMES_KNOWN="${NAMES_KNOWN}、${dn}"
    keep=1
    if [ -n "${PICKS}" ]; then
        keep=0
        while IFS= read -r p; do
            [ -z "${p}" ] && continue
            if [ "${p}" = "$(lower "${dn}")" ] || [ "${p}" = "$(lower "${du}")" ]; then keep=1; fi
        done <<<"${PICKS}"
    fi
    [ "${keep}" -eq 1 ] && TARGETS="${TARGETS}${du}|${dn}"$'\n'
    i=$((i + 1))
done
[ -n "${TARGETS}" ] || fail 16 "設定裡沒有叫「$(echo "${PICKS}" | paste -sd '、' - | sed 's/、$//')」的手機，可用的有：${NAMES_KNOWN#、}"

# ---- 7. 逐支：檢查 → 名額 → 編譯簽章（登記這支手機）→ 安裝 → 啟動 ----
one_device() {
    local udid="$1" name="$2" log details apps n app expiry out developer
    log="${WORK}/build-${name}.log"
    details="${WORK}/device-${udid}.json"
    xcrun devicectl device info details --device "${udid}" --json-output "${details}" >/dev/null 2>&1 \
        || { echo "✖ [${name}] 連不到：插上傳輸線（或跟電腦連同一個 Wi-Fi）、解鎖，第一次要按「信任這部電腦」" >&2; return 13; }
    [ "$(plutil -extract result.connectionProperties.pairingState raw "${details}" 2>/dev/null)" != "unpaired" ] \
        || { echo "✖ [${name}] 還沒跟這台電腦配對：插線、解鎖、按「信任」" >&2; return 13; }
    [ "$(plutil -extract result.deviceProperties.developerModeStatus raw "${details}" 2>/dev/null)" != "disabled" ] \
        || { echo "✖ [${name}] 沒開開發者模式" >&2; return 14; }

    # 免費帳號一支手機最多 3 個自簽 App；要裝的不在手機上、而且已經 3 個，就先停下來
    apps="${WORK}/apps-${udid}.json"
    if [ "${OVER_LIMIT}" -eq 0 ] && xcrun devicectl device info apps --device "${udid}" --json-output "${apps}" >/dev/null 2>&1; then
        local list="" has=0 count=0
        n=0
        while b="$(plutil -extract "result.apps.${n}.bundleIdentifier" raw "${apps}" 2>/dev/null)"; do
            if [ "$(plutil -extract "result.apps.${n}.builtByDeveloper" raw "${apps}" 2>/dev/null)" = "true" ]; then
                [ "${b}" = "${RESIGN_BUNDLE_ID}" ] && has=1
                count=$((count + 1))
                list="${list}、$(plutil -extract "result.apps.${n}.name" raw "${apps}" 2>/dev/null)（${b}）"
            fi
            n=$((n + 1))
        done
        if [ "${has}" -eq 0 ] && [ "${count}" -ge 3 ]; then
            echo "✖ [${name}] 自簽 App 已經 ${count} 個（免費帳號上限 3）：${list#、}。先在手機上刪一個，或確定其中有付費團隊簽的再加 --allow-over-limit" >&2
            return 17
        fi
    fi

    step "[${name}] 編譯與簽章中（第一次約 3～5 分鐘），完整紀錄在 ${log}"
    build "id=${udid}" "${log}" || { summarize "${log}"; echo "✖ [${name}] 編譯或簽章失敗" >&2; return 20; }
    app="$(app_path)"
    [ -d "${app}" ] || { echo "✖ [${name}] 編譯成功但找不到 .app" >&2; return 20; }
    expiry="$(expiry_of "${app}")"

    step "[${name}] 安裝"
    xcrun devicectl device install app --device "${udid}" "${app}" >>"${log}" 2>&1 \
        || { tail -15 "${log}" >&2; echo "✖ [${name}] 安裝失敗" >&2; return 30; }
    step "[${name}] 啟動 App"
    out="${WORK}/launch-${udid}.txt"
    if xcrun devicectl device process launch --device "${udid}" "${RESIGN_BUNDLE_ID}" >"${out}" 2>&1; then
        cat "${out}" >>"${log}"
        echo "✔ [${name}] 完成：已裝好並打開，描述檔到期 ${expiry:-（讀不到）}"
        return 0
    fi
    cat "${out}" >>"${log}"
    # 安裝已成功、只有啟動失敗：devicectl 回 CoreDeviceError 10002，內含 FBSOpenApplicationServiceErrorDomain 的 reason
    developer="$(codesign -dvv "${app}" 2>&1 | sed -n 's/^Authority=\(Apple Development: [^(]*\).*/\1/p' | head -1 | sed 's/ *$//')"
    if grep -qiE "explicitly trusted|Security|untrusted|not trusted" "${out}"; then
        echo "✔ [${name}] 部署成功，請在手機上確認憑證信任：設定 › 一般 › VPN 與裝置管理 › 開發者 App「${developer:-Apple Development}」› 信任（手機要能上網，信任完直接點 App；描述檔到期 ${expiry:-（讀不到）}）"
        return 31
    fi
    if grep -qiE "Locked|could not be, unlocked|device is locked" "${out}"; then
        echo "✔ [${name}] 部署成功，但手機鎖著沒辦法自動打開：解鎖後直接點 App（描述檔到期 ${expiry:-（讀不到）}）"
        return 32
    fi
    tail -8 "${out}" >&2
    echo "✖ [${name}] 已安裝，但 App 打不開，原因不明" >&2
    return 33
}

first_fail=0
# 從 fd 3 讀，xcodebuild／devicectl 才不會把迴圈的輸入吃掉
while IFS='|' read -r -u 3 udid name; do
    [ -z "${udid}" ] && continue
    one_device "${udid}" "${name}"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "RESIGN_EXIT=${rc} DEVICE=${name}" >&2
        [ "${first_fail}" -eq 0 ] && first_fail="${rc}"
    fi
done 3<<<"${TARGETS}"
exit "${first_fail}"
