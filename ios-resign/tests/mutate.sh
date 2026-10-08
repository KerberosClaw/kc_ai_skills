#!/bin/bash
# 突變測試：每次把腳本的一個關鍵判斷改壞，跑 tests/run.sh，測試要失敗（＝抓到）才算數。
# 測試照樣全過的突變＝測試有漏洞，列在最後。
#
#   tests/mutate.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "${HERE}/../scripts" && pwd)"
W="$(mktemp -d -t ios-resign-mutate)"
trap 'rm -rf "${W}"' EXIT
KILLED=0 SURVIVED="" INVALID=""

# 檔案|sed 運算式|說明（sed 用 | 以外的分隔字元）
MUTANTS=$(cat <<'EOF'
resign.sh|s#grep -q 'Personal Team'#true#|拿掉「只准個人團隊」
resign.sh|s#fail 15 "Xcode 沒登入#true "Xcode 沒登入#|拿掉「Xcode 要登入該團隊」
resign.sh|s#RESIGN_BUNDLE_OVERRIDE:-0}" = "1"#RESIGN_BUNDLE_OVERRIDE:-0}" != "x"#|bundle ID 對不上也照樣覆蓋
resign.sh|s#"${count}" -ge 3#"${count}" -ge 4#|App 名額上限改成 4
resign.sh|s#"${has}" -eq 0 \] \&\&#true \&\&#|要裝的已在手機上也算超額
resign.sh|s#return 31#return 0#|沒信任開發者當成完全成功
resign.sh|s#return 32#return 33#|手機鎖著當成原因不明
resign.sh|s#!= "disabled"#!= "never"#|不檢查開發者模式
resign.sh|s#keep=0#keep=1#|點名手機沒作用
resign.sh|s#exit "${first_fail}"#exit 0#|有手機失敗也回 0
resign.sh|s#generic/platform=iOS#id=UDID-A#|只編譯模式也指定手機
resign.sh|s#/bin/bash -c "${RESIGN_PREBUILD}"#true#|不跑建置前指令
resign.sh|s#-ge "${need%%.\*}"#-ge 0#|不檢查 SDK 版本
resign.sh|s#return 30#return 0#|安裝失敗當成功
resign.sh|s#\[ -f "${dir}/resign.yaml" \]#false#|不往上找設定檔
resign.sh|s#DEVELOPMENT_TEAM="${RESIGN_TEAM}"#DEVELOPMENT_TEAM=#|沒帶團隊
resign.sh|s#return 13; }#return 0; }#|手機連不到當成功
resign.sh|s#return 17#return 0#|名額滿當成功
resign.sh|s#shasum#true#|編譯資料夾不分專案（路徑雜湊變空字串）
resign.sh|s#Products/\*-iphoneos/\*.app#Products/Debug-iphoneos/*.app#|假設產物在 Debug 資料夾
config.rb|s#if project_cfg.key?("devices")#if false#|允許把手機寫進 resign.yaml
config.rb|s#when Psych::Nodes::Scalar then node.value.to_s#when Psych::Nodes::Scalar then (Float(node.value) rescue node.value).to_s#|YAML 值被當數字
config.rb|s#\["bundle_id"\] != v\["bundle_id"\]#["bundle_id"] == v["bundle_id"]#|覆蓋旗標反過來
config.rb|s#cfg\["allow_paid_team"\] == "true"#false#|忽略 allow_paid_team
config.rb|s#variant = cfg\["default_variant"\] if blank?(variant)#nil#|忽略 default_variant
config.rb|s#local_path = File.join(root, "resign.local.yaml")#local_path = "/nonexistent"#|不讀本機設定
EOF
)

n=0
while IFS='|' read -r -u 3 file expr desc; do
    [ -z "${file}" ] && continue
    n=$((n + 1))
    m="${W}/m${n}"
    rm -rf "${m}"; cp -R "${SRC}" "${m}"
    sed -i '' -e "${expr}" "${m}/${file}"
    if cmp -s "${SRC}/${file}" "${m}/${file}"; then
        INVALID="${INVALID}\n  #${n} ${desc}（sed 沒改到任何東西）"
        echo "INVALID #${n} ${desc}"
        continue
    fi
    if SCRIPTS="${m}" "${HERE}/run.sh" >/dev/null 2>&1; then
        SURVIVED="${SURVIVED}\n  #${n} ${desc}"
        echo "SURVIVED #${n} ${desc}"
    else
        KILLED=$((KILLED + 1))
        echo "KILLED #${n} ${desc}"
    fi
done 3<<<"${MUTANTS}"

echo
echo "突變 ${n} 個：抓到 ${KILLED}"
[ -n "${SURVIVED}" ] && printf "沒抓到（測試有漏洞）：%b\n" "${SURVIVED}"
[ -n "${INVALID}" ] && printf "突變無效（要修突變本身）：%b\n" "${INVALID}"
[ -z "${SURVIVED}${INVALID}" ]
