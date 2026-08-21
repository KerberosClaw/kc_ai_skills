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

# ── 用 fallback 之前先檢查 marker 的時效 ───────────────────────────
# 🔴 兩個 fallback 的判準都是「比 marker 新」。marker 一旦是舊的（撿到殘留的
#    state 檔就會這樣），「比它新」等於「幾乎所有東西」，於是撈到**別次執行**
#    的圖，回報成功，而結果看起來完全合理。實測踩過。
MARKER_MAX_AGE=3600     # 秒。單張圖大約三分鐘，一小時已經很寬鬆
if [ -f "$MARKER" ]; then
  NOW=$(date +%s)
  MTIME=$(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0)
  AGE=$((NOW - MTIME))
  if [ "$AGE" -gt "$MARKER_MAX_AGE" ]; then
    echo "marker 已經 ${AGE} 秒沒更新（上限 ${MARKER_MAX_AGE}），不能安全地用 fallback" >&2
    echo "這通常表示撿到了殘留的 state 檔 —— 硬跑下去會把別次執行的圖當成這次的結果" >&2
    exit 1
  fi
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
# 🔴 一定要受 marker 約束。實測踩過：不約束的話會撈到「今天稍早別次 codex 生圖」
#    的 session，把別人的圖當成這次的結果交出來，而且回報成功 —— 安靜、而且
#    結果看起來完全合理。一個什麼都沒產出的呼叫因此拿到一張成品。
if [ ! -f "$MARKER" ]; then
  echo "沒有 marker，不能安全地動用 fallback 2（會撈到別次 session 的圖）" >&2
  exit 1
fi

echo "# 前兩層都空，動用 fallback 2（rollout base64）" >&2
ROLLOUT=$(find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' -newer "$MARKER" 2>/dev/null \
          | xargs grep -l 'iVBORw0KGgo' 2>/dev/null \
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
