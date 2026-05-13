# md2ppt — 為什麼不做 generic markdown→pptx 自動轉換

> **English summary:** Design doc for md2ppt, an interactive pptx builder that drives a per-slide layout dialogue and emits a hand-coded build script. Built on python-pptx + mmdc, with optional LibreOffice headless for self-check. Generic markdown→pptx auto-converters (Marp, pandoc) produce slides that are syntactically correct but visually unbalanced — slide layout decisions need content meaning, not just markdown structure. Brand-template integration was prototyped as a prescribed workflow in v0.2, then pulled back to ad-hoc helper primitives in v0.4 after testing on a real template took 5 rounds of debugging to find the right layout names.

## 這東西為什麼存在

把 markdown 報告轉 pptx 簡報這件事,聽起來簡單。

```bash
# 你以為可以這樣
pandoc report.md -o deck.pptx
marp report.md --pptx
```

是會出來,但**長得很醜**:

- 一張 slide 一個 H2,但 H2 內容多寡天差地遠 — 短的擠在頂端剩白,長的爆出 slide
- Table 全用 default 等寬欄位,`#` 那欄佔三分之一,內容欄被擠扁
- Mermaid 渲染進去當 image,但常常太大或太小,沒對齊
- ASCII art code block 用比例字體 render,排版整個垮掉
- 字型 default 那種一看就「不像簡報」

**問題不在工具不夠強,在 layout 是 design decision 不是 syntactic transform**。一張 markdown table 4 row 是一張 slide;同樣 table 12 row 該拆兩 slide;30 row 該丟附錄。Bullet list 4 條一張 slide,14 條該分主題拆 3 張。Generic parser 不知道哪一條是「重點 punchline」哪一條是「補充 caveat」,所以視覺權重都一樣。

## 設計思路

### 互動式對話取代 generic parser

skill 跑流程:

```
1. Pre-analyze input.md(統計 H2/H3/table/code block/bullet)
2. Quiz user (5 題:slide grouping / style / cover / diagram strategy / per-slide granularity)
3. (optional) per-slide walk-through(逐張 layout 提案)
4. 寫 hand-coded build script(每張 slide 一段 # ====== Slide N ====== + helper calls)
5. Render pptx
6. (optional) self-check via LibreOffice → 看 PNG 找跑版
7. User manual review → iterate per-slide patch
```

LLM 取代了 generic parser 的 hard-coded heuristic — 跟 user 對話 5 分鐘,得到的 quality 接近完全 hand-code,但 user 不用會 python-pptx。

### 為什麼是 python-pptx 不是 Marp / pandoc

| | Marp | pandoc | python-pptx (我們) |
|---|---|---|---|
| 主要輸出 | HTML / PDF | 各種 doc 格式 | 直接 pptx |
| pptx 質感 | 普通(theme engine 受限)| 粗糙(忽略多數 layout intent)| 完全自控 |
| 互動性 | 寫死在 markdown | 寫死在 markdown | 跟 user 對話決策 |
| Mermaid | plugin support | lua filter | mmdc 渲染 PNG 嵌入 |
| Iterate cost | 改 .md re-export | 改 .md re-export | 改 .py re-render(同樣快)|

關鍵點:**python-pptx 給的是 primitive,不是 template**。我們可以決定「這張 slide 標題 30pt 深藍 + 底下放 12 inch 寬 table + 配 5 條 14pt bullet」,沒 theme engine 限制。

### Mermaid PNG vs ASCII monospace 怎麼選

Mermaid 渲染 PNG 不是萬能解,大多數 case 用 ASCII 還更可讀:

| 圖類型 | 推薦 |
|---|---|
| Sequence diagram | mermaid PNG(時序視覺化 > ASCII)|
| 線性 flowchart ≤ 5 nodes | ASCII OK(monospace 對齊讀得清楚)|
| 線性 flowchart > 5 nodes 且 LR layout | mermaid PNG |
| 嵌套 / 階層 box | mermaid PNG(ASCII 嵌套對齊很煩)|
| 狀態機 | mermaid PNG |
| Directory tree | ASCII(tree 是 monospace native)|
| 單純箭頭鏈 `A → B → C` | ASCII inline(整段 textbox 不需要圖)|

skill 在 Step 2 Q4 quiz user 全 mermaid / 全 ASCII / mixed / 個別決定,根據 case 來。

## Build script 是 source of truth

每份 deck 對應一份 `build_<topic>.py`,大概 200-400 行。**這個 .py 是 deck 真正的 source code,.pptx 是 build 出來的 binary**:

- 數據要更新(typo / 新數字)→ 改 .py 一行 → re-run 5 秒
- 加一張新 slide → 加一段 `# ====== Slide N ======` block → re-run
- 換配色 → 改 style 常數 → re-run

不維護 build script,只留 .pptx 的 cost:下次小改要在 PowerPoint 手改,容易跑版,失去原本對齊的 layout。

build script 跟 input.md + `_assets/*.png` cache 一起放專案的 `drafts/ppt/`(慣例)。.pptx 出貨後存 `deliverables/`。

## Style preset 為什麼選 corporate_blue 為 default

簡報 95% 場景是內部 review / 主管簡報 / stakeholder 對齊,所以 default 走「保守商務風」:

- **深藍 (`#1F3A5F`)** 標題 — 不會太刺眼也夠 contrast
- **PingFang TC** 中文字型 — macOS native,字重對比清楚
- **Menlo** monospace — code / ASCII art 用
- **紅色 (`#C0392B`)** 強調 — 重點 / warning
- **綠色 (`#27AE60`)** OK / positive
- **灰 (`#7F8C8D`)** 副標 / muted text
- **藍 (`#3498DB`)** 中性 bar / 次要強調

完全不用 emoji。簡報投影出來 ❌ ✅ 🔴 ⚠️ 看起來很業餘 — 用顏色或文字 label("受影響" vs "不受影響")替代。

## brand mode 試過又退掉(v0.4.0 故事)

v0.2.0 加了「brand mode」prescribed workflow:user 提供公版 .pptx,skill 兩階段產出 content 版 + branded 版,自動 mapping cover / section / Q&A 到 template layout。聽起來合理。

實測下來 5 個 round:

```
Round 1: helper 加白底 rectangle 蓋住 template logo → 修
Round 2: cover 用「標題投影片」layout,結果 user 說公版第 1 頁不是這個 style → 改用「章節標題」
Round 3: content slide 用「標題投影片」layout,placeholder default 「按一下以新增標題」跑出來疊在我們手刻 textbox 上 → user catch,改用「空白」layout
Round 4: 「空白」layout 在 helper 內被白底 rect 蓋住沒 chrome → 跟 round 1 同 root cause,加 clear_placeholders
Round 5: user 說 page 2-12 應該套公版 page 7,結果發現 page 7 用「標題投影片」(剛剛踩過的)→ 真正 content 頁是 page 8 用「空白」
```

每個 template 的 layout 命名 / chrome 設計 / placeholder 結構完全不同。**沒辦法寫出 generic「cover_layout / content_layout」抽象**,每次都要 user 跟 LLM 一起 inspect template 才能決定。所謂 brand mode 不過是把這個 dialogue 包成假 workflow。

v0.4.0 退回 ad-hoc:helpers 還在(`init_deck_from_template` / `add_blank_from_template` / `add_cover_from_template` / `list_template_layouts`),user 要套公版時跟 LLM 對話走 helper。SKILL.md 寫了一段「Brand template (ad-hoc, optional)」列踩過的坑(白底 / placeholder / env var)。

教訓:**有些 workflow 不該變成 prescribed,變成抽象反而把問題推到難處理的時機才爆**。

## Self-check loop:LibreOffice headless

Step 6.5 optional,如果有裝 `soffice`(macOS:`brew install --cask libreoffice`),把 .pptx render 成 PDF → 切 PNG 一張一張看,8 種 visual issue pattern grep:

| Issue | Visual signal | Fix |
|---|---|---|
| Text 跑出 slide | 邊緣截斷 | 縮字 / 拆 slide |
| 字太小 | 看不清 | bump `size=` |
| Emoji 出現 | ❌ ✅ 等 | grep + replace |
| Table 欄寬怪 | 一欄擠一欄空 | 設 `col_widths=` |
| 圖跑版 | 超出邊界 / 變形 | `add_picture_fit` 加 max_height |
| 下方留白多 | 30%+ 空 | `vertical_center_in` 或補內容 |
| placeholder 疊到 | 兩個 title 重疊 | 換 layout / 清 placeholder |
| Chrome 被蓋 | logo 不見 | 移除全 slide 白底 rect |

Max 3 次 retry auto-fix,搞不定再交還 user manual review。沒裝 soffice 就 silent skip,純人工 review 也 OK。

self-check 不是 authoritative — LibreOffice 跟 PowerPoint / Keynote render 不完全一致,字體 / chrome 可能略差。它只是 first-pass filter,user 視覺 review 仍是最後 gate。

## 已知 anti-patterns

幾個踩過或看別人踩過的:

- ❌ Generic markdown loop — 每張 slide 都長一樣,不平衡
- ❌ 跳過 Step 2 quiz 直接寫 build script — 設計決策沒鎖,user 反饋會反覆改
- ❌ Slide 內 emoji — 投影機看醜,改用顏色 / text label
- ❌ ASCII art > 20 行 — 投影看不清,改 mermaid 或拆 slide
- ❌ markdown frontmatter 滲進 deck — frontmatter 是 meta 不是 content
- ❌ `add_picture(width=N)` 沒帶 height → 縱向圖爆出 slide bottom
- ❌ Table 不設 `col_widths=` → default 等寬經常很醜
- ❌ 把 template 既有 slide 留在 branded build script — strip 掉只留 theme/masters

## File structure

```
md2ppt/
├── SKILL.md                            主 workflow + decision frameworks + anti-patterns
├── scripts/
│   ├── pptx_helpers.py                 全部 helpers + 配色常數
│   ├── render_mermaid.sh               mmdc wrapper + content-hash cache
│   └── md_analyze.py                   Step 1 pre-analyze
├── docs/
│   └── DESIGN.md                       本檔
└── examples/
    ├── build_quarterly_review.py          reference build script (default flow)
    └── build_quarterly_review_branded.py  reference build script (ad-hoc brand)
```

## 限制 / 未來

- 字型 fallback 假設 PingFang TC(macOS),其他 OS 開的 deck 字型可能跑掉
- LibreOffice render 跟真實 PowerPoint 視覺有差異,self-check 不是萬能
- 還沒做的:speaker notes / 多語言版本 / outline-only mode / 自動 theme-aware 字型 fallback
- v0.5 可能加:把 design decisions 存進 `~/.cache/md2ppt/<input-hash>.json`,re-run 同 input.md 時可以「沿用上次決策」跳過 quiz
