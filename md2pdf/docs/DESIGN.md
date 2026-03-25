# md2pdf -- Design Document

> **English summary:** A Claude Code skill that converts Markdown files to publication-ready A4 PDFs, with automatic ASCII-art-to-Mermaid conversion, CJK font handling, and a self-check loop that reads its own output and fixes rendering issues. Born from a real session where a "simple PDF export" turned into a 2-hour debugging marathon across SVG font failures, Mermaid syntax traps, and weasyprint's creative interpretation of Chinese characters. This document covers the motivation, technical gaps, design decisions, and the battle scars that shaped every rule in the pipeline.

---

# 設計文件

## 這個 Skill 的誕生故事

一切始於一句看似無害的話：「把這份 Markdown 轉成 PDF，要給廠商看。」

聽起來很簡單對吧？Markdown 轉 PDF，2024 年了，應該跟呼吸一樣自然。結果我們花了整整一個對話的時間，來回除錯，才搞定一份看起來正常的 PDF。不是因為工具不夠多 — pandoc、weasyprint、mermaid-cli 都在手邊 — 而是因為這些工具的組合拳，每一拳都往意想不到的地方打。

所以我們決定把這些血淚經驗封裝成一個 skill，讓下次（以及每一次）不用再重新踩一遍。

---

## 技術缺口：為什麼現有工具不夠

### 問題一：Mermaid + PDF = 字型地獄

pandoc 可以透過 lua filter 呼叫 `mmdc` 把 Mermaid 渲染成圖片嵌入 PDF。聽起來很美好。

但如果你用 SVG 輸出，weasyprint 渲染時會嘗試用系統字型來顯示 SVG 裡的文字。問題是 Mermaid 的 SVG 會引用它自己的字型（通常是 sans-serif），而 weasyprint 找不到對應的字型，結果就是：**方框都在，文字全消失**。

你盯著一份只有框線沒有字的流程圖，會開始懷疑人生。

> 解法：一律用 PNG 輸出，scale 3x 確保解析度。文字直接烤進圖片裡，不再依賴字型渲染。粗暴但有效。

### 問題二：CJK 在 Code Block 裡變問號

weasyprint 對 `<pre>` 和 `<code>` 預設使用 monospace 字型。macOS 的 monospace 字型（Menlo、Courier）不包含中日韓字元。所以你會看到 `http://{???IP}:8080` 這種鬼東西。

更刺激的是，pandoc 的語法高亮會把程式碼包在 `<span>` 裡面，每個 span 可能用不同的 CSS class，而這些 class 的字型設定又不一定繼承父元素。於是 JSON 裡的 `{`、`}`、`:` 和數字全部變成方框。

> 解法：關閉語法高亮（`--no-highlight`），然後在 CSS 裡對 `pre`、`code` 顯式指定 `"Menlo", "Heiti TC", "Arial Unicode MS", monospace` 的 fallback chain。Menlo 負責英文字元，Heiti TC 接住中文。

### 問題三：Mermaid 的 Markdown 解析陷阱

Mermaid 的節點文字支援 Markdown 語法 — 這聽起來是個功能，實際上是個坑。

- 節點裡寫 `"1. 客戶提供測試集"` → Mermaid 把 `1.` 解析成 ordered list → 渲染出 "Unsupported markdown: list"
- 節點裡寫 `\n` 換行 → 某些渲染器會原封不動地把 `\n` 當文字印出來
- 全形括號 `（）`、特殊符號 `≥` → 可能觸發解析錯誤

> 解法：`\n` 一律改 `<br/>`。節點文字移除數字編號開頭。特殊符號用 ASCII 替代或移除。

### 問題四：圖太高，PDF 跑版

一個 7 層垂直的 ResNet 架構圖，渲染成 PNG 後高度超過 A4 頁面。weasyprint 的做法是：把圖片推到下一頁，前一頁留白。然後圖片還是超出邊界被裁切。

> 解法：CSS 加上 `img { max-height: 700px; }`。Mermaid 圖如果太高就改成橫向（LR）佈局。自檢時偵測空白頁，觸發自動修正。

---

## 競品分析（又名「一定有人做過了吧？」）

做之前我們先查了一輪。Markdown 轉 PDF，2026 年了，應該有成熟方案。結果發現大家都做了一部分，但沒有人把 CJK + Mermaid + 自動修正這條路走完。

### 現有方案一覽

| 工具 | 它做什麼 | 它不做什麼 |
|------|---------|-----------|
| **pandoc + LaTeX** | 業界黃金標準。排版精美，學術論文首選。 | macOS 裝 LaTeX 要下載 3-4 GB。CJK 需要額外設定 XeLaTeX + 字型。門檻高到讓人想放棄人生。 |
| **md-to-pdf (npm)** | 用 Puppeteer 渲染，CSS 驅動，裝起來簡單。 | 不處理 Mermaid code block。你的流程圖會變成一坨原始碼躺在 PDF 裡。 |
| **Typora Export** | GUI 一鍵匯出，所見即所得，Mermaid 原生支援。 | GUI 工具。你不能在 terminal 裡自動化它。AI agent 更不可能幫你按按鈕。 |
| **VS Code Markdown PDF** | VS Code 套件，右鍵就能轉。方便。 | 同上，IDE 套件不能 CLI 化。而且 CJK 字型問題一樣存在。 |
| **Marp** | 把 Markdown 變成簡報 PDF。如果你要的是投影片，它很強。 | 它做的是簡報，不是文件。A4 多頁技術文件不是它的主場。 |
| **grip + wkhtmltopdf** | 用 GitHub API 渲染 Markdown，然後轉 PDF。 | 需要網路連線呼叫 GitHub API。Mermaid 不渲染。wkhtmltopdf 已經停止維護了。 |

### 沒人填補的缺口

我們注意到一個有趣的現象：**能處理 Mermaid 的工具不支援 CLI，能 CLI 的工具不處理 Mermaid，能處理 Mermaid 又能 CLI 的不處理 CJK。**

然後更關鍵的是 -- **沒有人做自動修正。**

所有工具都是「轉完就丟給你」。SVG 文字消失？你的問題。圖太大跑版？你的問題。code block 裡中文變問號？你的問題。

我們想要的是：轉完之後自己看一遍，壞了就自己修。不要讓使用者當 QA。

這就是這個 skill 的切入點 -- 不是做一個更好的轉換器，而是做一個**會自我檢查的轉換流程**。

---

## 設計決策

### 決策一：不動原檔

原始 Markdown 裡的 ASCII art 是作者的心血。有些人就是喜歡用 `┌─┐` 和 `──►` 畫圖，而且在 terminal、GitHub preview、HackMD 上看起來都好好的。

所以我們複製一份 `_pdf.md` 來改，原檔一個字都不動。

如果下次執行時發現 `_pdf.md` 已經存在，會詢問使用者：「要直接用上次的版本轉？還是從原檔重新產？」 — 因為使用者可能已經手動微調過 `_pdf.md`，直接覆蓋就太不尊重人了。

### 決策二：ASCII Art 辨識而非全部轉換

不是所有 code block 裡的東西都該變成 Mermaid。目錄樹（`├── src/`）就該是目錄樹。

辨識規則：
- 有箭頭（`→ ► ▼ ──►`）+ 方框（`┌ ┐ └ ┘`）→ 大概率是流程圖 → 轉 Mermaid
- `├──` `└──` + 檔名路徑 → 目錄樹 → 保留
- 已經是 ` ```mermaid ` → 不動
- 不確定 → 保留，寧可不轉也不要轉壞

### 決策三：自檢但設上限

PDF 產出後會自動讀取每一頁，檢查：
- 幾乎空白的頁面（圖被推到下頁）
- Mermaid 渲染失敗文字（"Unsupported markdown"）
- 圖片超出頁面邊界

發現問題就修 `_pdf.md` 然後重新產。但最多重試 **3 次**。實測證明 2 次不夠 -- 有時候第一次修錯方向，第二次修對方向但不完整，第三次才真正解決。但 3 次之後如果還是壞的，問題大概率需要人類判斷，繼續重試也只是浪費時間。

### 決策四：風格可選但有預設

執行時會列出幾種 CSS 風格讓使用者選。不選的話就自動決定一個合適的。

因為「給客戶看的規格書」和「給工程師看的技術手冊」，排版需求天差地別。但如果使用者只是想快速轉個 PDF，不應該被迫思考 CSS。

### 決策五：依賴先檢查

執行前先確認 `pandoc`、`mmdc`、`weasyprint` 都存在。缺少就報錯 + 給安裝指令，不要跑到一半才炸。

因為 pandoc 跑到一半發現沒有 weasyprint 的那個錯誤訊息，不是每個人都看得懂的。

---

## 完整流程

```
原始 file.md（不動）
      │
      ├── 複製 → file_pdf.md
      │
      ▼
ASCII art 辨識 + 轉 Mermaid
      │
      ▼
Mermaid 語法清理
（\n→<br/>, 移除 list 語法, 特殊符號處理）
      │
      ▼
產生暫存 lua filter + CSS
      │
      ▼
pandoc + weasyprint → PDF
      │
      ▼
自檢（逐頁讀取）
      │
      ├── OK → 清理暫存檔 → 完成
      └── 有問題 → 修正 → 重新產（最多 3 次）
              └── 仍有問題 → 停止，告知使用者
```

---

## 技術棧

| 工具 | 用途 | 為什麼選它 |
|------|------|----------|
| pandoc | Markdown → HTML → PDF 的管線 | 業界標準，lua filter 擴展性強 |
| weasyprint | HTML → PDF 引擎 | 不需要 LaTeX，CSS 驅動，macOS 友善 |
| mmdc (mermaid-cli) | Mermaid → PNG | 官方 CLI，支援 CJK |
| lua filter | pandoc 擴展 | 在轉換過程中攔截 mermaid code block，呼叫 mmdc |

### 為什麼不用 LaTeX？

因為 macOS 上裝 LaTeX 要下載 3-4 GB 的東西，而且中文排版需要額外設定 XeLaTeX + CJK 字型。weasyprint 用 CSS 就能搞定，裝起來只要 `pip install weasyprint`。

取捨很明確：LaTeX 排版更精緻，但 weasyprint 夠用且門檻極低。我們要的是「快速產出可交付的 PDF」，不是「排一本書」。

---

## 實測結果

我們拿了一份真實的產品規格書（一對一聊天紅包發送功能，506 行 Markdown）來跑第一次端到端測試。這份文件什麼都有：4 個 Mermaid 圖、5 個 ASCII UI 線框稿、大量 CJK 表格、JSON code block 含中文註解。

### 第一次產出

大部分都正常 -- Mermaid 圖渲染正確、ASCII 線框稿保留、CJK 字型沒問題。但 3.3 業務規則表格爆了：9 行全部擠成一個 cell。

### 診斷過程

一開始以為是表格內的 `**bold**` 語法干擾了 pandoc 解析。移除 bold，沒用。

接著懷疑是 `$5,000` 的 `$` 符號。轉義了 `$5,000` → `\$5,000`，還是沒用。

最後用 `pandoc -t html` 看中間產物，發現真正的兇手：pandoc 把 `NT$1 ～ NT$5,000` 裡的兩個 `$` 配對成 LaTeX inline math，中間所有的 `|`（表格分隔符）都被吃掉了。`$1 ～ NT$` 變成一個 math span，後面 7 行的表格結構全部崩潰。

解法：轉義所有 `$` → `\$`。

### 最終結果

15 頁 PDF，1.3 MB。所有內容正確渲染，無跑版、無裁切、無字型問題。

### 學到的教訓

1. **永遠先看 HTML 中間產物**。PDF 出問題時，先 `pandoc -t html` 確認是 pandoc 解析問題還是 weasyprint 渲染問題。這次如果一開始就看 HTML，可以省掉一次無效的 retry。
2. **`$` 是隱形殺手**。在含有貨幣符號的技術文件中（`NT$`、`US$`），pandoc 的 LaTeX math 解析會默默地吞掉表格結構。這不是 bug，是 feature（pandoc 的角度），但對我們來說就是坑。
3. **2 次 retry 不夠**。這次實際用了 3 次才修好。第一次修錯方向（移除 bold），第二次修對方向但不完整（只轉義了一個 `$`），第三次才全部轉義成功。所以 retry 上限從 2 調整為 3。

---

## 這份文件為什麼存在

因為下一個碰到「Markdown 轉 PDF 怎麼這麼多坑」的人，不應該要重新踩一遍。

每個決策背後都有一個「我們試過了，壞掉了，然後學到了」的故事。把這些故事記下來，就是設計文件存在的意義。

不然你以為 `--no-highlight` 和 `"Menlo", "Heiti TC"` 這種詭異的 CSS 組合是怎麼來的？不是靈感，是絕望。
