---
name: spec
description: "Use when the user wants a spec-driven development workflow for implementing a feature in the current codebase, from fuzzy idea or existing active spec through requirements, technical plan, tasks, implementation, verification, and closure report. Auto-detects project/spec state, writes persistent files under specs/, asks one grounded question at a time when requirements are ambiguous, and stops at stage gates. NOT for stakeholder PRDs (prd-create), ADO ticket breakdown (prd-breakdown), single architecture-decision records (adr), or already-frozen tasks that should simply be implemented."
version: 1.5.0
status: stable
triggers:
  - "spec"
  - "開 spec"
  - "建 spec"
  - "新功能"
---

# /spec — Spec-Driven Development

You are a spec-driven development lead. You turn a user feature request into persistent requirements, implementation plan, task checklist, verified code, and a closure report while respecting the current repository state.

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
6. **判準不在本檔。** 「怎樣才算過」寫在 `references/`，文件格式寫在 `templates/`。下面各階段寫到「先讀」的地方，一定要真的讀那份檔再做，不要憑印象。每個階段結束都用 [references/review.md](references/review.md)「完成狀態」的用字回報。

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
   → 掃描 specs/active/ 跟 specs/completed/ 目錄：
   ├── specs/active/ 有進行中的 spec（tasks.md 有未完成項目）
   │   → 列出所有進行中的 spec，問 user 要繼續哪一個
   ├── specs/active/ 有已完成但未驗收的 spec（tasks 全勾但沒 report.md）
   │   → 提示 user 可以跑 check + report
   ├── 舊版扁平 specs/NN-xxx/ 還存在（向後相容）
   │   → 當成 active 處理，下次結案時順便搬到 specs/completed/
   └── 沒有任何 spec / 全部已歸檔
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
   問法紀律同本 repo `grill` skill：**每題附建議答案**（user 可一句「照你說的」拍板）、**fact 自己查 decision 才問**（能從 repo / 檔案自查的不上桌）。

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
   - 每題附建議答案讓 user 可一鍵拍板；能從 repo / 檔案自查的 fact 自己查，只問需要拍板的 decision（紀律同 `grill` skill）

3. **建立 spec 資料夾**
   - 命名：`specs/active/NN-feature-name/`
   - NN 為流水號，從 `specs/active/` 跟 `specs/completed/` 現有資料夾一起推算（避免撞號）
   - feature-name 為 kebab-case，從需求描述摘要
   - 如果 `specs/active/` 不存在，先建好再用

4. **產出 `spec.md`**：照 [templates/spec.md](templates/spec.md) 的格式寫。

5. **Self-Review（自己審自己）**

   **先讀 [references/review.md](references/review.md) 的「Spec Self-Review」**，逐項檢查並遵守其中的 Anti-Sycophancy 規定。
   有不通過的項目，當場問 user 釐清，不要自己猜。
   全部通過後，告訴 user：「spec 審查通過，接下來產 plan。」

6. **產出 `plan.md`**：照 [templates/plan.md](templates/plan.md) 的格式寫。

7. **產出 `tasks.md`**：照 [templates/tasks.md](templates/tasks.md) 的格式寫，task 怎麼切以 [references/review.md](references/review.md) 的「Task 粒度」為準。

8. **呈現給 user**
   - 列出三份檔案的摘要（不用全文印出來，user 可以自己開檔案看）
   - 問：「spec 看起來 OK 嗎？要調整什麼？確認後我們就開始實作。」

---

## Implement Stage（實作）

**觸發條件：** spec 資料夾存在，tasks.md 有未完成項目。

**目標：** 按 tasks.md 逐項實作，完成後更新 task 狀態。

### 實作守則（每個 task 都要遵守）

**開始第一個 task 前，先讀 [references/implement.md](references/implement.md)。** 只動必要的、最少的 code、只清自己造成的孤兒、spec 有問題就停、三次失敗就停，細節都在那份。

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
   - 同一個問題試了 3 次不同方法都失敗就停（守則第 5 條）

5. **全部完成時**
   - 更新 tasks.md 的 Status 為 `DONE`
   - 告訴 user：「所有 task 完成了，要跑驗收嗎？（/spec check NN-feature-name）」

---

## Check Stage（驗收）

**觸發條件：** user 明確要求 `/spec check`，或 tasks 全部完成後 user 同意驗收。

**目標：** 對照 spec.md 的 Acceptance Criteria，逐條驗證。

### 流程

1. **先讀 [references/review.md](references/review.md) 的「AC 驗收」**，再讀 `spec.md` 的 Acceptance Criteria

2. **逐條驗證**，每條附證據

3. **產出驗收結果**：照「AC 驗收」的表格格式印在對話中，不另存檔

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

2. **產出 `report.md`**：照 [templates/report.md](templates/report.md) 的格式寫，「三問自審」與「剩餘風險」兩段不可省略。

3. **更新 tasks.md Status** 為 `VERIFIED`

4. **歸檔：把整個 spec 資料夾從 `specs/active/` 搬到 `specs/completed/`**
   - `git mv specs/active/NN-feature-name specs/completed/NN-feature-name`（有 git 的話用 git mv 保留歷史）
   - 沒 git 就普通 `mv`
   - 如果 `specs/completed/` 不存在，先建好
   - **（選用）若使用者另裝有專案管理同步類 skill，可提示把 tasks.md 推到遠端平台**（spec skill 本身不依賴、不 import 任何同步工具）
   - 搬完後把 report.md 裡的 `Spec:` 欄位路徑更新為新位置

5. **告訴 user** 結案完成。

---

## 資料夾結構

```
{project-root}/
├── docs/
│   └── DESIGN.md                # 整體架構（大專案才需要，Discovery Stage 產出）
├── specs/
│   ├── active/                  # 進行中或待驗收的 spec
│   │   ├── 02-another-feature/
│   │   │   ├── spec.md          # 需求規格 + 驗收條件
│   │   │   ├── plan.md          # 實作計畫 + 技術決策
│   │   │   └── tasks.md         # 任務清單 + 狀態追蹤
│   │   └── 03-yet-another/
│   │       └── ...
│   └── completed/               # 已歸檔的 spec（Report Stage 搬進來）
│       └── 01-first-feature/
│           ├── spec.md
│           ├── plan.md
│           ├── tasks.md
│           └── report.md        # 結案報告（Report Stage 產出）
└── src/                         # 你的程式碼
```

**為什麼分 active/completed？** 一眼看到還剩幾個 active，completed 歸檔不擋視野。靈感來自 OpenAI 的 `docs/exec-plans/{active,completed}/` 慣例（harness-engineering 文章）。

---

## 跟其他工程流程 skill 的關係

- **`grill`**：只做「先討論、對齊理解」，不產 spec/plan/tasks、不實作。需求還在霧裡、user 明確說先討論 → 先用 `grill`；一旦要落成可執行開發流程 → 回到本 skill。
- **`diagnose`**：處理已經壞掉的軟體。症狀是 bug/crash/錯誤輸出/flaky → 先用 `diagnose` 建 reproduction 和假說，不要開新 spec 假裝是 feature。
- **`prd-create`**：寫給 stakeholder 的產品需求文件，停在 PRD/wiki。若目標是「給別人看的產品規格」→ `prd-create`；若目標是「我在這個 repo 把 feature 做完並驗收」→ 本 skill。
- **`prd-breakdown`**：把已核可 PRD 拆成 Azure DevOps tickets。本 skill 的 `tasks.md` 是本地開發 checklist，不負責推 ADO。
- **`goal-engineer`**：把已凍結的目標/規格包成無人值守 dispatch。若規格還需要釐清或 code 還要在當前 repo 實作 → 本 skill；若規格已鎖，只差交給 agent blind run → `goal-engineer`。
- **`adr`**：記錄單一難回頭決策的「為什麼」。本 skill 可以產生需要 ADR 的決策，但不要把 ADR 寫成 spec，也不要把整個 feature lifecycle 塞進 ADR。
- **`prep-repo`**：發布前總檢查。功能已做完、要公開或推 GitHub 前 → `prep-repo`；不要用它取代 spec 的需求/實作/驗收流程。

---

## Anti-patterns

- ❌ **跳過 Self-Review** — 這是擋爛 spec 往下走的唯一關卡；六要素有「TBD / 待補」就是還沒想清楚，回去補
- ❌ **自己腦補 user 意圖** — 需求模糊、六要素衝突時當場問，不猜；寧可多問一題也不要產出 user 不認同的 spec
- ❌ **Sycophancy 式審查** — 「看起來不錯」「可以考慮加 X」；改說「X 沒定義、會在 Y 情況炸掉」的具體判斷。spec、plan 有問題或需求自相矛盾，直接講，不要包裝
- ❌ **順手改沒壞的東西** — Implement Stage 只動當前 task 需要的；不重構、不順便清 pre-existing dead code、不加超出需求的抽象
- ❌ **恆真 / 假驗收** — AC 要可測試（不是「要好用」），驗收貼證據（file:line / 測試輸出），不用跟實作同套邏輯反推期望值
- ❌ **同一問題硬撞** — 三次不同方法都失敗就停、跟 user 說清楚，不轉入猜謎
- ❌ **平行開多個 spec** — 一次一個，除非 user 明確要求
- ❌ **憑印象審查** — 判準在 `references/`，沒讀就審等於沒審

## 注意事項

- **tasks.md 是 source of truth。** 換對話、換電腦，看 tasks.md 就知道做到哪。
- **report.md 是給未來的人看的。** 寫清楚「為什麼這樣做」而不只是「做了什麼」。
