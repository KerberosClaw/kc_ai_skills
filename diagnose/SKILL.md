---
name: diagnose
description: "Use when the user reports misbehaving software to investigate — a bug, crash, wrong output, flaky behavior, or '為什麼壞掉/不會動/查一下' — and the root cause is not yet established. Enforces building a red-capable reproduction command BEFORE any hypothesis is allowed, then 3-5 ranked falsifiable hypotheses before testing any single one. NOT for conceptual questions, code reading requests, or feature work. When a failing command already exists, Step 1 is pre-satisfied — still apply, jumping straight to the hypothesis discipline."
version: 0.3.0
status: mvp
triggers:
  - "/diagnose"
  - "排查"
  - "查一下為什麼"
  - "壞了"
  - "查 bug"
  - "debug 一下"
---

# diagnose — 先架測謊機，再准審問

You are a disciplined debugger. 你最大的敵人不是 bug，是**自己的過早結論**：讀兩眼 code 就宣稱「找到原因了」，修下去症狀還在、信用先沒了。本 skill 的核心只有一件事——**Step 1 的 feedback loop 才是全部，其餘都是機械動作**。

## Step 0: 適用判定

| 情境 | 套不套 |
|---|---|
| 行為異常（錯輸出 / crash / 時好時壞 / 效能劣化）且原因未明 | ✅ 套 |
| 已有一條會 fail 的指令（失敗測試 / 可重現的 curl） | ✅ 套，既有指令當**候選 loop**——過一遍 Step 1 五條判準（常已滿足）再進 Step 3，必要時回 Step 2 最小化 |
| 純概念問題、讀 code 導覽、新功能需求 | ❌ 不套 |
| 原因已確立、只是要修 | ❌ 不套，直接修 |

## Step 1: 建 red-capable feedback loop（本 skill 的全部）

**CRITICAL — 停止句：這條指令存在之前，禁止讀 code 建理論、禁止提任何 root cause。** 發現自己在沒有重現指令的狀態下開始「應該是因為…」——停，回來先建 loop。

### 完成判準（五條全過才算有 loop）

- [ ] 一條**實際跑過至少一次**的指令（把指令和輸出貼出來，不是「應該可以這樣測」）
- [ ] **Red-capable**：它斷言的是 user 講的那個症狀（錯值、crash、缺資料），**不是「沒噴錯」**
- [ ] 確定性：重跑結果一致（非決定性 bug → 目標改成**拉高重現率**——50% 可以 debug、1% 不行）
- [ ] 秒級完成（分鐘級的 loop 會讓你懶得跑、開始用猜的）
- [ ] 可無人執行（不需要 user 幫忙點畫面）

### Loop 手法選擇

| 情境 | 手法 |
|---|---|
| 有測試框架 | 寫一個 failing test |
| HTTP 服務 | curl + 斷言輸出（grep / jq） |
| CLI / script | 固定 fixture 輸入重跑 |
| 只在特定資料上壞 | 把那筆資料抽成最小 fixture |
| 版本回歸 | `git bisect` + 上面任一手法當判準 |
| 效能問題 | **不用 log**，先量基準數字，再二分定位 |
| 真的建不出來 | 最後手段：明講建不出、列出試過什麼、向 user 要環境 / log dump / 錄影——**不准在沒有 loop 的情況下開始猜** |

## Step 2: 最小化重現

逐項砍（環境變數、輸入欄位、config、資料量），**每砍一項重跑 loop**，直到剩下的每一項都缺它不可（砍掉任何一項就重現不了）。最小化省下的時間會在 Step 4 十倍還你。

## Step 3: 假說——先列 3 到 5 個，再測第一個

**MANDATORY**: 測任何假說之前，先產出一張排序過的假說清單，每條附**可否證預測**：

```
H1（最可能）：<假說>。若為真：跑 <X> 會看到 <Y>。
H2：...
H3：...
```

- 排好的清單**先給 user 過目再開測**——user 常有能瞬間重排順序的領域知識。
- User 不在場（背景 / 無人值守）→ 照自己的排序繼續，但清單和理由要留在紀錄裡。
- 單假說是錨定的溫床：只想到一個解釋，通常代表還沒想。

## Step 4: 驗證

- **一次只變一個變數**。改兩個地方然後綠了，你不知道是哪個。
- Debug log 一律帶唯一前綴（如 `[DBG-4f2a]`），收尾一次 grep 清光。
- 假說被否證 → 劃掉、換下一條，**不是**修改假說硬凹。

## Step 5: 收尾 checklist

**修復需授權**：受託的只是「排查」→ 交出 Step 3/4 的驗證結論與最強假說即結案，不動手修；動手修在 user 同意（或本來就受託修）之後。以下 checklist 屬修復完成後的動作：

- [ ] 原始重現指令轉綠（跑給自己看，不是推論它會綠）
- [ ] grep 前綴、清光 debug log；刪拋棄式 harness / fixture
- [ ] **驗證成立的那個假說寫進 commit message**——下一個 debugger 會感謝你
- [ ] 迴歸測試：只在**正確的 seam**（可插斷言的自然介面：函式邊界 / HTTP 層 / CLI 入口）上寫；seam 太淺的測試給的是假信心。**沒有正確 seam 可放，本身就是一個 finding**，如實回報、不硬塞
- [ ] 迴歸測試的期望值來自**獨立來源**（寫死的已知答案 / 手算範例 / spec / issue 裡貼的實際輸出），**不得由實作反推**
- [ ] 回報時區分「已驗證」與「仍是推測」——alternative 沒全排除前，不用「root cause 確定」這種措辭

## Anti-patterns

- ❌ **讀 code 蓋理論** — 沒有重現指令就開始「應該是 X 造成的」
- ❌ **單假說錨定** — 想到一個解釋就直奔驗證，測完不符再想下一個
- ❌ **「沒噴錯」當通過** — loop 必須斷言症狀本身
- ❌ **恆真測試** — 期望值用跟實作同一套算法重算（`expect(add(a,b)).toBe(a+b)`、照實作邏輯手算出來的 snapshot）。它通過是因為結構上不可能失敗，不是因為 code 是對的
- ❌ **一次改多變數** — 綠了也不知道為什麼綠
- ❌ **過早宣稱 root cause** — 替代假說未排除前，一律「目前最可能」
- ❌ **修好但殘留** — debug log、拋棄式腳本、hack 的 config 留在 codebase

## Important rules

1. **No red-capable command, no hypothesis** — 這是本 skill 唯一不可協商的規則
2. **假說先列滿再測** — 3-5 條、可否證、排序、給 user 過目
3. **一次一變數**
4. **非決定性 bug 目標是拉高重現率**，不是等一個完美重現
5. **正確假說進 commit message**
6. **沒有正確 seam = finding**，不是硬寫測試的理由
7. **期望值不得由實作反推** — 恆真的測試等於沒有測試
8. **建不出 loop 要明講**，列出嘗試、要資源，不轉入猜謎模式

## 跟其他 skill 的關係

- **`spec`**：處理「還沒做的 feature」。症狀是既有行為壞掉（bug / crash / 錯誤輸出 / flaky）→ 本 skill；需求是新功能 → `spec`。別把 debug 包裝成開新 spec。
- **`adr`**：debug 若催出難回頭的決策，驗完可用 `adr` 記「為什麼這樣修」；debug 流程本身留在本 skill。
- 選哪顆有疑問 → 見 README 決策框或 `workflow-router`。

## Acknowledgments

Feedback-loop-first 與多假說紀律參考 [mattpocock/skills](https://github.com/mattpocock/skills)（MIT）的 diagnosing-bugs，中文重寫並融入自家排查教訓（過早結論、單假說錨定為實戰高頻失誤）。恆真測試反模式參考同 repo 的 tdd。
