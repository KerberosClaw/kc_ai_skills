# repo-scan -- 設計文件

> **English summary:** Design document for the `repo-scan` skill — a security scanning tool for evaluating GitHub repos before installation. Covers motivation, competitive landscape analysis (Anthropic's built-in /security-review, Trail of Bits skills, commercial AI-native SAST), the gap we identified (nobody scans Issues, nobody does full-repo audit from a URL), and key design decisions including why we scan GitHub Issues, why we assess maintainer health, and why the output is an opinion rather than a data dump.

---

## 這個 Skill 為什麼存在

我們活在 AI 開源工具的黃金時代。每週都有一個閃亮的新 GitHub repo 號稱會改變你的工作流程。你按了 star，clone 下來，`npm install`，然後祈禱不會出事。

劇透：有時候真的會出事。

現實是 -- 大多數開發者（包括我們自己）評估開源工具的方式是：掃一眼 README、看看 star 數、也許花 30 秒瞄一下程式碼。這不是盡職調查，這是擲硬幣但多了幾個步驟。

我們想要一個 skill，能幫我們做那些我們懶得手動做的事：真的讀完程式碼、檢查依賴、翻一下 issues、然後告訴我們「欸，這個你可能不要裝比較好。」

---

## 競品分析（又名「一定有人做過了吧？」）

動手寫之前，我們先查了一輪。結果發現很多人在做這塊，只是沒有一個完全符合我們的需求。

### 現有方案一覽

| 工具 | 它做什麼 | 它不做什麼 |
|------|---------|-----------|
| **Anthropic /security-review**（內建）| 掃你的 PR diff 找弱點。MIT license，隨 Claude Code 出貨。 | 只掃*你的*分支上*你的*修改。不能丟一個 GitHub URL 給它說「幫我看看這安不安全」。 |
| **Trail of Bits /skills**（3,875 stars）| 安全審計 skill 的黃金標準。CodeQL、Semgrep、variant analysis、supply chain audit。CC BY-SA 4.0。 | 為已經拿到 codebase 的審計師設計。不是「給我 URL，告訴我能不能裝」的工具。 |
| **商業 AI-native SAST**（ZeroPath、DryRun、Corgea、Cycode）| AI 驅動的靜態分析。有些確實做得很好。 | SaaS 產品。不是 skill。你不能在終端機用一行指令跑它。 |
| **MCP 安全掃描 server**（Semgrep MCP、hexstrike-ai 等）| 把既有安全工具包成 MCP server。 | 工具層級，不是工作流層級。給你 raw output，不是「該不該裝」的答案。 |

### 沒人填補的缺口

我們注意到一件事：**所有人都在掃自己的程式碼。** 不是別人的。

現有工具假設你是在 review 自己的 PR、或是手上已經有 codebase 的審計師。沒有人為「我在 Twitter 上看到這個 repo，裝了會不會出事？」這個場景做過工具。

然後最讓我們驚訝的是 -- **沒有人掃 GitHub Issues。**

想想看。當使用者在一個小型開源專案裡發現弱點，他們通常就是... 開一個 issue。公開的 issue。標題直接寫著「vulnerability」。這是全世界最明顯的信號，但我們看過的每一個安全掃描工具都完全無視它。

這就是我們的切入點。

---

## 設計決策（又叫被需求逼出來的選擇）

### 1. 全 Repo 掃描，不是 Diff 掃描

官方 `/security-review` 掃 diff。我們掃整個 repo。不同使用場景，互補而非競爭。當你在評估一個陌生人的程式碼時，你不關心上一個 PR 改了什麼 -- 你關心的是裡面*現在*有什麼。

### 2. Issues 掃描是一等公民

這是我們的差異化。我們用 `gh issue list` 配合安全關鍵字，撈出使用者回報的弱點。同時看 open（未修補！）和 closed 的 issue，還看回應時間來判斷維護者對安全問題有多上心。

會有雜訊嗎？有時候。有價值嗎？第一次測試就在 issues 裡找到一個真實的未修補弱點。所以是的。

### 3. 維護者健康度也算在內

一個有 3 個 critical 弱點但維護者很活躍的 repo，比一個零已知問題但維護者 18 個月沒 commit 的 repo 安全。我們把 contributor 數量、commit 頻率、CI/CD 有無、測試覆蓋率都納入評估。Bus factor 是真的。

### 4. 依賴 gh + git（而且這沒什麼問題）

我們依賴 `gh`（GitHub CLI）來掃 issues 和抓 repo metadata，依賴 `git` 來 clone。有人可能覺得依賴太重。我們覺得這叫「每個用 Claude Code 的開發者本來就裝好的工具」。

如果 `gh` 不可用，就跳過 issues 掃描，其他照跑。優雅降級，不是硬性失敗。

### 5. 輸出的是意見，不是資料傾倒

大多數安全工具給你一份 finding 清單，然後把判讀留給你。我們多做一步：報告最後有風險總結表和明確的「該不該安裝？」建議。因為當你晚上 11 點在評估一個工具的時候，你不想判讀 47 個 finding -- 你要的是 yes/no 加上證據。

### 6. 我們偷了官方 Skill 的好東西

官方 `/security-review` 的弱點分類架構（Input Validation、Auth、Crypto、Injection、Data Exposure）和輸出格式設計得很好。我們直接借用了 -- MIT license，而且它們確實好用。我們拿掉了 diff 相關的邏輯和過度激進的 false positive 過濾（我們寧可讓你看到一個可能是誤報的 finding，也不要把它藏起來）。

---

## 這個 Skill 不是什麼

誠實面對邊界：

- **不是專業滲透測試的替代品。** 我們做的是 LLM 靜態分析。找不到 zero-day，也不能測試 runtime 行為。
- **不是合規工具。** 我們不 mapping CWE/CVE ID，不產生 SARIF 報告。需要這些的話，請用 Trail of Bits 的 skills 或商業 SAST。
- **不是萬無一失的。** LLM 會漏，我們也會漏。這是「比什麼都不做好得多」的工具，不是「絕對萬無一失」的工具。

但如果你的使用場景是「我找到一個很酷的 repo，想知道它會不會偷我的 SSH key」-- 它在這方面做得不錯。

---

## 參考資料

- [Anthropic /security-review](https://github.com/anthropics/claude-code-security-review) -- MIT，我們的基底
- [Trail of Bits /skills](https://github.com/trailofbits/skills) -- CC BY-SA 4.0，安全審計 skill 的黃金標準
- [ZeroPath](https://zeropath.com)、[DryRun Security](https://www.dryrun.security) -- 商業 AI-native SAST，了解產業方向用
