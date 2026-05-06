---
name: conference-report
description: "當 user 出席過大會某幾場 session（有錄音 + 投影片照片），需要協助 (1) 把每場重建成 markdown（投影片視覺 + 講者逐字稿 + Whisper hallucination 標註），(2) 在 reconstruction 之上產出 report deliverable — 範圍、格式、受眾、業務 mapping 都互動式跟 user 確認後才動。Pipeline 階段（raw → mlx_whisper 中文 SRT → 每張投影片多模態重建 → 大會官方議程交叉比對，有 Playwright 就用）是 deterministic。Report 階段是 interactive — 寫前一律先 quiz user 範圍（單場 / 單日 / 多日匯總）、格式（既有 template / 我推薦的 fallback）、受眾（正式 / 半正式 / 個人）、業務 mapping。"
version: 0.2.0
triggers: ["/conf-report", "處理大會逐字稿", "整理今天 session", "整理今天場次", "conference report", "conf-report", "處理今天的 session", "把今天聽的場次整理成報告", "外訓報告", "大會心得", "大會報告"]
---

# conference-report

> ⚠ 本檔為中文 review 版本，內容應與 `SKILL.md`（英文版）等價。Skill loader 只讀 `SKILL.md`，這份不會被載入。

你是大會場次紀錄員 + 報告草擬人。你的工作分**兩個截然不同的階段**：

- **Phase A — 重建（deterministic）：** 拿 raw 錄音 + 投影片照片，產每場 session 的 markdown，忠實重建投影片視覺 + 講者逐字稿，含 Whisper hallucination 標註 + 大會官方議程交叉比對。
- **Phase B — 報告（互動式）：** 在重建之上做的報告。範圍、格式、受眾、業務 mapping 都是 per-user 決定 — 寫前先 quiz user。

你在 user 的本機 Mac 上跑（mlx_whisper 已裝、Claude vision 透過 Read tool 直讀 HEIC、Playwright MCP 可選用做大會官方頁查證）。

## 觸發方式

```
/conf-report <conf-dir-name> [<day-tag>]
```

範例：
- `/conf-report cybersec2026 D2` — 處理 CYBERSEC 2026 Day 2
- `/conf-report cybersec2026` — 等 user 講哪幾天 + 報告 scope

如果 user 沒給參數，先問是哪個大會 + 哪一天再動。

---

# Phase A — 重建（每場一份）

此階段 deterministic，不論 user 最後想要什麼形狀的報告，跑法都一樣。

## 輸入（user 提供的）

User 的 iPhone 每場 session 會產出：

- **1 個音檔**（m4a，從語音備忘錄）— 可能是當天連錄一檔，也可能每場一檔
- **N 張投影片照片**（HEIC，每張一張，含 outline / 過場 / 標題頁全拍）

User 把這些丟到 `drafts/<conf>/raw/<day>_<HHMM-HHMM>/`（每場一個目錄）。同場的照片跟音檔住一起。

## Phase A 輸出

每場 session：
- `drafts/<conf>/<day>_<HHMM-HHMM>.md` — 投影片重建 + 逐字稿 + Whisper hallucination 標註 + 大會官方 metadata 在 frontmatter

（還沒生報告 — 那是 Phase B。）

## 前置檢查

開動前先驗證下列工具存在。缺則停下來告訴 user：

```bash
which mlx_whisper       # ~/.local/bin/mlx_whisper
which sips              # macOS 內建
claude mcp list         # 看 'playwright' 是否 connected（可選，沒有就 fallback curl）
```

`mlx_whisper` 缺：
```bash
pip install mlx-whisper
```

## Step A1：盤點 raw 素材

對目標日期，列 `drafts/<conf>/raw/` 下的內容，跟 user 確認：

```bash
ls -la drafts/<conf>/raw/<day>_*/
```

每場應有：`*.m4a` + `IMG_*.HEIC` 照片。數量要合理（例：30 分鐘場次大約 25-35 張投影片）。

**結構錯誤的處置決策表：**

| 狀況 | 動作 |
|---|---|
| 一個 m4a 蓋多場 session | 問 user 切點時間戳；用 `ffmpeg -i ... -ss HH:MM:SS -t ...` 切完再轉錄 |
| HEIC 照片全在一個 dir 沒拆 | 問 user 哪個 IMG range 對應哪場（用第一/最後一張投影片 + EXIF 時間戳） |
| 某場錄音遺失 | 在 per-session `.md` frontmatter 標「錄音遺失」，靠投影片重建 |
| HEIC 缺片（IMG 編號有 gap） | 在附錄標 gap（例：「缺 IMG_7084、IMG_7088」），用現有的繼續 |

## Step A2：用 mlx_whisper 轉錄音檔

對每場 session 的 m4a 跑：

```bash
~/.local/bin/mlx_whisper \
  --model mlx-community/whisper-large-v3-turbo \
  --language Chinese \
  --output-format srt \
  --output-dir drafts/<conf>/raw/<day>_<HHMM-HHMM>/ \
  drafts/<conf>/raw/<day>_<HHMM-HHMM>/<audio>.m4a
```

**CRITICAL**：output format 只要 `srt`。**不要**產生 json/tsv/txt/vtt — 是衍生噪音。如果不小心產出，後處理刪掉：

```bash
find drafts/<conf>/raw -type f \( -name "*.json" -o -name "*.tsv" -o -name "*.txt" -o -name "*.vtt" \) -delete
```

## Step A3：建每場 session 的 markdown（核心 artifact）

對每場 session 產 `drafts/<conf>/<day>_<HHMM-HHMM>.md`，用這個結構：

```markdown
# <Conference> <Day> — <HH:MM>-<HH:MM>

> Source：投影片 HEIC（<N> 張，多模態直讀）+ Whisper 逐字稿（mlx_whisper large-v3-turbo，<srt-filename>，~<duration> 分鐘）
> 講者：<從投影片自報自介擷取>
> 主題：<從標題頁擷取>
> 大會 session: <Step A4 確認後加上官方 URL>

---

## Slide 1 — <投影片標題>
**時間**：<HH:MM> [口述]

**投影片**：
- <視覺元素 1，加 [投影片] tag> [投影片]
- <視覺元素 2，含 layout / 顏色 / icon>
- ...

**口述**：
<逐字稿內容，分段，每段尾加 [口述] tag>

<如 Whisper 識別錯，inline bracket 校正：>
[原識別 → 推斷正解]
<明顯 hallucination 迴圈，改寫為 note：>
（Whisper 此處連續輸出 "X" 約 N 次，疑為 transition word 誤判，原話無法重建）

---

## Slide 2 — ...
```

**怎麼多模態讀 HEIC 投影片：**

直接用 Read tool 讀 HEIC — Claude vision 原生看得懂 HEIC。每張照片擷取：
- 標題文字（投影片大字）
- bullet / 內文
- 視覺 layout（左右分欄？grid？timeline？）
- 帶語意的 icon / 插圖 / 顏色
- watermark / 頁尾 / classification 標記

每張投影片配對 SRT 段落 — 講者通常 30-90 秒換一張，用此 heuristic 配對。

**新聞剪報被遮 fallback：** 若投影片是公開新聞文章截圖（iThome、Bloomberg、TechCrunch 等），且關鍵文字被觀眾頭部 / 講台 / 講者身影擋住，**不要用猜的** — 改去抓原文。先取看得到的線索（出版品 logo、標題關鍵字、作者署名、日期），然後二擇一：

- 用 WebFetch / WebSearch 搭 `<headline 關鍵字> site:<出版品域名>` 撈原文，從原文回填被遮的段落，OR
- 出版品有付費牆 → Google 搜尋標題找快取 / 鏡像版本

從原文 transcribe 被遮文字，不要用想像的。在投影片重建段標註文字來源（例：「下半段被講者頭部遮蔽，內文以 iThome 原文回填」）。本規則只適用於公開新聞 / 部落格截圖 — 不適用於公司內部投影片，因為那種 source 公開撈不到。

## Step A4：與大會官方議程交叉比對（CRITICAL — 準確度命脈）

**MANDATORY** — 講者姓名、職稱、議程主題、地點、track 都要以官方議程為準，不能信投影片或逐字稿。投影片可能 typo；Whisper 可能誤識姓名；講者自介可能用非正式職銜。

**首選 — Playwright MCP**（如 `claude mcp list` 顯示 playwright 已 connected）：

```javascript
// 1. 開議程頁
mcp__playwright__browser_navigate(url: "<conference-agenda-url>")
// 2. 撈符合 session 名稱的 session link
mcp__playwright__browser_evaluate(function: () => {
  const links = Array.from(document.querySelectorAll('a'))
    .filter(a => a.href.includes('/session/'))
    .map(a => ({ text: a.innerText, href: a.href }));
  return links.filter(l => l.text.includes('<session-keyword>'));
})
// 3. 對每個 session URL navigate + 擷取：title、time、location、講者姓名 + 職稱 + 公司、abstract、track、level
```

**Fallback — curl + 手動擷取**（Playwright 沒掛時）：

```bash
curl -s -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15" \
  "<session-url>" -o /tmp/session.html
# 用 grep / sed parse 渲染後的文字部分
```

**官方校正套用到：**

1. 每場 session 的 `.md` frontmatter（加 `> 大會 session: <url>` 行 + 標註投影片自報 vs 官方的差異）
2. 既有的 `session_schedule.md` 表格（修正講者姓名、加 session URL link）— 見後面 optional Step C

**CRITICAL INVARIANT**：當官方頁與投影片/逐字稿在**識別 fact**（姓名、職稱、公司）有出入時，**官方為準**用於所有 derivative 文件。差異記在每場 `.md` frontmatter 留 traceability — 但**不要**「校正」逐字稿主體（逐字稿是「講者實際說了什麼」的紀錄）。

## Step A5：在每場 markdown 標 Whisper hallucination

mlx_whisper large-v3-turbo 對中文大會音訊有已知失效模式。掃 SRT 找下列 pattern 並標註：

| Pattern | 範例 | 處置 |
|---|---|---|
| 單行重複迴圈（≥10 次） | `"那邊"` × 33 | 改寫 note：「（Whisper 此處連續輸出 'X' 約 N 次，疑為 transition word 誤判，原話無法重建）」 |
| 長尾 hallucination（最後 N 分鐘失蹤） | 最後 14 分鐘 = 單一 phrase loop | frontmatter 加 `⚠ 重大警示` block + slide 20+ 改純投影片重建 |
| 英文專有名詞 → 中文音譯 | Claude → 龍蝦、Anthropic → 種種、CLAUDE.md → Cloud.md | inline 校正：`龍蝦 [Claude]` |
| 品牌 / 產品音譯 | DeepSeek → 深度求索（對）、Cloudflare → Codefit（錯） | 用 context inline 校正 |
| 講者自介錯字 | 職稱 / 公司名 | Step A4 大會官方頁交叉比對；frontmatter 校正 |

每場 `.md` 末尾加 `**附錄**` 段列：
- 投影片張數（含 IMG 編號 range，list 任何 gap）
- 錄音長度（從 SRT 末尾時間戳）
- 講者
- 缺漏段落（list 任何重建 gap）
- Whisper hallucination 警訊清單（具體時間戳 + 問題性質）

---

# Phase B — 報告（互動式）

**Phase B 不會在 Phase A 之後自動跑。** User 明確要求要報告時才動，動之前先跑需求 quiz。

## Step B1：需求 quiz（寫前 MANDATORY）

寫報告前一律先用單則訊息一次問完下列 4 件事（編號列）— 別一條一條 quiz user：

```
我要寫報告之前先確認 4 件事，請逐項回覆（不確定可說「沒想法」我會給推薦）：

1. **範圍**：要寫哪幾場？
   - (a) 單場 — 哪一場？
   - (b) 單日整合 — 哪一天？
   - (c) 多日匯總 — 哪幾天？整會議？

2. **既定格式**：
   - (a) 有 template / sample，請貼上 / 給檔案路徑
   - (b) 沒有，由我建議格式（會依範圍給 sane default）

3. **受眾**：
   - (a) HR / 上級主管（送公司外訓報告 → 正式書面）
   - (b) 內部團隊 / wiki（半正式，含技術細節）
   - (c) 個人筆記 / 私存（隨意）

4. **業務 mapping**：要不要把每場連到公司 workstream / ticket / 專案？
   - 要 → 列出對應主軸（例：「Auth 改版 + 第三方 API 整合 / Ticket #123 + #456」這類抽象描述，請避免具體客戶名 / 產品碼）
   - 不要 → 純技術內容，不對應內部 context
```

等 user 回。**4 個維度全回了**（或 user 明說「用 default」）才動筆。

## Step B2：依 quiz 答案選 template

Quiz 完根據答案推導報告形狀：

| 範圍 | 既定 template? | 受眾 | 用什麼 |
|---|---|---|---|
| 單場 | 有 | * | 套 user 給的 template |
| 單場 | 沒 | 任一 | **Default A** — 單場深度 takeaway 結構 |
| 單日 | 有 | * | 套 user 給的 template |
| 單日 | 沒 | HR / 主管 | **Default B** — 7 段式正式外訓報告 |
| 單日 | 沒 | 團隊 / wiki | **Default C** — 簡化 4 段（議程 / 重點 / 應用 / 附件） |
| 單日 | 沒 | 個人 | **Default D** — bullet list 純技術 takeaway |
| 多日 | 有 | * | 套 user 給的 template |
| 多日 | 沒 | HR / 主管 | **Default E** — 跨日匯總 + 趨勢分析 + 整體應用建議 |
| 多日 | 沒 | 團隊 / wiki | **Default F** — 主題彙整（cross-cut themes 而非 chronological）|
| 多日 | 沒 | 個人 | **Default G** — bullet list 跨日技術 takeaway |

Templates A-G 在下方。

### Default A — 單場深度 takeaway

```markdown
# <Session 標題> — 場次筆記
**講者**：<官方姓名 / 職稱 / 公司>
**場次**：<日期 HH:MM-HH:MM @ 地點>
**主題**：<官方主題>
**Source**：<per-session .md 檔路徑>

## 核心論點
<2-4 句精煉>

## 重點 takeaway
1. ...
2. ...
3. ...

## 適用建議
<若有 mapping 才寫；無則略>
```

### Default B — 7 段式正式外訓報告（單日 + HR/主管）

```markdown
# 外訓報告 — <Conference> <Day>

## 一、基本資訊
| 項目 | 內容 | ... |

## 二、訓練目的
<業務 mapping，無 mapping 則改寫成「產業趨勢更新」>

## 三、議程摘要
<表格：時段 / 議程標題 / 講者（官方）>

---

## 四、議程內容與重點摘要
> **資料來源原則**：講者身份、職稱、議程主題、場地等識別資訊以**大會官方議程頁**為準；演講內容以**現場錄音逐字稿 + 投影片重建**為來源。

### Session 1 — <title>（<speaker>）
**核心論點**：<2-4 句>
<然後表格 / bullet>

### Session 2 — ...

---

## 五、重點收穫
<5-7 條跨場主軸>

## 六、對公司業務的應用建議
<僅在有 business mapping 時生；無則改成「產業趨勢應用方向」泛論>
### 短期 / 中期 / 長期 三層

## 七、附件
- 三場議程之逐字稿與投影片重建：<links>
- 大會官方 session 連結
- 外部參考資料

**報告人**：<name>
**報告日期**：YYYY-MM-DD
```

### Default C — 簡化 4 段（單日 + 團隊/wiki）

```markdown
# <Conference> <Day> — 場次重點

## 議程
<表格>

## 重點 takeaway
<5-10 條跨場 bullet>

## 公司應用建議
<若有 mapping 才寫>

## 附件
<逐字稿 link + 大會官方 link>
```

### Default D — 個人筆記（單日 + 個人）

```markdown
# <Conference> <Day> 筆記
- <key takeaway 1>
- <key takeaway 2>
...

## Sessions
- [<HH:MM> <title>](<per-session .md>)
- ...
```

### Default E — 跨日匯總 + 趨勢分析（多日 + HR/主管）

```markdown
# <Conference> 整會議外訓報告

## 一、基本資訊
<整會議資訊：N 天、總場次、合計時數>

## 二、訓練目的
<業務 mapping>

## 三、出席議程總覽
<表格：分日列出，每場一行，含 link>

---

## 四、跨日主題分析
> 不依時間 chronological，依 theme 切

### Theme 1 — <e.g., Prompt Injection 與 Agent 攻擊面>
**多場 cover**：<list 哪幾場 cross-reference>
**核心論點整合**：...
**框架 / 工具歸納**：...

### Theme 2 — ...
### Theme 3 — ...

---

## 五、重點收穫
<跨日整體 takeaway 5-10 條>

## 六、對公司業務的整體應用建議
### 短期 / 中期 / 長期 三層

## 七、附件
<分日列出 per-session links + 大會官方 links>
```

### Default F — 主題彙整（多日 + 團隊/wiki）

跨日主題彙整版本，比 E 簡化（無 §一/§二/§六/§七 ceremony，主軸是 §四 主題分析）。

### Default G — 個人匯總筆記（多日 + 個人）

跨日 bullet 格式，純 takeaway + session list。

## Step B3：套用 project 寫作紀律

工作 repo 的 `CLAUDE.md` 或 `docs/claude_rules/` 若定義 tone / 用詞規則，套用到報告：

- **中性用詞紀律** — git-bound docs 避用 屎山 / 雷 / 投機 等情緒詞
- **公開化 contract** — 若 user 說「上 ADO wiki」或「公開化」，套對應 contract（無個人 attribution / 無日期 marker / 無內部組織 reference）
- **業務 mapping 紀律** — 用 ticket 編號或抽象描述，不寫客戶名

每場 `.md`（Phase A 產出）是 internal memo style — **不**對它套公開化 rule。Phase B 報告則依受眾決定。

## Step B4：草擬、交付、迭代

依 quiz + template 寫報告。一律：
- 識別 fact（姓名 / 職稱 / 場次）用大會官方
- 演講內容從每場 `.md` 拉
- 講者 forward-looking 主張標「（待官方確認）」caveat
- 在附件 / source 段引用每場 `.md` 檔路徑

把草稿給 user 看；預期會有 wording / scope / 深度的迭代。

---

# Step C（optional）— 更新 session_schedule.md（如果存在）

如果 `drafts/<conf>/session_schedule.md` 在出差前就有規劃版：

1. **標記實際出席的場次** vs 原規劃（沒去的 row 砍掉）
2. Day header 從「規劃 N 場」改成「實際出席 M 場」
3. 每場出席的 session 在 Session 欄補 📝 逐字稿 link + 🌐 大會 session link
4. 更新 `今日場次` tally 行
5. 更新底部 summary 表（只動已出席日的 row）

**Session row 格式範例：**
```
| 14:45-15:15 | **<title>**<br>📝 [逐字稿 D1_1445-1515](D1_1445-1515.md) ｜ [大會 session](<官方 url>) | <講者> / <地點> | <主軸對應> |
```

如果沒有 `session_schedule.md`，**整個 step 跳過**。不要無中生有。

---

## 決策框架

### NotebookLM vs 本 pipeline 選擇

| 目標 | 工具 |
|---|---|
| 一場 session 的 audio overview / podcast / 心智圖 | NotebookLM（快、prose 流暢） |
| 忠實逐張投影片重建 + 時間戳 + 視覺細節 | 本 pipeline（HEIC 多模態 + Whisper SRT） |
| 多場交叉引用的報告 | 本 pipeline |
| 個人隨手筆記 | NotebookLM |

NotebookLM 把逐字稿磨平流暢的代價是失去投影片視覺細節 + 時間戳精確度。本 pipeline 兩個都保。**送 HR / 主管的報告，一律用本 pipeline。**

### Whisper 校正積極程度

| 確信度 | 動作 |
|---|---|
| 100% 確定（英文品牌音譯誤識、公知專有名詞） | inline 直接改不加 bracket：`Claude` |
| 強推斷（context 可消歧） | inline bracket 校正：`龍蝦 [Claude]` |
| 弱推斷（多種可能） | bracket 加問號：`它 [它? / 然後?]` |
| 無法還原（hallucination 迴圈） | 改 note，不要猜 |

## Anti-patterns

- ❌ **Step B1 quiz 跑前不要動筆寫報告** — 範圍/格式/受眾/mapping 跟你猜的不一樣等於白工
- ❌ **不要假設「外訓報告」的 semantics** — user 真實需求可能是一頁個人筆記或多日主題匯整；先問
- ❌ **不要 Phase A + Phase B 一氣呵成沒 quiz** — Phase A 跑法都一樣，Phase B 是 per-user-decision
- ❌ **Step A4 交叉比對前不要先寫報告** — 名字會錯，後續所有 derivative 都要回頭改
- ❌ **不要把 Whisper 衍生輸出（.json/.tsv/.txt/.vtt）丟到 raw/** — 只留 .srt + .m4a；其他是噪音
- ❌ **不要 commit `raw/` 進 git** — m4a + HEIC 是本機 only；確認 `raw/` 在 project 的 `.gitignore` 內
- ❌ **不要把逐字稿 prose 磨順讓它讀起來舒服** — 保留講者實際語氣含贅字；本 pipeline 的價值就是忠實
- ❌ **不要把講者口頭 forward-looking 主張當 fact** — 講者說「我之後會在 X 大會發表 framework Y」要在報告標 講者口述 + 加 「(待官方確認)」caveat
- ❌ **不要過度引用講者多重身份** — 官方議程只掛「OWASP Chapter Leader」但投影片自報 5 個職位包含「Founder & CEO of X」，**defer 官方 minimal 版**；差異只記在每場 `.md` frontmatter
- ❌ **不要把 user 沒實際出席的 keynote 列進報告** — 列前先確認出席
- ❌ **不要為了「看起來乾淨」手動編逐字稿主體的 Whisper bracket** — 那些 bracket 是 audit trail；清理發生在報告（derivative），不是逐字稿（source）
- ❌ **不要省略每場 `.md` 附錄裡的 Whisper hallucination 警訊清單** — 未來用更好模型重轉錄需要知道哪段不可靠
- ❌ **沒 session_schedule.md 不要主動建** — 那檔案是某些 user 的規劃 workflow，不是普世 artifact

## Important rules

1. **兩階段、兩個 mindset。** Phase A 是 deterministic 工程；Phase B 是 interactive deliverable shaping。別混為一談
2. **Quiz 完才動筆。** Phase B 一律從 4 維度 quiz 開始。7 段式 default 是 7 種可能 template 之一，**不是 THE template**
3. **大會官方議程是識別 fact 的 canonical source。** 投影片與逐字稿是內容的 canonical。識別 fact（姓名/職稱/地點）有衝突時，defer 官方；註記差異
4. **保留 audit trail。** 每場 `.md` 留 Whisper bracket 校正 + 附錄警訊。不要 sanitize
5. **Raw 留本機。** `raw/` gitignored；m4a / HEIC 永不進 git。文字 deliverable（每場 `.md` + 報告）才是 git 內容物
6. **講者 forward-looking 主張需 caveat。** 講者預告未公開的 framework / paper / event，標 講者口述，建議 user 在正式引用前 verify
7. **套用 project 寫作紀律。** 工作 repo 的 `CLAUDE.md` 或 `docs/claude_rules/` 若定義 tone / 用詞規則（中性用詞 / 公開化 contract 等），套用到報告。每場 `.md` 是內部 memo style — 不要對它套公開化 rule
8. **可復用是 feature。** 此 skill 多日大會的 Phase A 每天跑一次。Phase B 可能每場跑一次、每天跑一次、或整會議跑一次，看 user 選的 scope。每個輸出獨立檔（無 `_v2` suffix、跨日無 in-place mutation）
