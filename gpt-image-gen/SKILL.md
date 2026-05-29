---
name: gpt-image-gen
description: "Use when the user asks to generate an image via GPT/Codex (e.g. 「叫 gpt 生圖」「幫我用 gpt 生圖」「gpt 畫一個 X」). The skill drafts a Chinese + English prompt pair, iterates with the user until they explicitly approve, then dispatches Codex CLI ($imagegen skill, codex built-in image_gen) in the background, monitors progress, converts the result to a jpg in the current working directory, and writes a sidecar prompt log. Text-to-image only — no image edits, no reference-image input via Codex."
version: 0.2.0
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
2. **有 reference image 不呼叫 codex** — Codex `$imagegen` 是 text-to-image only。user 這輪有附底圖（任何形式：拖曳、貼上、`[Image #N]`）→ 切 manual mode：印 prompt 給 user 自己貼到 ChatGPT GUI，**不**呼叫 codex。
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
有附 → 走 manual mode：
  印「拍板的英文 prompt」一段（純 prompt，不要任何前後文 wrap）
  附一句說明：「Codex $imagegen 不收底圖，這條改你貼到 ChatGPT GUI 自己生。
              產出後丟回給我可以一起看 / 後續微調 prompt。」
  結束流程，不呼叫 codex
無附 → 進 Step 3b
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

## Step 4: 呼叫 Codex（背景跑 + Monitor 監看）

### Step 4a: 組路徑與檔名

```bash
# 時間戳 + 啟動 epoch（START_EPOCH 給 Step 5a 收圖用）
TS=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date +%s)

# slug：從中文 prompt 抽 1-3 個關鍵詞，連字號連接，去掉空白與標點
# 範例：「一隻棕熊在雪山頂看日出」→ "brown-bear-summit-sunrise"
SLUG="<由你從中文 prompt 抽出>"

# 判斷 cwd 是否 git repo
if git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1; then
  OUT_DIR="$PWD/generated_images"
  mkdir -p "$OUT_DIR"
else
  OUT_DIR="$PWD"
fi

OUT_PNG="$OUT_DIR/${TS}_${SLUG}.png"      # codex 原始 png（中繼，轉 jpg 後刪）
OUT_JPG="$OUT_DIR/${TS}_${SLUG}.jpg"      # 最終交付（jpg q85）
OUT_SIDECAR="$OUT_DIR/${TS}_${SLUG}.prompt.md"
LAST_MSG="/tmp/codex_imagegen_${TS}.lastmsg"
LOG_FILE="/tmp/codex_imagegen_${TS}.log"
```

### Step 4b: 背景啟動 codex exec

用 `Bash` 工具，`run_in_background: true`：

```bash
codex exec "<英文 prompt 內容> \$imagegen" \
  --sandbox workspace-write \
  --output-last-message "$LAST_MSG" \
  > "$LOG_FILE" 2>&1
```

**Flag 註解**（codex-cli 0.134.0 實測對齊；新版本前先 `codex exec --help` 確認）：

- **`--sandbox workspace-write`**：允許 codex 寫進 workspace（含 codex 把生成圖落地到 `~/.codex/generated_images/`）。
- **`codex exec` 沒有 `--ask-for-approval`** — 那 flag 只在 top-level `codex`，exec 預設就是 non-interactive never-ask，不需另指定。
- **`--full-auto` 已 deprecated**（0.128.0 起），等同 `--sandbox workspace-write`。**不要用**。
- **`-o, --output-last-message`**：把 codex 最後 assistant message 寫進指定檔，後續用來 parse 圖片實際路徑。
- **`-i, --image <FILE>`**：exec 技術上支援附 input image，但本 skill **不用** — 有底圖直接走 manual mode（Step 3a），別把責任丟回 codex。

**Prompt 字串注意**：
- prompt 內的 `$imagegen` 在 bash 字串裡要 escape 成 `\$imagegen`，不然 shell 會把它當變數展開成空字串，codex 不會啟用 imagegen skill。
- prompt 用 double-quote 包，內含的 `"` / `` ` `` / `$` 全部 escape。
- 不要加 `--json`（log 變 JSONL，反而難用 grep / Monitor 監看）。

> ⚠️ **0.134.0 版差異（踩過、直接影響 Step 5 收圖）**：codex 改用 `gpt-5.5` orchestrator + 內建 `image_gen` flow，不再是 gpt-image-2，連帶兩個 output 形狀變了：
> 1. `--output-last-message` **不再吐圖片路徑**（只寫一句「Generated the image...」）→ 別再 grep LAST_MSG 抓路徑。
> 2. 圖落在**巢狀** `~/.codex/generated_images/<session-id>/ig_*.png`，不是平鋪。
> 3. 固定輸出 **png**（無法指定格式）→ 交付前自行轉 jpg。

### Step 4c: Monitor 看 log

啟動 `Monitor` 看 `$LOG_FILE`，等到下列任一條件成立：

| 條件 | 含義 | 動作 |
|------|------|------|
| log 出現 `image saved to` 或 `Generated image:` 之類字眼 | 成功，圖在 `~/.codex/generated_images/` 下 | 進 Step 5 |
| 背景 process 結束（Bash 通知） | 不論成敗都收尾 | 進 Step 5 / Step 6 |
| Monitor 看到 `error` / `rate limit` / `safety` / `rejected` | 失敗 | 進 Step 6 |

期間給 user **一行** heartbeat（避免他以為當機）：
```
Codex 跑起來了，背景生圖中（一般 30-90s），等成品...
```
不要刷屏。

---

## Step 5: 收圖 + 寫 sidecar + 通知

### Step 5a: 收圖（以 mtime 為錨，不依賴 LAST_MSG）

0.134.0 起 LAST_MSG 不吐路徑、圖又落巢狀 session 目錄（見 Step 4b 警告），所以**用啟動前記下的 `START_EPOCH` 遞迴找之後最新的 png**：

```bash
SRC_PNG=$(find ~/.codex/generated_images -type f -iname '*.png' -newermt "@$START_EPOCH" 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
```

- **用 `find` 不用 glob**：巢狀目錄要遞迴，且空 glob 在 zsh 會 `no matches found` 中止（踩過）。
- session id 那條路（grep log 的 `session id:`）**不要用** — log 有 ANSI 色碼夾在 `session id:` 跟 uuid 之間，regex 易撲空、反而脆弱。
- `SRC_PNG` 抓空 → codex 大概率失敗，跳 Step 6。

### Step 5b: 轉 jpg 交付（q85）+ 清中繼

codex 吐 png（2MB 級）；交付走 **jpg q85**（實測畫質肉眼無感、體積約 png 的 1/5）：

```bash
mv "$SRC_PNG" "$OUT_PNG"                    # 搬出 codex 中繼目錄
rmdir "$(dirname "$SRC_PNG")" 2>/dev/null   # 清掉空的 session 子目錄
sips -s format jpeg -s formatOptions 85 "$OUT_PNG" --out "$OUT_JPG" >/dev/null 2>&1
rm -f "$OUT_PNG"                            # 刪 png 中繼，只留 jpg
```

- **MANDATORY**：`mv` 不 `cp` — codex 預設位置只是中繼、留著會堆積。
- 最終交付 = `$OUT_JPG`。**只有 user 明講「要留無損 png」才跳過 `rm -f "$OUT_PNG"`**。

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
reference_image: null
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
rm -f "$LAST_MSG" "$LOG_FILE"
```

---

## Anti-patterns

- ❌ 用模糊正向回應（「不錯」「可以」）當拍板信號，誤呼叫 codex
- ❌ user 有附底圖卻硬呼叫 codex（codex 不收 reference image，浪費 quota）
- ❌ 預設「畫四隻熊 / kemono / 某固定角色群像」這種寫死 style — 沒 context 就問
- ❌ Skill 內部偷偷加 NSFW filter 替 user 做決策（只警告 + 給選項）
- ❌ 把生圖結果留在 `~/.codex/generated_images/` 不搬走（堆積 + user 找不到）
- ❌ 圖搬到 cwd 根但 cwd 是 git repo（會雜進 git status / 容易誤 commit）
- ❌ 用 `cp` 不用 `mv` 搬 codex 中繼檔
- ❌ 依賴 `LAST_MSG` grep 圖片路徑收圖（0.134 起 codex 不吐路徑、此法必撲空）
- ❌ 用 shell glob（`ls $DIR/*.png`）收圖（巢狀目錄漏抓 + 空 glob 在 zsh 中止）→ 改 `find -newermt`
- ❌ 生完自動 `open` 圖（user 不要）
- ❌ sidecar 寫死 `codex_model: gpt-image-2`（實際是 log 裡的 model）
- ❌ 失敗自動重試（codex 失敗通常是 prompt 本身問題或 quota，重試只浪費 token）
- ❌ 不寫 sidecar（user 之後翻舊圖找不回原 prompt）
- ❌ heartbeat 刷屏（user 已經知道在跑了，給一行就好）
- ❌ prompt 字串內 `$imagegen` 沒 escape（shell 會展開成空，codex 不會啟用 imagegen skill）
- ❌ 在 user 還在改 prompt 的迭代過程中提前算 slug / 建目錄 / 啟動 codex（pre-flight 在拍板**之後**才做）

---

## Important rules

1. **拍板 = 明確 keyword（OK / 生 / go / 下去），不准語意推測** — 違規即破壞 user 信任
2. **Reference image 自動切 manual mode** — 不要試圖把底圖塞 codex，那條路不通
3. **不寫死預設風格** — 風格 100% 來自當下 context 與 user 描述
4. **NSFW 判斷依 context，警告而非阻擋** — 不替 user 做安全決策
5. **背景跑 + Monitor 看 log + 一行 heartbeat** — 不阻塞 user 對話、不刷屏
6. **cwd 是 git repo → `./generated_images/` 子資料夾；否則 → cwd 根**
7. **Sidecar `<image>.prompt.md` 是強制產出** — 含中英 prompt + metadata，方便日後翻
8. **交付 jpg q85（`sips`），png 中繼轉完即刪**（user 明講要無損才留）；**生完不自動開圖**；`mv` 不 `cp`，中繼 log + 空 session 目錄跑完清掉 — 不要在 `/tmp/` 與 `~/.codex/generated_images/` 留垃圾
9. **失敗不自動重試** — 印 log 摘要交給 user 決定
10. **這 skill 不做 image edit、不做 UI 設計、不做 ASCII art** — 走錯領域請 user 改用 Claude Design / 其他工具
