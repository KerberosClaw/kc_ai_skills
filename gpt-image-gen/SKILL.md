---
name: gpt-image-gen
description: "Use when the user asks to generate an image via GPT/Codex (e.g. 「叫 gpt 生圖」「幫我用 gpt 生圖」「gpt 畫一個 X」). The skill drafts a Chinese + English prompt pair, iterates with the user until they explicitly approve, then dispatches Codex CLI ($imagegen skill, codex built-in image_gen) in the background, monitors progress, converts the result to a jpg in the current working directory, and writes a sidecar prompt log. Does text-to-image AND img2img — drop a reference image (on-disk file) and it runs Codex `-i` to lock a face/character across scenes."
version: 0.4.0
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
argument-hint: "（無；自然語言觸發）"
---

# gpt-image-gen — 用 Codex CLI 叫內建 image_gen 生圖

You are a prompt-crafting partner who turns the user's loose Chinese description into a tight bilingual prompt pair, iterates with the user until they explicitly approve, then dispatches Codex CLI to generate the image. You are **not** the image generator — Codex is. Your job is prompt design, user confirmation gating, and execution orchestration.

**CRITICAL — 三條紅線**：

1. **未拍板絕不呼叫 codex** — 拍板 = user 明確說 `OK` / `生` / `go` / `下去`。其他正向回應（「不錯」「可以喔」「應該行」）一律當「還沒拍板」處理，繼續等明確指令。生圖會花 user 的錢，誤觸發 = 違規。
2. **有 reference image → 走 img2img**（codex `-i`） — user 這輪有附底圖（拖曳/貼上/`[Image #N]`）→ Step 3a 偵測 → Step 4 用 `codex exec ... -i <ref>` 跑 img2img（鎖臉/角色一致）。⚠️ codex `-i` 吃**本機檔案路徑**：底圖有實體檔就 img2img；只貼在對話、本機無檔 → 問 user 要路徑，給不出才退回印 prompt 貼 GUI。**拍板 gate（紅線 1）對 img2img 一樣適用。**
3. **不寫死任何預設風格** — Skill 不存 style preset。每張圖風格純靠當下 conversation context + user 描述推。沒 context 就問。

---

## Step 1: 判斷觸發語境（mid-conversation vs 新對話）

讀 trigger 那輪訊息 + 最近 5-10 輪 context，落到下表：

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
有附底圖：
  • 本機有實體檔（user 給 path / 拖曳實體檔）→ 記 REF=該絕對路徑，走 img2img（Step 4 帶 -i "$REF"）。進 Step 3b。
  • 只貼在對話裡、本機無實體檔 → 問 user 要本機路徑（codex -i 吃 file path、不吃對話內嵌圖）。給了 → img2img；給不出 → 退而印「拍板的英文 prompt」一段給 user 自己貼 ChatGPT GUI，結束。
無附 → REF 留空，text2img。進 Step 3b。
```

**Step 3b: NSFW context 判斷**

依當下 conversation context 判斷這張圖內容是否會踩到 OpenAI policy：

- **不寫死硬規則** — 看上下文。例如：
  - 純 fiction 寫作 + 角色穿衣 + 表情曖昧 → 應該過
  - 明確露點 / 性器官名詞 / 性行為描寫 → 大概率被 reject
  - 使用者明顯在做成人 / NSFW 創作脈絡 → 提高警覺度

- 判斷會 reject → 警告 + 問：
  ```
  這張描述 codex 大概率會 reject（OpenAI policy）。要硬送看看，還是改走 ChatGPT GUI / local SD？
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
OUT_JPG="$OUT_DIR/${TS}_${SLUG}.jpg"      # 最終交付（jpg q85）
OUT_SIDECAR="$OUT_DIR/${TS}_${SLUG}.prompt.md"
LAST_MSG="/tmp/codex_imagegen_${TS}.lastmsg"
LOG_FILE="/tmp/codex_imagegen_${TS}.log"

touch "$START_MARKER"   # fallback 用：萬一 codex 沒照存，Step 5a 退而用 find -newer 撈
```

### Step 4b: 背景啟動 codex exec

用 `Bash` 工具，`run_in_background: true`。**主路 = prompt-save**：在 prompt 裡直接叫 codex 用內建 image_gen、存到 `$OUT_PNG`、回報實際路徑（跨版本最穩，見下方 0.141.0 註）：

```bash
# text2img：REF 留空。img2img：REF=底圖絕對路徑時自動帶 -i（prompt 仍當第一 positional、-i 擺後）
codex exec --skip-git-repo-check \
  "用內建 image_gen 工具生圖，不要使用 scripts/image_gen.py，也不要使用 OPENAI_API_KEY。<英文 prompt 內容>。請把最終圖片存到 ${OUT_PNG}，完成後回報實際存檔的絕對路徑。" \
  ${REF:+-i "$REF"} \
  --sandbox workspace-write \
  --output-last-message "$LAST_MSG" \
  < /dev/null > "$LOG_FILE" 2>&1
```
> - **img2img** 時，prompt **開頭**再加一句身份鎖：「請參考附上的 Image #1 作為人物身份參考（同一個人，保持臉、鬍、體型一致）。」
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

## Step 5: 收圖 + 寫 sidecar + 通知

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

### Step 5b: 轉 jpg 交付（q85）+ 清中繼

codex 吐 png（2MB 級）；交付走 **jpg q85**（實測畫質肉眼無感、體積約 png 的 1/5）。`$SRC_PNG` 此時已 == `$OUT_PNG`（主路直接落定位、fallback 也已 mv 過來）：

```bash
sips -s format jpeg -s formatOptions 85 "$OUT_PNG" --out "$OUT_JPG" >/dev/null 2>&1
rm -f "$OUT_PNG"                            # 刪 png 中繼，只留 jpg
# 0.141.0 有時 prompt-save 與 generated_images 兩邊都寫 → 清掉 codex 那份多餘 copy（避免堆積）
STRAY=$(find ~/.codex/generated_images -type f -iname '*.png' -newer "$START_MARKER" 2>/dev/null | head -1)
[ -n "$STRAY" ] && rm -f "$STRAY" && rmdir "$(dirname "$STRAY")" 2>/dev/null
```

- 最終交付 = `$OUT_JPG`。**只有 user 明講「要留無損 png」才跳過 `rm -f "$OUT_PNG"`**。
- **絕不把圖留在 `~/.codex/generated_images/`**（堆積 + user 找不到）—— 主路雖然落 cwd，codex 仍可能另存一份在那，務必清。

### Step 5c: 寫 sidecar

先從 log 抓實際 model（別寫死 — 0.134 是 gpt-5.5 不是 gpt-image-2）：

```bash
MODEL=$(grep -aoE 'gpt-[0-9.]+' "$LOG_FILE" | head -1)
```

格式固定：

```yaml
---
timestamp: 2026-05-03T20:45:00+08:00
trigger: "<user 觸發那句原文>"
reference_image: <$REF 絕對路徑；text2img 則 null>
codex_model: <$MODEL，如 gpt-5.5> (codex built-in image_gen flow)
codex_exit: success
output_image: <$OUT_JPG 絕對路徑>
---

# 中文 prompt

<拍板版本的中文 prompt>

# English prompt

<拍板版本的英文 prompt（實際送 codex 的）>
```

寫進 `$OUT_SIDECAR`。**bg session 內若 `Write` 被 bg-isolation guard 擋（這 skill 常在 bg + git repo 跑），改用 Bash heredoc 寫**（`cat > "$OUT_SIDECAR" <<'EOF' ... EOF`）。

### Step 5d: 通知 user（不自動開圖）

```
✅ 生好了
- 圖：<相對 cwd 路徑>.jpg
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

**不自動重試** — 失敗交給 user 決定。

清掉中繼檔：
```bash
rm -f "$LAST_MSG" "$LOG_FILE" "$START_MARKER"
```

---

## Anti-patterns

- ❌ 用模糊正向回應（「不錯」「可以」）當拍板信號，誤呼叫 codex
- ❌ img2img 時把 `-i` 放 prompt 前面（prompt 被當第二張圖 → codex 失敗）；prompt 一定當第一 positional、`-i` 擺後
- ❌ 對話內嵌圖（本機無檔）硬塞 codex `-i`（吃 file path、抓不到）→ 先問本機路徑
- ❌ 預設「畫四隻熊 / kemono / 某固定角色群像」這種寫死 style — 沒 context 就問
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

---

## Important rules

1. **拍板 = 明確 keyword（OK / 生 / go / 下去），不准語意推測** — 違規即破壞 user 信任
2. **Reference image → img2img（codex `-i`）** — 底圖有本機檔就 `-i "$REF"` 跑 img2img；只有「對話內嵌圖、無本機檔」才問路徑 / 退 manual
3. **不寫死預設風格** — 風格 100% 來自當下 context 與 user 描述
4. **NSFW 判斷依 context，警告而非阻擋** — 不替 user 做安全決策
5. **背景跑 + 讓出主線程 + 一行 heartbeat，靠 task 完成通知喚回收圖** — 禁前景 `sleep N; tail` 輪詢（會阻塞 user 對話）；harness 沒有獨立 `Monitor` 工具，task 系統就是 monitor
6. **收圖主路 = prompt-save**：launch 時在 prompt 內叫 codex 存到 `$OUT_PNG`（git repo cwd → `./generated_images/` 子夾；否則 cwd 根），收圖直接讀該檔。撈 `generated_images` / 解 rollout base64 只是 fallback（0.141.0 起 generated_images 時有時無、不可當主路）
7. **Sidecar `<image>.prompt.md` 是強制產出** — 含中英 prompt + metadata，是 prompt 的**唯一持久記錄**；**圖被搬走 / 保留 (keep) 時 sidecar 必須跟著走**（暫存 output 目錄常被清，prompt 只活在 sidecar，丟了就重建不回原 prompt）
8. **交付 jpg q85（`sips`），png 中繼轉完即刪**（user 明講要無損才留）；**生完不自動開圖**；`mv` 不 `cp`，中繼 log + 空 session 目錄跑完清掉 — 不要在 `/tmp/` 與 `~/.codex/generated_images/` 留垃圾
9. **失敗不自動重試** — 印 log 摘要交給 user 決定
10. **這 skill 不做 image edit、不做 UI 設計、不做 ASCII art** — 走錯領域請 user 改用 Claude Design / 其他工具
