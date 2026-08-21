#!/usr/bin/env bash
# 從 codex 手上把圖收回來。主路 + 兩層 fallback，一次做完。
#
# 用法：collect.sh <期望的輸出路徑 OUT_PNG> <啟動前 touch 的 marker 檔>
# 退出碼：0 收到（路徑印在 stdout）/ 1 三層都拿不到
#
# 為什麼是三層（每一層都是實際翻車換來的）：
#   主路 prompt-save  —— launch 時就在 prompt 裡叫 codex 存到指定絕對路徑。
#                        跨版本最穩，因為不依賴 codex 把圖放哪。
#   fallback 1        —— 撈 ~/.codex/generated_images。0.141.0 起「時有時無」，
#                        同版本同指令有時整批不落，所以它不能當主路。
#   fallback 2        —— 從 session rollout JSONL 解 base64 還原。未文件化、
#                        隨版本可能再變，只在前兩層都空時動用。
#
# 🔴 找檔一律用 `find -newer <實體 marker 檔>`，絕不用 `-newermt`：
#    macOS 的 BSD find 對 -newermt 的 @epoch 與相對時間都會 silently 假陰性
#    —— 圖明明在，卻回報「沒有 png」，然後整批被誤判成失敗。
set -u

OUT_PNG="${1:-}"
MARKER="${2:-}"
if [ -z "$OUT_PNG" ] || [ -z "$MARKER" ]; then
  echo "用法：collect.sh <OUT_PNG> <START_MARKER>" >&2
  exit 1
fi

# ── 主路：codex 照 prompt 存到定位了嗎 ─────────────────────────────
if [ -f "$OUT_PNG" ]; then
  echo "$OUT_PNG"
  echo "# 主路（prompt-save）命中" >&2
  exit 0
fi

# ── fallback 1：撈 generated_images ────────────────────────────────
if [ -f "$MARKER" ]; then
  SRC=$(find "$HOME/.codex/generated_images" -type f -iname '*.png' -newer "$MARKER" 2>/dev/null \
        | xargs ls -t 2>/dev/null | head -1)
  if [ -n "${SRC:-}" ] && [ -f "$SRC" ]; then
    mv "$SRC" "$OUT_PNG"
    rmdir "$(dirname "$SRC")" 2>/dev/null
    echo "$OUT_PNG"
    echo "# fallback 1（generated_images）命中，已搬到定位" >&2
    exit 0
  fi
else
  echo "# marker 檔不存在，跳過 fallback 1" >&2
fi

# ── fallback 2：從 rollout JSONL 解 base64 ─────────────────────────
echo "# 前兩層都空，動用 fallback 2（rollout base64）" >&2
ROLLOUT=$(grep -rl 'iVBORw0KGgo' "$HOME/.codex/sessions/$(date +%Y/%m/%d)"/rollout-*.jsonl 2>/dev/null \
          | xargs ls -t 2>/dev/null | head -1)
if [ -z "${ROLLOUT:-}" ]; then
  echo "三層都拿不到圖，codex 大概率失敗 —— 去讀 log 判斷失敗類型" >&2
  exit 1
fi

python3 - "$ROLLOUT" "$OUT_PNG" <<'PY'
import sys, json, base64
rollout, out = sys.argv[1], sys.argv[2]
b64 = None
for line in open(rollout):
    if 'iVBORw0KGgo' not in line:          # PNG magic 的 base64 開頭
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    stack = [obj]
    while stack:                            # 結構隨版本會變，遞迴找就好
        c = stack.pop()
        if isinstance(c, dict):
            stack.extend(c.values())
        elif isinstance(c, list):
            stack.extend(c)
        elif isinstance(c, str) and c.startswith('iVBORw0KGgo'):
            b64 = c                         # 留最後一張
if b64:
    open(out, 'wb').write(base64.b64decode(b64))
    sys.exit(0)
sys.exit(1)
PY

if [ -f "$OUT_PNG" ]; then
  echo "$OUT_PNG"
  echo "# fallback 2 命中（那是救援不是備份 —— 成品該留 png 就別急著刪）" >&2
  exit 0
fi

echo "三層都拿不到圖" >&2
exit 1
