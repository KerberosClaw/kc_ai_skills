---
name: spec
description: "Spec-driven 開發流程 — 從模糊需求到驗收結案。自動判斷專案狀態，引導 user 走完：需求釐清 → 技術審查 → 實作 → 驗收 → 結案報告。"
version: 1.0.0
triggers: ["spec", "開 spec", "建 spec", "新功能"]
---

# /spec — Spec-Driven Development

把「實作 feature 的流程」標準化：需求釐清 → 技術審查 → 實作 → 驗收 → 結案。
一個入口，自動判斷該做什麼。

## 使用方式

```
# 新需求（有明確想法）
/spec 做一個 Markdown loader，遞迴讀取資料夾內所有 .md 檔

# 新需求（很模糊）
/spec 我想做一個全本地的 RAG pipeline

# 繼續上次進度（自動偵測狀態）
/spec

# 指定操作特定 spec
/spec check 01-loader-chunker
/spec report 01-loader-chunker
```

---

## 執行規則

1. 永遠先跑 **Stage Detection** 判斷目前狀態，再決定進入哪個階段。
2. 所有產出的檔案放在專案根目錄的 `specs/` 下。
3. 用 `git rev-parse --show-toplevel` 找專案根目錄。如果不在 git repo 裡，用當前工作目錄。
4. 不主動執行 user 沒要求的事。每個階段完成後，說明產出了什麼，問 user 下一步。
5. 與 user 的互動用正體中文。spec/plan/tasks/report 文件摘要為英文（English summary），內容為正體中文。

---

## Stage Detection（自動判斷）

依序檢查，命中第一個就進入對應階段：

```
1. user 明確指定了操作？（如 /spec check 01-xxx）
   → 進入指定階段

2. user 提供了新需求描述？（如 /spec 做一個 loader）
   → 判斷規模：
   ├── 需求能在一個 spec 內完成（單一功能/模組）
   │   → 進入 Spec Stage
   └── 需求涵蓋多個模組/需要整體架構設計
       → 進入 Discovery Stage

3. user 沒提供描述？（只打 /spec）
   → 掃描 specs/ 目錄：
   ├── 有進行中的 spec（tasks.md 有未完成項目）
   │   → 列出所有進行中的 spec，問 user 要繼續哪一個
   ├── 有已完成但未驗收的 spec（tasks 全勾但沒 report.md）
   │   → 提示 user 可以跑 check + report
   └── 沒有任何 spec / 全部已結案
       → 提示 user 提供新需求
```

### 判斷「需求規模」的標準

問自己：**這個需求能拆成一張 tasks checklist（5-10 項）就做完嗎？**

- 能 → 單一 spec，直接進 Spec Stage
- 不能 → 需要先在 Discovery Stage 討論架構，拆成多個 spec

不確定的時候，問 user。

---

## Discovery Stage（大專案 → DESIGN.md）

**觸發條件：** 需求模糊或規模大，需要先釐清整體架構。

**目標：** 透過對話，把模糊想法收斂成一份 `docs/DESIGN.md`，然後拆成可執行的 spec 清單。

### 流程

1. **釐清問題（Forcing Questions）**

   逐題問，每題推到拿到具體答案為止。不要一次丟 5 個問題。

   **Q1: 痛點確認**
   「這個專案要解決什麼具體問題？誰會遇到這個問題？」
   - 推到什麼程度：聽到具體場景、具體的人、具體的痛。
   - 紅旗：「大家都需要」「市面上沒有類似的」「應該會有用」— 這些都是假需求的信號。
   - 不要說「聽起來不錯」— 說「你剛才說的是 X 場景，對嗎？」直接確認。

   **Q2: 現狀與替代方案**
   「現在怎麼解決這個問題的？就算用很爛的方式？」
   - 推到什麼程度：聽到具體的 workaround（手動流程、土炮腳本、第三方工具）。
   - 紅旗：「現在完全沒辦法做」— 如果真的沒人在解決，通常代表問題不夠痛。

   **Q3: 技術限制**
   「有什麼技術限制？設備、預算、時間、必須用的技術棧？」
   - 推到什麼程度：拿到硬限制清單（硬體規格、預算上限、deadline）。
   - 如果 user 說「沒限制」，追問一次：「跑在哪台機器上？要花錢嗎？什麼時候要用？」

   **Q4: 最小範圍**
   「如果只做一個最小版本，什麼功能是第一天就必須有的？」
   - 推到什麼程度：user 能說出一個可以獨立運作的最小功能集。
   - 紅旗：「都很重要，不能少」— 要求排優先級：「如果只能留三個，留哪三個？」

   **Q5: 明確排除**
   「有什麼是你確定不做的？」
   - 推到什麼程度：至少列出 2-3 個明確排除項。
   - 這題很重要，省略會導致 scope creep。如果 user 想不到，主動建議：「像是 Web UI、多用戶、雲端部署，這些第一版要嗎？」

   **問題路由：** 不是每題都要問。
   - user 已經有明確的技術選型 → 跳過 Q3 的技術棧部分
   - user 從 DESIGN.md 能回答的 → 不要重複問
   - user 已經在需求描述中回答過的 → 直接確認，不要再問一次

2. **產出 `docs/DESIGN.md`**
   - 概觀（做什麼、為什麼）
   - 架構圖（Mermaid）
   - 技術選型 + 理由
   - Pipeline / 流程拆解
   - 不做的事

3. **拆 Spec 清單**
   - 從 DESIGN.md 拆出建議的 spec 順序
   - 標明依賴關係（哪個要先做）
   - 問 user：「要從哪個開始？」
   - User 選定後，進入 Spec Stage

---

## Spec Stage（產 spec.md + plan.md + tasks.md）

**觸發條件：** user 提供了明確的 feature 需求。

**目標：** 產出三份文件，確保「想清楚再動手」。

### 流程

1. **讀取上下文**
   - 如果專案有 `docs/DESIGN.md`，先讀它
   - 如果 `specs/` 下已有其他 spec，讀它們的 spec.md 了解已完成的部分
   - 這些資訊用來避免重複和衝突

2. **釐清需求**（跟 user 對話，最多 3-5 個問題）
   - 只問會影響設計的問題
   - 不問 user 已經在需求描述中回答過的問題
   - 如果從 DESIGN.md 能找到答案，不要再問

3. **建立 spec 資料夾**
   - 命名：`specs/NN-feature-name/`
   - NN 為流水號，從 `specs/` 現有資料夾推算
   - feature-name 為 kebab-case，從需求描述摘要

4. **產出 `spec.md`**

```markdown
# 功能名稱

> **English summary:** One-line summary of what this feature does and why.

## 背景

為什麼需要這個功能。如果有 DESIGN.md，標註對應的章節。

## 驗收條件

- [ ] AC-1: [具體、可測試的條件]
- [ ] AC-2: [具體、可測試的條件]
- [ ] AC-3: ...

## 不做的事

- [明確排除的項目]
- [另一個排除項目]

## 依賴

- [外部服務、套件、或必須先完成的其他 spec]
```

5. **Self-Review（自己審自己）**

   產完 spec.md 後，逐項檢查：

   | 檢查項目 | 不通過怎麼辦 |
   |---------|------------|
   | 每個 AC 都可測試？（不是「要好用」這種） | 改寫成可測試的條件 |
   | 邊界條件有定義？（空輸入、超大檔、錯誤格式） | 補到 AC 或 Out of Scope |
   | 範圍明確？（不做的事有列出來） | 補 Out of Scope |
   | 外部依賴有交代？ | 補 Dependencies |
   | 跟已有的 spec 衝突嗎？ | 標出衝突，問 user |

   **Anti-Sycophancy（審查時禁止的行為）：**
   - 不要說「這個 spec 看起來不錯」— 說具體哪裡通過、哪裡有問題
   - 不要說「可以考慮加上 X」— 說「X 沒定義，這會在 Y 情況下炸掉」
   - 不要自己腦補答案 — 不確定就問 user
   - 如果 spec 有明顯漏洞，直接說「這個 spec 有問題」，不要包裝成建議

   如果有不通過的項目，**當場問 user 釐清，不要自己猜**。
   全部通過後，告訴 user：「spec 審查通過，接下來產 plan。」

6. **產出 `plan.md`**

```markdown
# 實作計畫

> **English summary:** Brief description of the implementation approach.

## 做法

[1-2 段：怎麼做這個功能]

## 關鍵決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| ... | ... | ... |

## 風險

| 風險 | 對策 |
|------|------|
| ... | ... |

## 實作順序

1. [先做什麼 — 為什麼先做]
2. [再做什麼 — 因為依賴 #1]
3. ...
```

7. **產出 `tasks.md`**

```markdown
# 任務清單

> **English summary:** Task checklist for [feature-name].

**Spec:** [feature-name]
**Status:** NOT_STARTED | IN_PROGRESS | DONE | BLOCKED | VERIFIED

## Checklist

- [ ] Task 1: [交付物描述 — 完成時可以怎麼驗證]
- [ ] Task 2: ...
- [ ] Task 3: ...

## 備註

[實作筆記、踩坑紀錄、或交接給其他人時需要知道的事]
```

   **Task 粒度原則：**
   - 一個 task = 一個可以跟別人說「這個做完了」的交付物
   - 通常對應 1-3 個檔案的改動
   - 5-10 個 tasks 為一個 spec 的合理範圍
   - 太細（「寫一個 function」）→ 合併
   - 太粗（「完成整個模組」）→ 拆開

8. **呈現給 user**
   - 列出三份檔案的摘要（不用全文印出來，user 可以自己開檔案看）
   - 問：「spec 看起來 OK 嗎？要調整什麼？確認後我們就開始實作。」

---

## Implement Stage（實作）

**觸發條件：** spec 資料夾存在，tasks.md 有未完成項目。

**目標：** 按 tasks.md 逐項實作，完成後更新 task 狀態。

### 流程

1. **載入上下文**
   - 讀 `spec.md`、`plan.md`、`tasks.md`
   - 找到第一個未完成的 task
   - 如果專案有 `docs/DESIGN.md`，也讀它

2. **進入 Claude Code Plan Mode**
   - 用 plan.md 的 Implementation Order 作為計畫骨架
   - 逐項執行 task

3. **每完成一個 task**
   - 更新 `tasks.md`：把 `- [ ]` 改成 `- [x]`
   - 如果實作過程中有重要的決策偏離 plan，在 tasks.md 的 Notes 區補充

4. **遇到阻塞時**
   - 更新 tasks.md 的 Status 為 `BLOCKED`
   - 在 Notes 區記錄：卡在什麼、試過什麼、建議怎麼解
   - 告訴 user 狀況，不要自己硬撐
   - **三振原則：** 同一個問題試了 3 次不同方法都失敗 → 停下來，跟 user 說清楚狀況，不要繼續猜

5. **全部完成時**
   - 更新 tasks.md 的 Status 為 `DONE`
   - 告訴 user：「所有 task 完成了，要跑驗收嗎？（/spec check NN-feature-name）」

---

## Check Stage（驗收）

**觸發條件：** user 明確要求 `/spec check`，或 tasks 全部完成後 user 同意驗收。

**目標：** 對照 spec.md 的 Acceptance Criteria，逐條驗證。

### 流程

1. **讀 `spec.md` 的 Acceptance Criteria**

2. **逐條驗證**
   - 讀相關的 source code
   - 如果 AC 可以用測試驗證，跑測試
   - 如果 AC 是行為描述，讀 code 判斷

3. **產出驗收結果**（印在對話中，不另存檔）

```
## Acceptance Criteria Check

| AC | Status | Evidence |
|----|--------|----------|
| AC-1: ... | PASS | [file:line or test result] |
| AC-2: ... | FAIL | [what's missing or wrong] |
```

4. **FAIL 的處理**
   - 列出需要修正的項目
   - 問 user：「要現在修嗎？」
   - 修完後可以再跑一次 check

5. **全部 PASS**
   - 告訴 user：「驗收通過，要產結案報告嗎？（/spec report NN-feature-name）」

---

## Report Stage（結案）

**觸發條件：** user 明確要求 `/spec report`。

**目標：** 產出 `report.md`，記錄這個 feature 的完整生命週期。

### 流程

1. **收集資訊**
   - 讀 `spec.md`、`plan.md`、`tasks.md`
   - 讀 git log（找跟這個 spec 相關的 commit）

2. **產出 `report.md`**

```markdown
# 結案報告：功能名稱

> **English summary:** Brief summary of what was built and the outcome.

**Spec:** specs/NN-feature-name
**Status:** completed
**Date:** YYYY-MM-DD

## 摘要

[1-2 句：做了什麼]

## 驗收條件結果

| 驗收條件 | 狀態 |
|---------|------|
| AC-1: ... | PASS |
| AC-2: ... | PASS |

## 關鍵 Commit

| Commit | 說明 |
|--------|------|
| abc1234 | ... |

## 與計畫的偏差

[實作過程中跟原本 plan 不同的地方。完全照做就寫「無」。]

## 備註

[學到的教訓、踩過的坑、對未來有用的資訊]
```

3. **更新 tasks.md Status** 為 `VERIFIED`

4. **告訴 user** 結案完成。

---

## 資料夾結構

```
{project-root}/
├── docs/
│   └── DESIGN.md          # 整體架構（大專案才需要，Discovery Stage 產出）
├── specs/
│   ├── 01-feature-name/
│   │   ├── spec.md        # 需求規格 + 驗收條件
│   │   ├── plan.md        # 實作計畫 + 技術決策
│   │   ├── tasks.md       # 任務清單 + 狀態追蹤
│   │   └── report.md      # 結案報告（Check + Report Stage 產出）
│   └── 02-another-feature/
│       └── ...
└── src/                   # 你的程式碼
```

---

## Completion Status Protocol

每個階段結束時，用以下狀態回報：

| 狀態 | 意思 | 後續動作 |
|------|------|---------|
| **DONE** | 全部完成，有證據 | 進入下一階段 |
| **DONE_WITH_CONCERNS** | 完成了，但有疑慮 | 列出疑慮，問 user 要不要處理 |
| **BLOCKED** | 卡住了，無法繼續 | 說明卡在哪、試過什麼、建議怎麼解 |
| **NEEDS_CONTEXT** | 缺少資訊，無法判斷 | 明確說需要什麼資訊 |

---

## 注意事項

- **不要跳過 Self-Review。** 這是防止爛 spec 往下走的唯一關卡。
- **不要自己猜 user 的意圖。** 不確定就問。寧可多問一個問題，也不要產出一份 user 不認同的 spec。
- **tasks.md 是 source of truth。** 換對話、換電腦，看 tasks.md 就知道做到哪。
- **report.md 是給未來的人看的。** 寫清楚「為什麼這樣做」而不只是「做了什麼」。
- **一次只做一個 spec。** 不要同時開好幾個 spec 平行實作，除非 user 明確要求。
- **三振出局。** 同一個問題試 3 次失敗就停，跟 user 說清楚，不要硬做。
- **直說不好聽的。** 如果 spec 有問題、plan 不可行、需求自相矛盾，直接講，不要包裝。
