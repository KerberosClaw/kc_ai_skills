#!/usr/bin/env bash
# 編輯模式的執行前檢查。跑在拍板之後、呼叫 codex 之前。
#
# 用法：preflight_edit.sh <底圖絕對路徑>
# 輸出：SRC_W / SRC_H（給 prompt 的畫布鎖定用），以 shell 可 eval 的形式印出
# 退出碼：0 可以繼續 / 1 相依或底圖有問題（停下告訴 user，不要硬跑）
#
# 為什麼要有這支：編輯模式的驗收（verify_edit.py）是必過閘門，而它需要 Pillow。
# 缺 Pillow 時如果一路跑下去，會生出一張沒驗過的圖，然後在「要不要轉 jpg」
# 那個決策點上做出可能毀掉透明度的選擇。寧可在花錢之前就停。
set -u

REF="${1:-}"
if [ -z "$REF" ]; then
  echo "用法：preflight_edit.sh <底圖絕對路徑>" >&2
  exit 1
fi

if [ ! -f "$REF" ]; then
  echo "底圖不存在：$REF" >&2
  echo "編輯模式沒有底圖就不成立 —— 跟 user 要本機路徑，不要退化成「生一張像的」" >&2
  exit 1
fi

if ! python3 -c "import PIL" 2>/dev/null; then
  echo "缺少 Pillow，編輯模式的驗收跑不了。安裝：python3 -m pip install pillow" >&2
  echo "🔴 裝不起來就停下告訴 user，不要靜默降級交付未驗過的圖" >&2
  exit 1
fi

# 量底圖尺寸 → Step 2-edit 的 "Keep the output canvas at exactly W x H pixels."
# 路徑走 argv 不走字串內插：內插在路徑含單引號時會壞，而且會壞得很安靜。
read -r SRC_W SRC_H <<EOF
$(python3 - "$REF" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
print(im.size[0], im.size[1])
PY
)
EOF

if [ -z "${SRC_W:-}" ] || [ -z "${SRC_H:-}" ]; then
  echo "量不到底圖尺寸：$REF" >&2
  exit 1
fi

echo "SRC_W=$SRC_W"
echo "SRC_H=$SRC_H"
echo "# 底圖 ${SRC_W}x${SRC_H} —— 把這兩個數字寫進 prompt 的畫布鎖定那行" >&2
