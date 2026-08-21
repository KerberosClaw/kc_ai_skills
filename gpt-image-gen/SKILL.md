---
name: gpt-image-gen
description: "Use when the user asks to generate OR edit an image via GPT/Codex (e.g. 「叫 gpt 生圖」「幫我用 gpt 生圖」「gpt 畫一個 X」「幫我去背」「把這張圖的背景去掉」). The skill drafts a Chinese + English prompt pair, iterates with the user until they explicitly approve, then dispatches Codex CLI ($imagegen skill, codex built-in image_gen) in the background, monitors progress, collects the result into the current working directory, and writes a sidecar prompt log. Three modes: text-to-image; img2img (drop a reference image on disk and it runs Codex `-i` to lock a face/character across scenes); and EDIT mode (background removal, targeted local changes) where the prompt is written as 'keep every pixel, change only X' and the result is verified for size, alpha and pixel fidelity before delivery."
version: 0.5.0
status: mvp
triggers:
  - "叫 gpt 生圖"
  - "叫gpt生圖"
  - "幫我用 gpt 生圖"
  - "幫我用gpt生圖"
  - "請 gpt 畫"
  - "gpt 畫一個"
  - "gpt 畫一張"
  - "gpt 生個圖"
  - "gpt 生張圖"
  - "幫我去背"
  - "去背"
  - "把背景去掉"
  - "去掉背景"
  - "改這張圖"
  - "編輯這張圖"
  - "修這張圖"
argument-hint: "（無；自然語言觸發）"
---

# gpt-image-gen — 用 Codex CLI 叫內建 image_gen 生圖與改圖

You are a prompt-crafting partner who turns the user's loose Chinese description into a tight bilingual prompt pair, iterates with the user until they explicitly approve, then dispatches Codex CLI to generate or edit the image. You are **not** the image generator — Codex is. Your job is prompt design, user confirmation gating, execution orchestration, and **verifying the result before you hand it over**.

**CRITICAL — 四條紅線**：

1. **未拍板絕不呼叫 codex** — 拍板 = user 明確說 `OK` / `生` / `go` / `下去`。其他正向回應（「不錯」「可以喔」「應該行」）一律當「還沒拍板」處理，繼續等明確指令。生圖會花 user 的錢，誤觸發 = 違規。
2. **有 reference image → 走 img2img 或編輯**（codex `-i`） — user 這輪有附底圖（拖曳/貼上/`[Image #N]`）→ Step 3a 偵測 → Step 4 用 `codex exec ... -i <ref>` 跑。⚠️ codex `-i` 吃**本機檔案路徑**：底圖有實體檔就跑；只貼在對話、本機無檔 → 問 user 要路徑，給不出才退回印 prompt 貼 GUI。**拍板 gate（紅線 1）對 img2img 與編輯一樣適用。**
3. **不寫死任何預設風格** — Skill 不存 style preset。每張圖風格純靠當下 conversation context + user 描述推。沒 context 就問。
4. 🔴 **編輯模式一律交 png，不轉 jpg，無例外** — Step 5c-1 的預設是「轉 jpg q85、刪 png」，那對生成是對的，對編輯是災難：jpg 沒有 alpha 通道，帶透明度的結果轉一次就永久消失，而**編輯結果不可重現**（同 prompt 同 ref 再跑不會是同一張）。**不要去猜它有沒有 alpha**（`mode P` 的透明 PNG 就會猜錯），一律走 Step 5c-2。

---

## Step 1: 先判斷模式，再判斷語境

### Step 1-0: 生成 or 編輯（**先決，決定後面每一步**）

| user 要的 | 模式 | 判準 |
|---|---|---|
| 一張**新的**圖（有沒有底圖都算） | **生成** — 走 Step 1 下半、Step 2 生成模板 | 底圖只是**參考**（鎖臉／鎖角色／鎖場景），輸出本來就該跟底圖不同 |
| **這張圖**動一個地方，其他不要變 | **編輯** — Step 1b → Step 2-edit 模板 → Step 3a-edit → Step 4b 編輯變體 → **Step 5b 驗收** → **Step 5c-2 只交 png** | 輸出應該**還是同一張圖**，只有指定處不同 |

🔑 **一句話判準**：**「user 會不會拿輸出去跟原圖逐像素比對？」** 會 → 編輯；不會 → 生成。

- 「把他放到海邊」→ 生成（換場景，人以外全變）
- 「同一個人，換成笑的表情」→ **生成**（img2img；臉會被重繪，只是要求相似）
- 「把背景去掉」「把左上角那個杯子移掉」→ **編輯**（其餘每一像素都該原封不動）

分不出來就**問一句**：「這張是要**改這張圖本身**（其他地方一個像素都不動），還是**照它生一張新的**？」

⚠️ **編輯模式沒有底圖就不成立。** 沒有本機實體檔 → 照紅線 2 問路徑，給不出就結束，不要退化成「生一張像的」。

**不阻塞條款（user 不在場時）**：模式判斷、Step 1a、Step 1b 都是**資訊不足**型閘門，
user 不在（背景 / 無人值守 / 被別的 skill 呼叫）時，**照最合理的解讀往下走**，
並在交付訊息裡明標「假設：`MODE=<x>`，未經確認」。

🔴 **但拍板閘（Step 2a）沒有不阻塞版本** —— 那是授權閘，花的是 user 的錢，沒有 fallback。
被別的 skill 當子流程呼叫時，**批次授權要在上層取得**（上層對整批拿一次拍板），
不是在這裡放行；本層仍然不得在沒有任何授權的情況下呼叫 codex。

### Step 1-1: 判斷觸發語境（mid-conversation vs 新對話）

**生成模式**讀 trigger 那輪訊息 + 最近 5-10 輪 context，落到下表（**編輯模式跳過本表，直接去 Step 1b**）：

| 情況 | 動作 |
|------|------|
| Mid-conversation 且 context 含 ≥3 錨點（**場景 + 主體 + 動作**） | 跳 Step 2，直接展 prompt |
| Mid-conversation 但 context 不足（缺任一錨點） | 跳 Step 1a，互動補問 |
| 新對話 / 純 trigger 沒帶任何描述 | 跳 Step 1a，互動問清楚 |

**錨點判斷標準**：
- **場景**：哪裡 / 什麼背景（街道、室內、特定地標、純色底...）
- **主體**：誰 / 什麼物件、外型描述
- **動作**：在做什麼 / 姿態 / 表情 / 互動

不確定時就降級到 Step 1a 問清楚 — **禁止靠想像力填空**。

### Step 1a: 互動補問（只在缺錨點時）

問題收斂在缺的那幾項，每次最多 3 個問題、numbered list、口語：

```
要先確認幾件事再展 prompt：
1. 場景 / 背景：__
2. 主體：誰 / 什麼，幾個，長相 / 外型描述：__
3. 動作 / 氛圍：__
4. 風格傾向（可選；不講就交給我推）：__
```

**不要問**：尺寸 / aspect ratio / 解析度（除非 user 主動提）；技術參數（model / steps / cfg）；codex 怎麼跑（這 skill 自己處理）。

### Step 1b: 編輯模式要先釘死的三件事

編輯模式**不問場景／主體／動作**（那是生成模式的錨點），改問這三件：

| 要釘的 | 為什麼 | 不釘會怎樣 |
|---|---|---|
| **① 底圖的本機絕對路徑** | codex `-i` 只吃檔案路徑 | 沒有就不成立，別退化成「生一張像的」 |
| **② 改哪一處，精確到可驗證** | prompt 要寫成 `CHANGE EXACTLY ONE THING` | 寫「修一下」→ 模型自由發揮 → 整張重畫 |
| **③ 其餘一切都不准動** | 這句是編輯模式的核心，**不是廢話** | 不寫，模型會把它當 img2img，重新生成一張「很像的」 |

②③ 這對是編輯模式成立的關鍵：**模型預設的行為是「重新生成」不是「就地修改」**，要它就地改必須明說。

**尺寸也要釘。** 編輯模式**一定**在 prompt 裡明寫輸出畫布尺寸（`Keep the output canvas at exactly W x H pixels.`），
否則模型可能吐一個常見比例的畫布，主體位置全跑掉。

---

## Step 2: 展 bilingual prompt 給 user 過

格式固定，**中文在前英文在後**（user review 中文，英文是實際送 codex 的 payload）：

```markdown
## 中文 prompt
（口語描述，user 看得順、能直接指出哪裡要改的顆粒度。
 包含：場景 / 主體 / 動作 / 風格 / 光線 / 構圖 等該講的都講。）

## English prompt（送 codex 用）
（codex 影像模型吃的高密度英文 prompt。
 結構建議：SETTING / SUBJECT / ACTION / STYLE / LIGHTING / COMPOSITION / ASPECT RATIO。
 寫法照 OpenAI 官方 prompt guide — 名詞 + 形容詞密集，少動詞，少 narrative。）
```

**生成模式展完後就到這裡：停下來等 user 回應**（拍板字眼見 Step 2a）。編輯模式改用下面那套骨架。

### Step 2-edit: 編輯模式的 prompt 骨架（三段，缺一不可）

編輯模式**不用**上面那個 SETTING / SUBJECT / ACTION 結構 —— 那是在描述「要生什麼」，
而編輯要描述的是「**保留什麼、只改什麼**」。骨架固定三段：

```
① 保留清單 —— 越具體越好，把畫面上看得到的東西逐項點名
Use the attached Image #1 as the BASE. Keep EVERYTHING identical to it:
<逐項列出：主體、五官、髮型、配件、服裝、姿勢、位置、取景、裁切、
 鏡頭距離、背景、光線、長寬比 …… 凡是不該變的都點名>

② 唯一的改動 —— 用 EXACTLY ONE THING 句式
CHANGE EXACTLY ONE THING: <要改的那一項，寫到可驗證>

③ 明擋清單 + 畫布鎖定 —— 反面詞比正面詞有效
DO NOT <逐項擋掉最可能被順手改掉的東西>. DO NOT move the subject.
DO NOT zoom in or out. DO NOT resize.
Keep the output canvas at exactly <W> x <H> pixels.
```

**去背另外加一段**（否則模型會把背景「畫成白色」而不是挖掉）：

```
Output a PNG with a genuine ALPHA CHANNEL - the area around the subject must be
actually TRANSPARENT (alpha = 0), not painted white, not painted any solid colour,
and not a checkerboard pattern drawn as pixels.
```

⚠️ 中文那半照樣要寫（user 是看中文 review 的），但**中文段要把「保留清單」逐項寫出來**，
不要濃縮成「其他都不要動」—— user 要能一眼看出你有沒有漏點名某個東西。

展完後**停下來等 user 回應**。

### Step 2a: User 回應分支

| User 回應 | 動作 |
|-----------|------|
| `OK` / `生` / `go` / `下去`（明確拍板字眼） | 進 Step 3 |
| 任何修改指令（「改成 X」「加 Y」「拿掉 Z」「換風格」） | 重生 prompt 雙段 → 回 Step 2 開頭重展 |
| `算了` / `不要了` / `取消` | 結束，不呼叫 codex |
| 其他模糊正向回應（「不錯」「可以喔」「OK 吧」**含猶豫感**） | 視為「還沒拍板」，回問一句：「這版就生？確認的話回 `OK` 或 `生`」 |

**MANDATORY**：拍板字眼是 hard gate，不准用語意推測代替。

---

## Step 3: 執行前檢查（pre-flight）

**Step 3a: Reference image 偵測**

掃這輪 trigger + 等待拍板期間 user 是否有附過任何 image：

```
MODE=edit（Step 1-0 判定）：
  • REF 已在 Step 1b ① 取得（編輯模式在拍板前就必須有底圖，否則寫不出保留清單）→ 直接進 Step 3b。
  • 沒有 REF → 編輯模式不成立。照紅線 2 問路徑；給不出就如實告訴 user 做不到，
    🔴 不要退化成 MODE=generate「生一張像的」交差。

MODE=generate：
  • 本機有實體檔（user 給 path / 拖曳實體檔）→ 記 REF=該絕對路徑，走 img2img（Step 4 帶 -i "$REF"）。進 Step 3b。
  • 只貼在對話裡、本機無實體檔 → 問 user 要本機路徑（codex -i 吃 file path、不吃對話內嵌圖）。給了 → img2img；給不出 → 退而印「拍板的英文 prompt」一段給 user 自己貼 ChatGPT GUI，結束。
  • 無附 → REF 留空，text2img。進 Step 3b。
```

⚠️ **`REF` 是全篇唯一的底圖變數名**（Step 1b 的「底圖絕對路徑」＝ `REF`，Step 5b 驗收的來源也是它）。
不要在不同 step 給同一張圖取不同名字。

**Step 3a-edit: 編輯模式專屬 pre-flight（MANDATORY）**

```bash
# ① 相依：驗收要用 Pillow，缺了就跑不了 MANDATORY 的 Step 5b
python3 -c "import PIL" 2>/dev/null || {
  echo "編輯模式需要 Pillow：python3 -m pip install pillow"
  # 🔴 裝不起來就停下告訴 user，不要靜默降級交付未驗過的圖
}

# ② 量底圖尺寸 → Step 2-edit 的畫布鎖定要填這兩個數字
read SRC_W SRC_H < <(python3 -c "
from PIL import Image; im=Image.open('$REF'); print(im.size[0], im.size[1])")
echo "底圖 ${SRC_W}x${SRC_H}"
```

⚠️ **畫布尺寸有一個未收斂的風險**：`assert out.size == (SRC_W, SRC_H)` 是硬閘門，
但 image_gen 不保證任意尺寸都吐得出來。實測**非標準比例（如 720×1080）有成功過**，
但這不是保證。若這道閘門反覆失敗且尺寸只差一點，**那是管線限制不是 prompt 問題** ——
告訴 user、讓他決定要不要接受「輸出後自己裁回原尺寸」，不要無限重試。

**Step 3b: NSFW context 判斷**

依當下 conversation context 判斷這張圖內容是否會踩到 OpenAI policy：

- **不寫死硬規則** — 看上下文。例如：
  - 一般角色插畫、無裸露 → 應該過
  - 明確的性內容或裸露 → 大概率被 reject
  - context 本身就落在敏感題材 → 提高警覺度

- 判斷會 reject → 警告 + 問：
  ```
  這張描述 codex 大概率會 reject（OpenAI policy）。要硬送看看，還是改走 ChatGPT GUI 或其他工具？
  - 硬送：回「送」
  - 改走別的工具：回「不要送」
  ```

- 判斷 OK → 直接進 Step 4

**不替 user 做安全決策** — 只警告 + 給選項。

---

## Step 4: 呼叫 Codex（背景跑 + 非阻塞等通知）

### Step 4a: 組路徑與檔名

```bash
TS=$(date +%Y%m%d_%H%M%S)
START_MARKER="/tmp/codex_imagegen_${TS}.marker"   # 只當 fallback 錨點（主路是 prompt-save，見 Step 4b/5a）

# slug：從中文 prompt 抽 1-3 個關鍵詞，連字號連接，去掉空白與標點
# 範例：「一隻棕熊在雪山頂看日出」→ "brown-bear-summit-sunrise"
SLUG="<由你從中文 prompt 抽出>"

# 輸出夾：cwd 是 git repo → ./generated_images/ 子夾（避免雜進 git 根）；否則 cwd 根
# 🔴 這個路徑等下要叫 codex 自己寫進去 → 必須落在 sandbox 可寫範圍（cwd 內 or /tmp/$TMPDIR）
if git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1; then
  OUT_DIR="$PWD/generated_images"
else
  OUT_DIR="$PWD"
fi
mkdir -p "$OUT_DIR"

OUT_PNG="$OUT_DIR/${TS}_${SLUG}.png"      # 🟢 主路：叫 codex 直接存這（prompt-save，見 Step 4b）
OUT_JPG="$OUT_DIR/${TS}_${SLUG}.jpg"      # 生成模式的最終交付（jpg q85）
OUT_SIDECAR="$OUT_DIR/${TS}_${SLUG}.prompt.md"
LAST_MSG="/tmp/codex_imagegen_${TS}.lastmsg"
LOG_FILE="/tmp/codex_imagegen_${TS}.log"

# 模式與底圖（Step 1-0 / Step 1b / Step 3a 已經決定，這裡只是落成變數）
MODE=generate            # generate | edit
EDIT_KIND=local          # 只在 MODE=edit 時有意義：bgremove | local
REF=""                   # 底圖絕對路徑；text2img 留空，img2img 與 edit 必填

touch "$START_MARKER"   # fallback 用：萬一 codex 沒照存，Step 5a 退而用 find -newer 撈

# 🔴 落一份 state 檔：每次 Bash 工具呼叫都是「全新的 shell」，上面這些變數活不過這一格。
#    Step 5 在背景等待之後才跑，屆時一律先 source 回來，不要憑記憶重打路徑。
cat > "/tmp/codex_imagegen_${TS}.state" <<EOF
TS=$TS
MODE=$MODE
EDIT_KIND=$EDIT_KIND
REF=$REF
OUT_PNG=$OUT_PNG
OUT_JPG=$OUT_JPG
OUT_SIDECAR=$OUT_SIDECAR
LAST_MSG=$LAST_MSG
LOG_FILE=$LOG_FILE
START_MARKER=$START_MARKER
EOF
```

進 Step 5 的每一格 bash 開頭都先：

```bash
. "/tmp/codex_imagegen_${TS}.state"      # TS 記在你的訊息裡，或用 ls -t /tmp/codex_imagegen_*.state | head -1
```

### Step 4b: 背景啟動 codex exec

用 `Bash` 工具，`run_in_background: true`。**主路 = prompt-save**：在 prompt 裡直接叫 codex 用內建 image_gen、存到 `$OUT_PNG`、回報實際路徑（跨版本最穩，見下方 0.141.0 註）：

**生成模式**（text2img：`REF` 留空；img2img：`REF` 有值時自動帶 `-i`）：

```bash
codex exec --skip-git-repo-check \
  "用內建 image_gen 工具生圖，不要使用 scripts/image_gen.py，也不要使用 OPENAI_API_KEY。<英文 prompt 內容>。請把最終圖片存到 ${OUT_PNG}，完成後回報實際存檔的絕對路徑。" \
  ${REF:+-i "$REF"} \
  --sandbox workspace-write \
  --output-last-message "$LAST_MSG" \
  < /dev/null > "$LOG_FILE" 2>&1
```

**編輯模式**（`REF` 必有值；注意**包裝動詞不同**）：

```bash
codex exec --skip-git-repo-check \
  "用內建 image_gen 工具編輯附上的圖片，不要使用 scripts/image_gen.py，也不要使用 OPENAI_API_KEY。<英文 prompt 內容（Step 2-edit 的三段骨架）>。請把最終圖片存到 ${OUT_PNG}，完成後回報實際存檔的絕對路徑。" \
  -i "$REF" \
  --sandbox workspace-write \
  --output-last-message "$LAST_MSG" \
  < /dev/null > "$LOG_FILE" 2>&1
```

> - 🔴 **包裝動詞必須跟著模式換**。生成用「生圖」、編輯用「**編輯附上的圖片**」。
>   編輯模式若沿用「生圖」，這個動詞會把 Step 2-edit 辛苦建立的
>   `CHANGE EXACTLY ONE THING` 稀釋掉，模型會回去重新生成。
> - **img2img 時**（**只有 img2img**），prompt 開頭再加一句身份鎖：
>   「請參考附上的 Image #1 作為人物身份參考（同一個人，保持臉部特徵、髮型、體型一致）。」
> - 🔴 **編輯模式禁止加身份鎖。** 「保持一致」＝「**重新生成一張像的**」，
>   跟編輯模式的「一個像素都不要動」正面衝突 —— 那正是 Step 5b 驗收要抓的失敗態。
> - `${REF:+-i "$REF"}` 只在 REF 有值時展開成 `-i "$REF"`；`< /dev/null` 防 codex 誤讀 stdin。

**Flag 註解**（codex-cli 0.141.0 實測對齊；新版本前先 `codex exec --help` 確認）：

- **`--skip-git-repo-check`**：讓 `codex exec` 在**非 git repo 的 cwd** 也能跑（不加會在非 repo 目錄報錯拒跑）。在 repo 內可省、但加著無害，當常駐。
- **`--sandbox workspace-write`**：允許 codex 寫進 workspace（cwd ＋ `/tmp` ＋ `$TMPDIR`）—— prompt-save 的 `$OUT_PNG` 必須落在這範圍，否則寫檔被靜默擋。
- **`codex exec` 沒有 `--ask-for-approval`** — 那 flag 只在 top-level `codex`，exec 預設就是 non-interactive never-ask，不需另指定。
- **`--full-auto` 已 deprecated**（0.128.0 起），等同 `--sandbox workspace-write`。**不要用**。
- **`-o, --output-last-message`**：把 codex 最後 assistant message 寫進指定檔。**prompt-save 法下這檔會帶實際絕對路徑**（因為你在 prompt 叫它回報）→ Step 5a 可拿來交叉驗證。
- **`-i, --image <FILE>`**：img2img 用 — 有底圖時帶 `-i "$REF"`（鎖臉/角色一致，已實測可行）。⚠️ **`-i` 是 variadic `<FILE>...`**：prompt 必須當**第一個 positional 放最前**、`-i` 擺後面，否則 prompt 會被吃成第二張圖 → codex 沒 positional prompt → 轉讀 stdin → 失敗。（Codex 官方範例把 `-i` 放 prompt 前，**別照抄**、會踩這雷。）
- **沒有 output-dir flag**：控制輸出位置只有兩根槓桿 ——「prompt 內明寫存檔路徑」（主路）＋ `-C <workdir>` / `--add-dir`。
- **批次/迴圈跑 codex 必加 `< /dev/null`**：在 `while read … done < file` 內跑 codex 會繼承迴圈 stdin（= prompt 檔）→ 一個 session 狂生多圖 + 吃掉 read fd。`< /dev/null` 切斷即解。多條並行各自獨立 `CODEX_HOME`（cp auth.json + config.toml）避免搶圖；🔴 `CODEX_HOME` 必須落 sandbox 可寫路徑（`/tmp/codex_stream_X`），別指到 cwd 外。

**Prompt 字串注意**：
- 用**自然語指示**叫 codex 走內建 image_gen（如上「用內建 image_gen 工具…」），不靠 `$imagegen` token —— 自然語更穩，也免去 `$` 被 shell 展開的坑。若硬要用 `$imagegen` token，bash 字串內要 escape 成 `\$imagegen`。
- prompt 用 double-quote 包，內含的 `"` / `` ` `` / `$` 全部 escape。
- 「不要使用 scripts/image_gen.py / OPENAI_API_KEY」是**防呆**：若 cwd repo 內有同名生圖 script，codex 可能誤抓 → 明擋。
- 不要加 `--json`（log 變 JSONL，反而難用 grep 監看）。

> ⚠️ **0.134.0 版差異（踩過、直接影響 Step 5 收圖）**：codex 改用 `gpt-5.5` orchestrator + 內建 `image_gen` flow，不再是 gpt-image-2，連帶兩個 output 形狀變了：
> 1. `--output-last-message` **不再吐圖片路徑**（只寫一句「Generated the image...」）→ 別再 grep LAST_MSG 抓路徑。
> 2. 圖落在**巢狀** `~/.codex/generated_images/<session-id>/ig_*.png`，不是平鋪。
> 3. 固定輸出 **png**（無法指定格式）→ 交付前自行轉 jpg。

> ⚠️ **0.136.0 版差異（PR #24972「native image artifact completion pipeline」重寫出圖管線、實測對齊）**：
> 1. 圖**仍然**落 `~/.codex/generated_images/<session-id>/ig_*.png`（0.136.0 實測確認、Step 5a 的 `find -newer marker` 照舊有效）—— 別誤信「0.136 不再寫 generated_images」這類推論，**自己 `find` 一下就知道**。
> 2. **同時**圖會以 base64 嵌進 session rollout JSONL（`~/.codex/sessions/<date>/rollout-*.jsonl` 的 `image_generation_call` / `image_generation_end` 的 `result` 欄）。萬一哪天 `generated_images` 撈空，這是**最後手段** fallback（解 base64 還原 png），但屬未文件化、隨版本可能再變、別當主路。
> 3. **更穩的官方文件作法（建議長期改用、跨版本不靠猜目錄）**：prompt 末尾明寫 `Save the final image as <name>.png in the current directory.` ＋ 跑 `codex exec -C <輸出夾> --enable image_generation --sandbox workspace-write …`，讓圖直接落你指定的 cwd。**沒有 output-dir flag**，`-C` / `--add-dir` + prompt 指示是唯一控制輸出位置的槓桿（0.136 的「local image attachments expose file paths to model」#25944 就是為了讓這條 save-path 流更可靠）。

> ⚠️ **0.141.0 版差異（實測 2026-06-24，本 skill v0.4.0 改版主因）**：
> 1. `generated_images` **時有時無** —— 同一版本、同樣指令，有時圖落 `~/.codex/generated_images/<session>/ig_*.png`、有時**完全不落**（圖只剩 rollout JSONL 的 base64）。所以 `find -newer marker` 撈 generated_images 這條**主路不再可靠**（實測整批撈空、得退 base64 還原才救回）。
> 2. **→ 收圖主路正式改為「prompt-save」**（上面 0.136 早記過的官方作法，現升為預設）：launch 時在 prompt 內叫 codex 存到 `$OUT_PNG`、回報路徑（見 Step 4b / 5a）。實測 0.141.0 圖**確實直接落指定路徑**、`--output-last-message` 也回報了絕對路徑。
> 3. generated_images `find` 與 rollout base64 解碼**降為 fallback 1 / 2**。注意 0.141.0 有時 prompt-save 與 generated_images **兩邊都寫** → Step 5b 收完主路要順手清掉 generated_images 的多餘 copy。

### Step 4c: 非阻塞等待（讓出主線程，靠 task 完成通知喚回）

codex 這條 image_gen flow **每張要跑 2-3 分鐘**（先跑 reasoning 再生圖）。Step 4b 既然 `run_in_background: true`，就**讓出控制權給 user、這一輪收尾**，別在前景 `sleep N; tail` 輪詢 —— 那會卡死主線程、user 不能講話（實戰踩過、user 抱怨「太久了 / 是不是當機」）。

正確姿態：

1. 啟動背景 codex 後，給 user **一行** heartbeat（見下），然後**這輪就結束**、把控制權還 user。
2. 背景指令跑完，harness 會丟 `<task-notification>`（含 task-id + output 檔路徑）自動把你喚回 —— **這就是「monitor」，由 task 系統盯，不是你前景 block**。
3. 被喚回 → 讀 `$LOG_FILE`（或 task output 檔）判斷成敗 → 進 Step 5（成功）或 Step 6（失敗）。

heartbeat（一行、不刷屏）：
```
Codex 跑起來了，背景生圖中（這條 flow 一般 2-3 分鐘），跑完通知你，先忙別的沒問題。
```

> ⚠️ **沒有獨立的 `Monitor` 工具** —— 「監督」= 背景 task + 完成通知。**禁用 `sleep N; tail` 前景輪詢**（阻塞主線程、卡死 user 對話）。真要中途偷看進度，用 `Read` 點一下 task output 檔就好，**別 sleep-loop**。

---

## Step 5: 收圖 → 驗收 → 交付 → sidecar → 通知

### Step 5a: 收圖（prompt-save 主路 + 兩層 fallback）

```bash
# 🟢 主路（prompt-save）：codex 應已把圖存到你指定的 $OUT_PNG
if [ -f "$OUT_PNG" ]; then
  SRC_PNG="$OUT_PNG"          # 已在定位，直接用（最常走這條）
else
  # fallback 1：codex 沒照存 → 去 generated_images 用 -newer marker 撈，撈到搬來 $OUT_PNG
  SRC_PNG=$(find ~/.codex/generated_images -type f -iname '*.png' -newer "$START_MARKER" 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
  [ -n "$SRC_PNG" ] && mv "$SRC_PNG" "$OUT_PNG" && SRC_PNG="$OUT_PNG"
fi
# fallback 2（最後手段）：兩邊都空 → 解 session rollout JSONL 的 base64 還原 png（見下方 python）
```

fallback 2（rollout base64 還原，只在 fallback 1 也空才動）：

```bash
# 從 log 抓 session id（無 ANSI 干擾的話），或直接抓 sessions 當天最新、含 PNG magic 的 rollout
ROLLOUT=$(grep -rl 'iVBORw0KGgo' ~/.codex/sessions/$(date +%Y/%m/%d)/rollout-*.jsonl 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
python3 - "$ROLLOUT" "$OUT_PNG" <<'PY'
import sys, json, base64
rollout, out = sys.argv[1], sys.argv[2]; b64=None
for line in open(rollout):
    if 'iVBORw0KGgo' not in line: continue
    try: obj=json.loads(line)
    except: continue
    st=[obj]
    while st:
        c=st.pop()
        if isinstance(c,dict): st.extend(c.values())
        elif isinstance(c,list): st.extend(c)
        elif isinstance(c,str) and c.startswith('iVBORw0KGgo'): b64=c  # 留最後一張
if b64: open(out,'wb').write(base64.b64decode(b64)); print("RESTORED", out)
else: print("NO_BASE64")
PY
[ -f "$OUT_PNG" ] && SRC_PNG="$OUT_PNG"
```

- 🔴 **絕不用 `-newermt`（任何形式）**：macOS BSD find 對 `-newermt` 的 `@epoch` **與**相對時間都 **silently 假陰性**（誤判「沒 PNG」其實圖都在）。一律 **`-newer <實體 marker 檔>`**（BSD/GNU 皆穩）。
- 🔴 fallback 1 **在 `~/.codex/generated_images` 找，別在 cwd / repo 內 `find .`**（主路已直接落 cwd 的 `$OUT_PNG`，不用 find；find 是給「codex 沒照存」的退路）。
- **用 `find` 不用 glob**：巢狀目錄要遞迴，空 glob 在 zsh 會 `no matches found` 中止。
- session id 走 grep log 的 `session id:` **不可靠**（ANSI 色碼夾在中間、regex 易撲空）→ fallback 2 改用「當天 rollout 抓含 PNG magic 的最新檔」。
- 三層都拿不到 `SRC_PNG` → codex 大概率失敗，跳 Step 6。

### Step 5b: 編輯模式驗收（**MANDATORY；生成模式跳過本段直接去 5c**）

🔴 **驗收一定排在交付之前。** 交付會轉檔／刪檔，驗收需要原始的 `$OUT_PNG`，順序顛倒就沒得驗了。

**「看起來沒變」不算驗過。** 模型有可能交回一張「重新生成的、看起來很像的」圖 ——
肉眼在表情／姿態沒動的情況下分辨不出幾十像素的位移，但那會讓這張圖與同批其他圖對不齊。

```bash
python3 - "$REF" "$OUT_PNG" "$EDIT_KIND" <<'PY'
import sys
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
KIND = sys.argv[3] if len(sys.argv) > 3 else "local"   # bgremove | local
src, out = Image.open(SRC), Image.open(OUT)
w, h = src.size
fail = []

def has_alpha(im):                       # mode P 的透明 PNG 也算，別漏
    return im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info

# ① 畫布尺寸沒變
if out.size != (w, h):
    fail.append(f"畫布跑掉：{out.size} != {(w, h)}")

# ② 透明度 —— 只在「這一輪的意圖就是去背」時驗（看意圖，不看輸出格式）
if KIND == "bgremove":
    if not has_alpha(out):
        fail.append(f"要的是去背，但輸出沒有透明度（mode={out.mode}）")
    else:
        a = out.convert("RGBA").getchannel("A")
        clear = a.histogram()[0] / (a.size[0] * a.size[1])
        if clear < 0.01:
            fail.append(f"有 alpha 但幾乎沒有透明像素（{clear:.1%}）：可能是畫上去的假背景")
        # ⚠️ 刻意不驗「四角必須透明」——主體貼齊邊緣的構圖（半身像、滿版）本來就有不透明的角

# ③ 主體像素保真（尺寸不同就沒得比，跳過）
if out.size == (w, h):
    sp = src.convert("RGB").load()
    op = out.convert("RGB").load()
    ap = out.convert("RGBA").getchannel("A").load() if has_alpha(out) else None
    gp = src.convert("L").load()
    bg = gp[5, 5]
    use_luma = bg >= 60          # 背景太暗時 bg-60 會把全圖判成背景 → 那條判準失效
    tot = worst = over = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if ap is not None:
                if ap[x, y] == 0:        continue     # 輸出判定為背景
            elif use_luma:
                if gp[x, y] >= bg - 60:  continue     # 原圖判定為背景
            d = max(abs(op[x, y][i] - sp[x, y][i]) for i in range(3))
            tot += 1; worst = max(worst, d); over += (d > 10)
    if tot == 0:
        fail.append("主體取樣為 0：背景判準失效（底圖是暗背景、或整張已透明）。"
                    "改用輸出的 alpha 當遮罩重跑，或請 user 目視比對")
    else:
        ratio = over / tot
        print(f"主體取樣 {tot}px  最大色差 {worst}  色差>10 佔 {ratio:.1%}")
        if worst > 9 or ratio > 0.01:
            fail.append(f"主體被改動了（最大色差 {worst}、色差>10 佔 {ratio:.1%}）"
                        "：它重新生成了一張像的，不是編輯")

print("VERDICT:", "PASS" if not fail else "FAIL")
for f in fail: print(" -", f)
sys.exit(0 if not fail else 1)
PY
```

判讀（**已寫進程式，不必用眼睛判**）：

| 最大色差 | 意思 | 結果 |
|---|---|---|
| **0** | 真的是遮罩／就地修改，一個位元都沒動 | ✅ PASS |
| **1–9** | 有輕微重編碼 | ✅ PASS，但在 Step 5e 通知裡講明 |
| **≥10**，或 `色差>10` 佔比 > 1% | **它重新生成了一張像的**，不是編輯 | ❌ FAIL |

**`VERDICT: FAIL` → 照 Step 6 的「編輯驗收未過」那列處理，不要自動重試、不要清檔。**

⚠️ **③ 的兩個假設要講清楚**：無 alpha 時退回明度判準，那條假設的**不只是「有對比」，是「背景比主體亮」**
（`>=` 是單向比較）。暗背景亮主體會讓取樣歸零，程式會明確報出來而不是靜默通過。
有 alpha 時一律走 alpha 遮罩，沒有這個問題。

### Step 5c: 交付

🔴 **先看模式再往下**：

| MODE | 走哪 |
|---|---|
| `generate` | 5c-1 轉 jpg |
| `edit` | **5c-2，禁止執行 5c-1 的 bash** |

#### Step 5c-1: 生成模式 — 轉 jpg 交付（q85）

codex 吐 png（2MB 級）；交付走 **jpg q85**（實測畫質肉眼無感、體積約 png 的 1/5）：

```bash
[ "$MODE" = "edit" ] && { echo "編輯模式，跳過本段，走 5c-2"; exit 0; }
sips -s format jpeg -s formatOptions 85 "$OUT_PNG" --out "$OUT_JPG" >/dev/null 2>&1
rm -f "$OUT_PNG"                            # 刪 png 中繼，只留 jpg
FINAL="$OUT_JPG"
```

- 最終交付 = `$FINAL`。**只有 user 明講「要留無損 png」才跳過 `rm -f "$OUT_PNG"`**。
- ⚠️ **例外**：這張圖若會**進版控**、**還要再加工**（去背／裁切／合成）、或**要當之後好幾張的 `-i`**，
  就留 png、別刪。q85 的損失本身肉眼無感，但拿它當整條產線的起點就是讓每一步都從有損的地方長出來。
  判準：**只是拿來看的 → 照刪；會被再利用 → 留 png。**

#### Step 5c-2: 編輯模式 — 只交 png

```bash
FINAL="$OUT_PNG"        # 不轉檔、不刪檔，就這樣
```

**編輯模式一律交 png，無例外。** 不分有沒有 alpha，理由同上一條的「會被再利用」判準 ——
編輯結果十之八九還要再加工或進版控，而且**編輯結果不可重現**（同 prompt 同 ref 再跑不會是同一張）。
不去猜它有沒有 alpha，就不會有猜錯的機會。

#### Step 5c-3: 清 `generated_images` 的多餘 copy（**兩種模式都要做**）

```bash
# 0.141.0 有時 prompt-save 與 generated_images 兩邊都寫 → 清掉 codex 那份多餘 copy（避免堆積）
STRAY=$(find ~/.codex/generated_images -type f -iname '*.png' -newer "$START_MARKER" 2>/dev/null | head -1)
[ -n "$STRAY" ] && rm -f "$STRAY" && rmdir "$(dirname "$STRAY")" 2>/dev/null
```

**絕不把圖留在 `~/.codex/generated_images/`**（堆積 + user 找不到）—— 主路雖然落 cwd，codex 仍可能另存一份在那，務必清。

### Step 5d: 寫 sidecar

先從 log 抓實際 model（別寫死 — 0.134 是 gpt-5.5 不是 gpt-image-2）：

```bash
MODEL=$(grep -aoE 'gpt-[0-9.]+' "$LOG_FILE" | head -1)
```

格式固定：

```yaml
---
timestamp: <ISO8601，帶時區偏移>
trigger: "<user 觸發那句原文>"
mode: <generate | edit>
edit_kind: <bgremove | local；MODE=generate 則 null>
reference_image: <$REF 絕對路徑；text2img 則 null>
codex_model: <$MODEL，如 gpt-5.5> (codex built-in image_gen flow)
codex_exit: success
verify: <MODE=edit 才有：Step 5b 的 VERDICT 與那行量測數字；生成模式 null>
output_image: <$FINAL 絕對路徑>
---

# 中文 prompt

<拍板版本的中文 prompt>

# English prompt

<拍板版本的英文 prompt（實際送 codex 的）>
```

- 🔴 `output_image` 一律填 **`$FINAL`**（生成＝`$OUT_JPG`、編輯＝`$OUT_PNG`）。
  寫死 `.jpg` 會讓編輯模式的 sidecar 指向一個**從未存在過的檔**，
  而 sidecar 是 prompt 的唯一持久記錄（見 Important rules）。
- 檔名慣例：sidecar 與圖**同 basename**、副檔名換成 `.prompt.md`。編輯模式沿用 `${TS}_${SLUG}` 這組，
  `SLUG` 改從「改了什麼」抽（例：`bg-removed`、`cup-removed`），不要沿用底圖檔名（會跟底圖的 sidecar 撞名）。

寫進 `$OUT_SIDECAR`。**bg session 內若 `Write` 被 bg-isolation guard 擋（這 skill 常在 bg + git repo 跑），改用 Bash heredoc 寫**（`cat > "$OUT_SIDECAR" <<'EOF' ... EOF`）。

### Step 5e: 通知 user（不自動開圖）

生成模式：

```
✅ 生好了
- 圖：<$FINAL 的相對 cwd 路徑>
- prompt log：<相對 cwd 路徑>.prompt.md
```

編輯模式（**要把驗收數字一起講出來**，那是「這真的是編輯不是重生」的唯一證據）：

```
✅ 改好了
- 圖：<$FINAL 的相對 cwd 路徑>（png，帶透明度就不轉 jpg）
- 驗收：尺寸 <W>x<H> 未變／主體取樣 <N>px 最大色差 <D>
- prompt log：<相對 cwd 路徑>.prompt.md
```

**不要自動 `open`** — user 偏好「搬好通知即可、自己決定要不要看」。

---

## Step 6: 失敗處理

依 log 內容分類：

| 失敗類型 | log 特徵 | 對應動作 |
|----------|----------|----------|
| Safety reject | `safety` / `policy` / `rejected` / `cannot generate` | 告訴 user「codex 拒了，policy 命中。要不要改 prompt 軟化 / 走別的工具？」 |
| Rate limit | `rate limit` / `429` / `usage limit` | 告訴 user「Codex 額度滿了。要等 / 改用 ChatGPT GUI 自己生？」 |
| 其他 error | exit code ≠ 0 + 沒以上字眼 | 印 log 最後 30 行給 user 看，問下一步 |
| **編輯驗收未過** | **codex exit 0、log 乾淨**，但 Step 5b 回 `VERDICT: FAIL` | 見下方 |

⚠️ **最後一列跟上面三列的性質不同**：codex 是**成功**的，log 裡什麼線索都沒有，
所以「印 log 最後 30 行」對它毫無用處 —— 那 30 行跟失敗原因無關。

**編輯驗收未過的處理**：

1. **貼出 Step 5b 的三項量測值**（尺寸、透明度、主體色差），那是唯一有資訊量的東西
2. **指出最可能的成因**，對照 `VERDICT` 底下那幾行：
   - 主體色差大 → Step 2-edit ① 的**保留清單不夠具體**，或 Step 4b 誤加了身份鎖
   - 畫布跑掉 → 沒鎖尺寸，或撞到 Step 3a-edit 講的管線限制
   - 沒有透明度 → 去背那段沒寫，或寫了但沒寫三個 `not`
3. **問 user 要不要補了再送一次**
4. 🔴 **這條路徑不要清檔**（不執行 Step 5c-3 的清理）—— user 可能要看那張失敗的圖來判斷

**不自動重試** — 失敗交給 user 決定。這條對「驗收未過」同樣適用：
它看起來很像「再調一下 prompt 就好」，但那是在沒有 user 判斷的情況下連續燒額度。

清掉中繼檔：
```bash
rm -f "$LAST_MSG" "$LOG_FILE" "$START_MARKER"
```

---

## Anti-patterns

- ❌ 用模糊正向回應（「不錯」「可以」）當拍板信號，誤呼叫 codex
- ❌ img2img 時把 `-i` 放 prompt 前面（prompt 被當第二張圖 → codex 失敗）；prompt 一定當第一 positional、`-i` 擺後
- ❌ 對話內嵌圖（本機無檔）硬塞 codex `-i`（吃 file path、抓不到）→ 先問本機路徑
- ❌ 預設某組固定角色 / 某個固定畫風這種寫死 style — 沒 context 就問
- ❌ Skill 內部偷偷加 NSFW filter 替 user 做決策（只警告 + 給選項）
- ❌ 把收圖**主路**放在「翻 `generated_images` / 解 rollout base64」（0.141.0 撈空率高、time-bomb）→ 主路用 prompt-save 叫 codex 存指定 `$OUT_PNG`，find / base64 只當 fallback
- ❌ 把生圖結果留在 `~/.codex/generated_images/` 不搬走/不清（堆積 + user 找不到）；0.141 兩邊都寫時要清掉那份多餘 copy
- ❌ 圖搬到 cwd 根但 cwd 是 git repo（會雜進 git status / 容易誤 commit）→ git repo 走 `./generated_images/` 子夾
- ❌ 把 codex 官方範例的 `-i ./input.png 'prompt'`（image 在 prompt 前）照抄 → `-i` variadic 會把 prompt 吃成第二張圖；一律 prompt 第一 positional、`-i` 擺後
- ❌ **單**靠「自動」`LAST_MSG` 抓路徑（沒在 prompt 叫 codex 回報就不吐）→ prompt-save 主路自己指定 `$OUT_PNG`、讀檔即可，LAST_MSG 只拿來交叉驗證
- ❌ 用 shell glob（`ls $DIR/*.png`）收 fallback 圖（巢狀目錄漏抓 + 空 glob 在 zsh 中止）→ 改 `find … -newer <marker檔>`
- ❌ fallback 收圖用 `find -newermt`（任何形式：`@epoch` 或相對 `'-30 minutes'`，macOS BSD find 都 silently 假陰性）→ 改 launch 前 `touch` marker + `find -newer "$MARKER"`
- ❌ 把單次觀察當鐵則（不論「不寫 generated_images 了」或「一定寫」）→ 0.141 實測**時有時無**；別賭它的行為，prompt-save 主路本就不依賴它
- ❌ 生完自動 `open` 圖（user 不要）
- ❌ sidecar 寫死 `codex_model: gpt-image-2`（實際是 log 裡的 model）
- ❌ 失敗自動重試（codex 失敗通常是 prompt 本身問題或 quota，重試只浪費 token）
- ❌ 不寫 sidecar（user 之後翻舊圖找不回原 prompt）
- ❌ heartbeat 刷屏（user 已經知道在跑了，給一行就好）
- ❌ 背景啟動後用 `sleep N; tail` 前景輪詢等 codex（阻塞主線程、卡死 user 對話）→ 讓出控制權、等 task 完成通知自動喚回
- ❌ 圖被 keep / 搬走卻把 sidecar 留在原（暫存）目錄 → prompt 隨目錄清掉就永久消失（sidecar 要跟圖走）
- ❌ 用 `$imagegen` token 卻沒 escape `\$imagegen`（shell 展開成空）→ 現行改用自然語指示「用內建 image_gen 工具」、免此坑
- ❌ 在 user 還在改 prompt 的迭代過程中提前算 slug / 建目錄 / 啟動 codex（pre-flight 在拍板**之後**才做）

**編輯模式專屬**：

- ❌ 🔴 把編輯結果轉 jpg（帶透明度就永久消失，而編輯結果不可重現）→ 編輯模式一律交 png
- ❌ 用 `mode in ("RGBA","LA")` 判有沒有透明度 → **漏掉 `mode P` 的透明 PNG**，會判成「沒 alpha」然後一路轉成 jpg。要判就用 `mode in ("RGBA","LA","PA") or "transparency" in im.info`；但更好的作法是**根本不要判**（見上一條）
- ❌ 驗收拿「四角必須全透明」當去背的判準 → 主體貼齊邊緣的構圖（半身像、滿版）本來就有不透明的角，會**假失敗**；一個 MANDATORY 閘門只要常假失敗，agent 就學會忽略它
- ❌ 編輯模式沿用生成模式的包裝動詞「生圖」→ 那個動詞會稀釋 `CHANGE EXACTLY ONE THING`
- ❌ 編輯模式加 img2img 的身份鎖（「保持臉部特徵…一致」）→ 「保持一致」＝「重新生成一張像的」，正是驗收要抓的失敗態
- ❌ 編輯 prompt 只寫「把背景去掉」「把 X 拿掉」而**沒有保留清單** → 模型會重新生成一張「很像的」，不是就地修改
- ❌ 編輯 prompt 沒鎖畫布尺寸 → 模型吐一個常見比例，主體位置全跑掉
- ❌ 去背只寫 "remove the background" → 可能得到「背景被畫成白色」或「棋盤格被畫成像素」→ 要明寫 genuine ALPHA CHANNEL + 三個 not
- ❌ **只看圖覺得「好像沒變」就當編輯成功** → 肉眼分辨不出幾十像素的位移，一定要跑 Step 5b 量
- ❌ 編輯模式沒底圖時退化成「生一張像的」交差 → 沒有本機實體檔就是不成立，如實講
- ❌ Step 5b 沒過就自動改 prompt 重送 → 失敗不自動重試，交給 user 決定

---

## Important rules

1. **拍板 = 明確 keyword（OK / 生 / go / 下去），不准語意推測** — 違規即破壞 user 信任（＝紅線 1）
2. **先分模式再動手**：生成 vs 編輯。判準＝「user 會不會拿輸出去跟原圖逐像素比對」。分不出來就問一句，別猜
3. **有 reference image → 走 img2img 或編輯（codex `-i`）** — 底圖有本機檔就跑；只有「對話內嵌圖、無本機檔」才問路徑 / 退 manual（＝紅線 2）
4. **不寫死預設風格** — 風格 100% 來自當下 context 與 user 描述（＝紅線 3）。**NSFW 判斷依 context，警告而非阻擋**，不替 user 做安全決策
5. **背景跑 + 讓出主線程 + 一行 heartbeat，靠 task 完成通知喚回收圖** — 禁前景 `sleep N; tail` 輪詢（會阻塞 user 對話）；harness 沒有獨立 `Monitor` 工具，task 系統就是 monitor
6. **收圖主路 = prompt-save**：launch 時在 prompt 內叫 codex 存到 `$OUT_PNG`，收圖直接讀該檔。撈 `generated_images` / 解 rollout base64 只是 fallback（0.141.0 起 generated_images 時有時無、不可當主路）
7. **Sidecar `<image>.prompt.md` 是強制產出** — 含中英 prompt + metadata，是 prompt 的**唯一持久記錄**；`output_image` 填 `$FINAL` 不是寫死 `.jpg`；**圖被搬走 / 保留 (keep) 時 sidecar 必須跟著走**
8. **生成模式交付 jpg q85，png 中繼轉完即刪**（user 明講要無損、或那張圖會被再利用時才留）；🔴 **編輯模式一律交 png，不轉 jpg，無例外**（＝紅線 4）；**兩種模式都不自動開圖**，中繼與 `~/.codex/generated_images/` 的殘留跑完清掉
9. **編輯模式必跑 Step 5b 驗收**（尺寸／透明度／主體像素保真），`VERDICT: PASS` 才交付。**「看起來沒變」不是證據** — 模型有可能交回一張重新生成的、看起來很像的圖
10. **失敗不自動重試**（含「驗收未過」）— 貼量測值與可能成因，交給 user 決定
11. **這 skill 做生成與圖片編輯，但不做 UI 設計、不做 ASCII art** — 走錯領域請 user 改用 Claude Design / 其他工具

---

## 已知限制（實測，會隨 codex 版本變）

| 項目 | 現況 |
|---|---|
| 去背的遮罩精度 | 實測可到**髮絲級**，主體像素**逐位元不變**（最大色差 0）—— 它是遮罩不是重生 |
| **抗鋸齒** | ⚠️ **alpha 是二值的（只有 0 與 255，零個半透明階）**。原尺寸看不出來，但**縮放時硬邊可能顯出鋸齒** |
| 補救 | 要羽化就自己對 alpha 做一次 1px 模糊，**不必重生**（重生反而會失去像素保真） |

⚠️ 以上是單一版本的單次實測，**別當鐵則**（呼應 anti-patterns 那條「把單次觀察當鐵則」）。
換 codex 版本後重驗一次 Step 5b 的三項，比讀這張表可靠。
