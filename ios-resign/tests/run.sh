#!/bin/bash
# ios-resign 腳本的離線測試：用假的 xcodebuild／xcrun（含 devicectl）／defaults／security／codesign，
# 不需要 Xcode 帳號、不碰任何手機。真的 Ruby 與 plutil 照用（YAML 與裝置 JSON 的解析是實測）。
#
#   tests/run.sh                      測 ../scripts
#   SCRIPTS=<別的 scripts 資料夾> tests/run.sh   突變測試用（tests/mutate.sh）
#
# 每個案例：建一個假專案（resign.yaml＋假 .xcodeproj），設定假工具的行為，跑 resign.sh，比對結束碼與輸出。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="${SCRIPTS:-$(cd "${HERE}/../scripts" && pwd)}"
T="$(mktemp -d -t ios-resign-test)"
trap 'rm -rf "${T}"' EXIT
PASS=0 FAIL=0

# ---------- 假工具 ----------
STUBS="${T}/stubs"
mkdir -p "${STUBS}"
cat >"${STUBS}/xcodebuild" <<'EOF'
#!/bin/bash
echo "xcodebuild $*" >>"${STUB_LOG}"
case " $* " in
  *" -version "*) echo "Xcode 27.0"; echo "Build version TEST"; exit 0 ;;
  *" -showBuildSettings "*)
    [ "${STUB_SETTINGS_RC:-0}" = 0 ] || exit "${STUB_SETTINGS_RC}"
    echo "    PRODUCT_BUNDLE_IDENTIFIER = ${STUB_BUNDLE:-com.example.app}"
    echo "    IPHONEOS_DEPLOYMENT_TARGET = ${STUB_DEPLOY:-27.0}"
    echo "    WRAPPER_EXTENSION = app"
    exit 0 ;;
esac
dd="" cfg="Debug"
while [ $# -gt 0 ]; do
  case "$1" in -derivedDataPath) dd="$2"; shift ;; -configuration) cfg="$2"; shift ;; esac
  shift
done
[ "${STUB_BUILD_RC:-0}" = 0 ] || { echo "error: stub build failed"; exit "${STUB_BUILD_RC}"; }
mkdir -p "${dd}/Build/Products/${cfg}-iphoneos/App.app"
echo stub >"${dd}/Build/Products/${cfg}-iphoneos/App.app/embedded.mobileprovision"
echo "** BUILD SUCCEEDED **"
EOF
cat >"${STUBS}/xcrun" <<'EOF'
#!/bin/bash
echo "xcrun $*" >>"${STUB_LOG}"
if [ "$1" = "--sdk" ]; then echo "${STUB_SDK:-27.0}"; exit 0; fi
[ "$1" = "devicectl" ] || exit 1
shift
out="" dev=""
args="$*"
while [ $# -gt 0 ]; do
  case "$1" in --json-output) out="$2"; shift ;; --device) dev="$2"; shift ;; esac
  shift
done
case "${args}" in
  "device info details"*)
    case " ${STUB_UNREACHABLE:-} " in *" ${dev} "*) exit 1 ;; esac
    mode=enabled
    case " ${STUB_DEVMODE_OFF:-} " in *" ${dev} "*) mode=disabled ;; esac
    printf '{"result":{"connectionProperties":{"pairingState":"paired"},"deviceProperties":{"developerModeStatus":"%s"}}}' "${mode}" >"${out}" ;;
  "device info apps"*)
    printf '{"result":{"apps":[%s]}}' "${STUB_APPS:-}" >"${out}" ;;
  "device install app"*) exit "${STUB_INSTALL_RC:-0}" ;;
  "device process launch"*)
    case "${STUB_LAUNCH:-ok}" in
      ok) echo "Launched application" ;;
      untrusted) echo 'ERROR: The request was denied by service delegate (SBMainWorkspace) for reason: Security ("Unable to launch x because it has an invalid code signature, inadequate entitlements or its profile has not been explicitly trusted by the user").'; exit 1 ;;
      locked) echo 'ERROR: The request was denied by service delegate (SBMainWorkspace) for reason: Locked ("Unable to launch x because the device was not, or could not be, unlocked").'; exit 1 ;;
      *) echo "ERROR: something else (com.apple.dt.CoreDeviceError error 1.)"; exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
cat >"${STUBS}/defaults" <<'EOF'
#!/bin/bash
[ "${STUB_NO_ACCOUNT:-0}" = 1 ] && exit 1
cat <<TEAMS
{
    "UUID-1" =         (
                        {
                isFreeProvisioningTeam = 0;
                teamID = COMPANY111;
                teamName = "Some Company";
                teamType = Company;
            },
                        {
                isFreeProvisioningTeam = 1;
                teamID = PERSONAL11;
                teamName = "Test User (Personal Team)";
                teamType = "Personal Team";
            }
        );
}
TEAMS
EOF
cat >"${STUBS}/security" <<'EOF'
#!/bin/bash
cat <<P
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>ExpirationDate</key><date>2030-01-08T00:00:00Z</date></dict></plist>
P
EOF
cat >"${STUBS}/codesign" <<'EOF'
#!/bin/bash
echo "Authority=Apple Development: test@example.com (ABC123)" >&2
EOF
chmod +x "${STUBS}"/*

# ---------- 案例工具 ----------
new_project() {  # 建假專案，印出路徑；resign.yaml 內容由 stdin 提供
    local p="${T}/proj-$((PASS + FAIL))-${RANDOM}"
    mkdir -p "${p}/App.xcodeproj" "${p}/sub/dir"
    git -C "${p}" init -q
    cat >"${p}/resign.yaml"
    echo "${p}"
}
local_yaml() { cat >"$1/resign.local.yaml"; }

BASE_YAML='name: 測試 App
project: App.xcodeproj
team: PERSONAL11
variants:
  prod:
    scheme: App
    bundle_id: com.example.app'

TWO_PHONES='devices:
  - name: My Phone
    udid: UDID-A
  - name: Old iPhone
    udid: UDID-B'

run() {  # run <專案> [參數...]：在專案資料夾跑，輸出存 OUT，結束碼存 RC
    local p="$1"; shift
    export STUB_LOG="${T}/stub.log"
    : >"${STUB_LOG}"
    OUT="$(cd "${p}" && env PATH="${STUBS}:${PATH}" IOS_RESIGN_CACHE="${T}/cache" \
        /bin/bash "${SCRIPTS}/resign.sh" "$@" 2>&1)"
    RC=$?
}

check() {  # check <說明> <條件...>
    local label="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); echo "PASS ${label}"
    else FAIL=$((FAIL + 1)); echo "FAIL ${label}"; echo "  RC=${RC}"; echo "${OUT}" | sed 's/^/  | /' | tail -12; fi
}
rc_is() { [ "${RC}" = "$1" ]; }
out_has() { echo "${OUT}" | grep -qF -- "$1"; }
out_lacks() { ! echo "${OUT}" | grep -qF -- "$1"; }
log_has() { grep -qF -- "$1" "${STUB_LOG}"; }
log_lacks() { ! grep -qF -- "$1" "${STUB_LOG}"; }
all() { local c; for c in "$@"; do eval "${c}" || return 1; done; }

reset_stubs() {
    unset STUB_BUNDLE STUB_DEPLOY STUB_SDK STUB_BUILD_RC STUB_INSTALL_RC STUB_LAUNCH STUB_UNREACHABLE \
          STUB_DEVMODE_OFF STUB_APPS STUB_NO_ACCOUNT STUB_SETTINGS_RC
}
export_stubs() { export STUB_BUNDLE STUB_DEPLOY STUB_SDK STUB_BUILD_RC STUB_INSTALL_RC STUB_LAUNCH \
                 STUB_UNREACHABLE STUB_DEVMODE_OFF STUB_APPS STUB_NO_ACCOUNT STUB_SETTINGS_RC 2>/dev/null; }

# ---------- 案例 ----------
reset_stubs; export_stubs
P="$(echo "${BASE_YAML}" | new_project)"; echo "${TWO_PHONES}" | local_yaml "${P}"

run "${P}" --list
check "--list 列出版本與手機" all 'rc_is 0' 'out_has "版本 prod：scheme App"' 'out_has "My Phone（UDID-A）"'

run "${P}/sub/dir" --list
check "從子資料夾往上找到 resign.yaml" all 'rc_is 0' 'out_has "測試 App"'

E="${T}/empty"; mkdir -p "${E}"; git -C "${E}" init -q
run "${E}"
check "找不到 resign.yaml → 10" all 'rc_is 10' 'out_has "找不到 resign.yaml"'

run "${P}"
check "兩支手機都成功 → 0，名稱有空格也行" all 'rc_is 0' 'out_has "✔ [My Phone] 完成"' 'out_has "✔ [Old iPhone] 完成"' 'log_has "device process launch --device UDID-B"'
check "沒刻意覆蓋就不帶 PRODUCT_BUNDLE_IDENTIFIER" log_lacks "PRODUCT_BUNDLE_IDENTIFIER="
check "團隊從命令列帶入" log_has "DEVELOPMENT_TEAM=PERSONAL11"

run "${P}" "old iphone"
check "點名手機（不分大小寫、含空格）只簽那支" all 'rc_is 0' 'out_has "✔ [Old iPhone]"' 'out_lacks "[My Phone]"'

run "${P}" udid-a
check "用 UDID 點名" all 'rc_is 0' 'out_has "✔ [My Phone]"' 'out_lacks "[Old iPhone]"'

run "${P}" nosuch
check "點名不存在的手機 → 16 並列出可用名稱" all 'rc_is 16' 'out_has "可用的有：My Phone、Old iPhone"'

run "${P}" --build-only
check "--build-only → 0 且不碰手機" all 'rc_is 0' 'out_has "只編譯模式完成"' 'log_lacks "devicectl"' 'log_has "generic/platform=iOS"'

STUB_UNREACHABLE="UDID-A"; export_stubs
run "${P}"
check "一支連不到 → 13，另一支照樣完成" all 'rc_is 13' 'out_has "✖ [My Phone] 連不到"' 'out_has "✔ [Old iPhone] 完成"' 'out_has "RESIGN_EXIT=13 DEVICE=My Phone"'
reset_stubs; export_stubs

STUB_DEVMODE_OFF="UDID-B"; export_stubs
run "${P}" "Old iPhone"
check "開發者模式沒開 → 14" all 'rc_is 14' 'out_has "沒開開發者模式"'
reset_stubs; export_stubs

STUB_APPS='{"bundleIdentifier":"a.one","name":"一","builtByDeveloper":true},{"bundleIdentifier":"a.two","name":"二","builtByDeveloper":true},{"bundleIdentifier":"a.three","name":"三","builtByDeveloper":true},{"bundleIdentifier":"store.app","name":"商店","builtByDeveloper":false}'; export_stubs
run "${P}" "My Phone"
check "自簽 App 已 3 個且要裝的不在上面 → 17，列出那三個" all 'rc_is 17' 'out_has "已經 3 個"' 'out_has "一（a.one）"' 'out_lacks "商店"' 'log_lacks "-destination id="'
run "${P}" "My Phone" --allow-over-limit
check "--allow-over-limit 照裝" rc_is 0
STUB_APPS='{"bundleIdentifier":"a.one","name":"一","builtByDeveloper":true},{"bundleIdentifier":"a.two","name":"二","builtByDeveloper":true},{"bundleIdentifier":"com.example.app","name":"測試","builtByDeveloper":true}'; export_stubs
run "${P}" "My Phone"
check "已滿 3 個但要裝的本來就在 → 覆蓋安裝" rc_is 0
reset_stubs; export_stubs

STUB_BUILD_RC=65; export_stubs
run "${P}" "My Phone"
check "編譯失敗 → 20 並印錯誤摘要" all 'rc_is 20' 'out_has "錯誤摘要"' 'out_has "stub build failed"'
reset_stubs; export_stubs

STUB_INSTALL_RC=1; export_stubs
run "${P}" "My Phone"
check "安裝失敗 → 30" all 'rc_is 30' 'out_has "安裝失敗"'
reset_stubs; export_stubs

STUB_LAUNCH=untrusted; export_stubs
run "${P}" "My Phone"
check "沒信任開發者 → 31，訊息是部署成功＋信任路徑" all 'rc_is 31' 'out_has "部署成功，請在手機上確認憑證信任"' 'out_has "Apple Development: test@example.com"'
STUB_LAUNCH=locked; export_stubs
run "${P}" "My Phone"
check "手機鎖著 → 32" all 'rc_is 32' 'out_has "部署成功，但手機鎖著"'
STUB_LAUNCH=weird; export_stubs
run "${P}" "My Phone"
check "其他啟動失敗 → 33" all 'rc_is 33' 'out_has "原因不明"'
reset_stubs; export_stubs

STUB_BUNDLE=com.other.app; export_stubs
run "${P}" --build-only
check "bundle ID 跟專案對不上 → 10" all 'rc_is 10' 'out_has "跟專案實際的"'
reset_stubs; export_stubs

STUB_SDK=26.5; export_stubs
run "${P}" --build-only
check "SDK 太舊 → 11" all 'rc_is 11' 'out_has "Xcode 太舊"'
reset_stubs; export_stubs

STUB_SETTINGS_RC=66; export_stubs
run "${P}" --build-only
check "讀不到專案設定 → 11" rc_is 11
reset_stubs; export_stubs

STUB_NO_ACCOUNT=1; export_stubs
run "${P}" --build-only
check "Xcode 沒登入 → 15" all 'rc_is 15' 'out_has "沒登入"'
reset_stubs; export_stubs

P2="$(printf '%s\n' "${BASE_YAML}" | sed 's/team: PERSONAL11/team: COMPANY111/' | new_project)"
run "${P2}" --build-only
check "公司團隊 → 15 拒絕" all 'rc_is 15' 'out_has "不是免費個人團隊"'
printf 'allow_paid_team: "true"\n' | local_yaml "${P2}"
run "${P2}" --build-only
check "allow_paid_team: \"true\" 才准付費團隊" rc_is 0

P3="$(printf '%s\nprebuild: touch prebuild-ran && exit 3\n' "${BASE_YAML}" | new_project)"
run "${P3}" --build-only
check "建置前指令失敗 → 12，且在 repo 根目錄執行" all 'rc_is 12' '[ -f "${P3}/prebuild-ran" ]'

P4="$(printf '%s\ndevices:\n  - name: x\n    udid: y\n' "${BASE_YAML}" | new_project)"
run "${P4}" --list
check "devices 寫在 resign.yaml → 10" all 'rc_is 10' 'out_has "不該寫 devices"'

run "${P}" --variant nope
check "不存在的版本 → 10" all 'rc_is 10' 'out_has "沒有叫「nope」的版本"'

P5="$(printf '%s\n  dev:\n    scheme: App-dev\n    bundle_id: com.example.app.dev\n    configuration: Debug-Dev\n' "${BASE_YAML}" | new_project)"
run "${P5}" --build-only
check "多版本沒寫 default_variant → 10" all 'rc_is 10' 'out_has "有好幾個版本"'
STUB_BUNDLE=com.example.app.dev; export_stubs
run "${P5}" --build-only --variant dev
check "--variant dev 用它自己的 scheme 與 configuration" all 'rc_is 0' 'log_has "-scheme App-dev -configuration Debug-Dev"'
printf 'default_variant: dev\n' | local_yaml "${P5}"
run "${P5}" --build-only
check "寫了 default_variant 就照它選版本" all 'rc_is 0' 'out_has "版本 dev（scheme App-dev）"' 'log_has "-scheme App-dev"'
reset_stubs; export_stubs

P6="$(echo "${BASE_YAML}" | new_project)"
printf 'variants:\n  prod:\n    bundle_id: com.friend.app\n' | local_yaml "${P6}"
run "${P6}" --build-only
check "本機設定改 bundle ID → 從命令列覆蓋" all 'rc_is 0' 'log_has "PRODUCT_BUNDLE_IDENTIFIER=com.friend.app"'

run "${P6}"
check "本機設定沒列手機、又不是 --build-only → 10" all 'rc_is 10' 'out_has "沒有列任何手機"'

P7="$(printf 'name: v\nproject: App.xcodeproj\nteam: PERSONAL11\nvariants:\n  prod:\n    scheme: S\n    bundle_id: 1.10\n' | new_project)"
OUT="$(/usr/bin/ruby "${SCRIPTS}/config.rb" env "${P7}/resign.yaml" 2>&1)"; RC=$?
check "YAML 值保持原始字串（1.10 不會變 1.1）" all 'rc_is 0' 'out_has "RESIGN_BUNDLE_ID=1.10"'

printf 'name: [壞掉\n' >"${P7}/resign.yaml"
run "${P7}" --list
check "YAML 語法錯 → 10" all 'rc_is 10' 'out_has "YAML 寫錯"'

OUT="$(cd "${P}" && env PATH="${STUBS}:${PATH}" IOS_RESIGN_RUBY=/nonexistent/ruby /bin/bash "${SCRIPTS}/resign.sh" --list 2>&1)"; RC=$?
check "找不到 Ruby → 18" all 'rc_is 18' 'out_has "找不到 /nonexistent/ruby"'

echo
echo "通過 ${PASS}，失敗 ${FAIL}"
[ "${FAIL}" -eq 0 ]
