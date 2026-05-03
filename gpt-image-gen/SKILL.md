---
name: gpt-image-gen
description: "Use when the user asks to generate an image via GPT/Codex (e.g. 「叫 gpt 生圖」「幫我用 gpt 生圖」「gpt 畫一個 X」). The skill drafts a Chinese + English prompt pair, iterates with the user until they explicitly approve, then dispatches Codex CLI ($imagegen skill, gpt-image-2) in the background, monitors progress, moves the result into the current working directory, and writes a sidecar prompt log. Text-to-image only — no image edits, no reference-image input via Codex."
version: 0.1.0
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

# gpt-image-gen — 用 Codex CLI 叫 gpt-image-2 生圖

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
（gpt-image-2 吃的高密度英文 prompt。
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
# 時間戳
TS=$(date +%Y%m%d_%H%M%S)

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

OUT_IMG="$OUT_DIR/${TS}_${SLUG}.png"
OUT_SIDECAR="$OUT_DIR/${TS}_${SLUG}.prompt.md"
LAST_MSG="/tmp/codex_imagegen_${TS}.lastmsg"
LOG_FILE="/tmp/codex_imagegen_${TS}.log"
```

### Step 4b: 背景啟動 codex exec

用 `Bash` 工具，`run_in_background: true`：

```bash
codex exec "<英文 prompt 內容> \$imagegen" \
  --full-auto \
  --output-last-message "$LAST_MSG" \
  > "$LOG_FILE" 2>&1
```

**注意**：
- `--full-auto` = `--sandbox workspace-write` + 自動執行（不卡 approval）。**不要**用舊版的 `--sandbox <mode> --ask-for-approval never`，新版 codex 不認那組 flag。
- prompt 內的 `$imagegen` 在 bash 字串裡要 escape 成 `\$imagegen`，不然 shell 會把它當變數展開成空字串。
- prompt 用 double-quote 包，內含的 `"` / `` ` `` / `$` 全部 escape。
- 不要加 `--json`（log 會難 parse）。
- 跑前若不確定 flag 是否還對齊，先 `codex exec --help` 確認一次再執行。

### Step 4c: Monitor 看 log

啟動 `Monitor` 看 `$LOG_FILE`，等到下列任一條件成立：

| 條件 | 含義 | 動作 |
|------|------|------|
| log 出現 `image saved to` 或 `Generated image:` 之類字眼 | 成功，圖在 `~/.codex/generated_images/` 下 | 進 Step 5 |
| 背景 process 結束（Bash 通知） | 不論成敗都收尾 | 進 Step 5 / Step 6 |
| Monitor 看到 `error` / `rate limit` / `safety` / `rejected` | 失敗 | 進 Step 6 |

期間給 user **一行** heartbeat（避免他以為當機）：
```
Codex 跑起來了，背景生圖中（gpt-image-2 一般 30-90s），等成品...
```
不要刷屏。

---

## Step 5: 收圖 + 寫 sidecar + 通知

### Step 5a: 從 `$LAST_MSG` parse 出實際路徑

`codex exec --output-last-message` 會把 codex 最後 assistant message 寫進去。imagegen 完成後通常會講出實際存檔路徑（在 `$CODEX_HOME/generated_images/` 底下，預設 `~/.codex/generated_images/`）。

```bash
# 抓出 codex 寫的圖片路徑（可能是絕對 / 可能是 ~/...）
SRC_IMG=$(grep -oE '(/Users|/home|~)[^[:space:]]*\.(png|jpg|jpeg|webp)' "$LAST_MSG" | head -1 | sed "s|^~|$HOME|")
```

如果 grep 沒抓到，fallback：找 `~/.codex/generated_images/` 底下這次 timestamp 之後最新的圖檔。

### Step 5b: 搬到目標位置

```bash
mv "$SRC_IMG" "$OUT_IMG"
```

**MANDATORY**：用 `mv` 不是 `cp` — codex 預設位置只是中繼，留著會堆積。

### Step 5c: 寫 sidecar

格式固定：

```yaml
---
timestamp: 2026-05-03T20:45:00+08:00
trigger: "<user 觸發那句原文>"
reference_image: null
codex_model: gpt-image-2
codex_exit: success
output_image: <絕對路徑>
---

# 中文 prompt

<拍板版本的中文 prompt>

# English prompt

<拍板版本的英文 prompt（實際送 codex 的）>
```

寫進 `$OUT_SIDECAR`。

### Step 5d: 通知 user

```
✅ 生好了
- 圖：<相對 cwd 路徑>
- prompt log：<相對 cwd 路徑>
（已自動 open 預覽）
```

然後跑：
```bash
open "$OUT_IMG"
```

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
8. **`mv` 不 `cp`，中繼 log 跑完清掉** — 不要在 `/tmp/` 與 `~/.codex/generated_images/` 留垃圾
9. **失敗不自動重試** — 印 log 摘要交給 user 決定
10. **這 skill 不做 image edit、不做 UI 設計、不做 ASCII art** — 走錯領域請 user 改用 Claude Design / 其他工具
