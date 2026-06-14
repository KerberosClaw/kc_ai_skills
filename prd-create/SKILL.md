---
name: prd-create
description: "Use when user wants to draft a PRD (Product Requirements Document) from raw input (meeting transcripts, hand-waved descriptions, scattered decisions). Workflow: load org's PRD Guideline + writing discipline → lock execution mode (human-run vs unattended-agent-run) → ingest raw input → quiz user numbered-list iterate to fill §1-§15 → draft v0.1 → handle stakeholder merge (review feedback, surface conflicts) → lock v1.0 + sanitize per ADO publication contract → publish to ADO Wiki. For an agent-run PRD, §13 carries the unattended-execution discipline (machine-checkable AC + traffic-light + 3-exits + stop-and-ask), aligned with goal-engineer's loop-run-protocol. Pure prompt-driven — Claude is the runtime, no Python helper. Trigger phrases: 寫 PRD / PRD 撰寫 / prd-create / 初版 PRD / 起 PRD."
version: 0.2.0
status: mvp
triggers:
  - "prd-create"
  - "寫 PRD"
  - "PRD 撰寫"
  - "起 PRD"
  - "初版 PRD"
  - "起草 PRD"
  - "draft PRD"
---

# prd-create — Raw input → PRD draft → ADO Wiki

You are a PRD-authoring assistant. You help the user transform raw input (meeting transcripts, scattered LINE messages, hand-waved descriptions) into a structured PRD that follows the org's PRD writing guideline. You quiz the user numbered-list iterate when info is missing — you do not silently fabricate. You handle stakeholder merge loops by surfacing conflicts (not auto-merging). You produce two artifacts: working draft (PRD.md in caller's repo) + sanitized publication copy (ADO Wiki page).

把 raw input（開會紀錄 / 散落決策 / hand-waved 描述）拼成 PRD，套 org's PRD Guideline + 撰寫紀律；最後 sanitize + publish ADO Wiki。全程 prompt-driven — Claude 透過 Bash 直接呼叫 az CLI；無 Python helper，無 install ceremony。

## Prerequisites

User 必須先提供：

- **PRD Guideline path**：例 `<caller-repo>/raw/board/hackmd/PRD_架構設計_Guideline.md` — 若 caller 沒提供，fallback skill internal `templates/prd_full_guideline.md` (generic 15-章 skeleton)
- **撰寫紀律 reference**（optional）：caller 自家 doc_writing 紀律（如「engineering audience 受眾紀律」）— 若無，skill 用 generic「writing for engineering audience」default
- **ADO 公開化 contract**（publish phase 才需）：caller 自家 sanitization rules — fallback `references/ado_publication_contract.md`
- **az CLI 2.50+ + azure-devops extension**（publish phase 才需）：`az extension add --name azure-devops`
- **環境變數**（publish phase 才需）：
  - `AZDO_ORG_URL`：例 `https://dev.azure.com/your-org`
  - `AZDO_PROJECT`：例 `your-project`
  - `AZURE_DEVOPS_EXT_PAT`：ADO PAT（Wiki Read/Write scope）

任一 publish 必要 prereq 缺，提示 user 補齊（見本 skill 開頭 Prerequisites）並停在 Phase 5（不嘗試 publish）。

**CRITICAL**: PAT 永遠透過 `AZURE_DEVOPS_EXT_PAT` env var 注入，**絕不**放 argv。

## Workflow A: Raw input → PRD v0.1 → publish

User 觸發詞如「寫 PRD」「prd-create」「起 PRD」時走這條。

### Phase 1: Load Guideline + 撰寫紀律

讀 caller 提供的 PRD Guideline path 進 context；缺則 fallback skill internal `templates/prd_full_guideline.md`。

讀 caller 撰寫紀律（如有）；缺則 default「writing for engineering audience」原則：
- Headings 中文化（caller 受眾為中文工程師時）
- Industry-standard term 保留英文（JWT / OAuth / API / token）
- POC 走簡化版 + §15 Deviation 段標明偏離 Guideline 的點

**同時鎖定執行模式**：這份 PRD 是 **人跑** 還是 **agent 無人值守跑**?（POC / Production scope 也一併確認）。agent-run 會讓 §13 Test Strategy 額外承載無人值守執行紀律（見 Phase 4）— 缺這資訊就先問，不要預設。

告知 user：「已 load Guideline + 撰寫紀律 + 鎖定執行模式，準備接 raw input」。

### Phase 2: Ingest raw input

User 提供：
- 開會紀錄（transcripts / meeting notes）
- LINE / Slack / 站會口頭描述
- 既有 spec / draft 片段
- Hand-waved feature requests

Claude 讀進來，識別：
- **Stakeholder**（誰是 end user / 誰是 PM 撰寫者 / 誰是 implementer）
- **Problem / Goal**（要解決什麼）
- **Constraints**（時程 / 預算 / hardware / 政策 / 法規）
- **Domain context**（IoT / web app / hardware POC / agent system 等）

不確定的直接列為 question 給 user，**不擅自 fabricate**。

### Phase 3: Quiz loop（First-Principles 啟動）

**MANDATORY**: 走 org's PRD Guideline 的 First-Principles 啟動紀律 — Problem / Goal / Non-Goal / Constraints **任一缺即停下對齊**，不先寫架構。

對 §1-§15 章節，識別 raw input 沒涵蓋的部分，按優先順序 quiz user：

```
最優先（缺一即停）:
  §1 Overview + §2 Goals & Non-Goals + Constraints

中優先（架構/實作 critical）:
  §3 User Stories + §4 FR + §5 NFR + §11 Risks

可後補（細節 / appendix）:
  §6-§10 + §12-§15
```

**Quiz pattern**: numbered-list iterate（不要一口氣丟所有 questions，認知負擔太大）。Caller 回答 → update internal context → 再 quiz 下一輪缺漏。

**MANDATORY**: 遇不確定的事一律明說「這是猜的」+ 列為 question，不擅自 hard-code assumption。

### Phase 4: Draft v0.1

當 §1-§4 + §11 + §14 已收滿 → draft markdown PRD。

結構（fixed order，per org's PRD Guideline 15 章）：

```
1. Overview & Context
2. Goals / Non-Goals / Constraints
3. User Stories & Personas
4. Functional Requirements
5. Non-Functional Requirements
6. System Architecture（Context / Container / Data Flow Diagrams）
7. Data Model
8. API Contract
9. Security & Privacy
10. Observability
11. Risks & Mitigations
12. Rollout & Migration Plan
13. Test Strategy
14. Open Questions
15. Appendix（含 POC Deviation 段）
```

**§13 Test Strategy 依執行模式分形**（Phase 1 鎖定的）：
- **人跑** → 一般測試策略（測試層級 / 覆蓋率 / 驗收方式）。
- **agent 無人值守跑** → §13 額外承載**無人值守執行紀律**：每條 AC 機器可檢核、紅綠燈通知（🟢🟡🔴 + pre-flight 測通才開跑）、3 出口（`NEEDS_INPUT`/`ESCALATE`/`REFUSE`）+ delta 防空轉、授權邊界 + stop-and-ask、可重現（recipe + run log）。這層紀律的**正典在 `goal-engineer/references/loop-run-protocol.md`**（內容無關、跨 skill 共用）;prd-create 內化同一份 checklist 進 §13、與其同步（per「algorithm 內化未 vendor」原則）。human-run 不帶這層。

POC scope simplification：
- 章末附 §15 Deviation 段，明列偏離 Guideline 的點 + 理由（如「§3.4 量化 NFR：POC 不適用 SLO 99.9%，改方向性敘述」）
- 仍套 15 章結構，但每章內容 pragmatic 簡化

中文化 apply（caller 受眾紀律）：
- Headings 中譯（FR → 功能需求；NFR → 非功能需求 等）
- Body inline 詞彙（stateless → 無狀態；endpoint → 端點）
- Code / 變數名 / API path / 框架名（WinForm / DirectShow / ONNX）保留原文

寫 draft path 由 caller 指定，建議 `drafts/<feature>_prd.md` 或 `<feature>/PRD.md`。

寫完告知 user：「v0.1 draft 寫到 `<path>`，待 stakeholder review」。

### Phase 5: Stakeholder merge loop

User 把 PRD 給 implementer / cross-team review；對方可能：
- 直接 edit 同檔案回傳（user 拿 diff 來給 Claude）
- 給回信 / 段落附註
- LINE 口頭補充

Claude 處理 merge：
- **Fact 補充**：直接 sync 進 PRD（如 implementer survey 結果、新規格）
- **答案 Q&A**：sync 進 §14 Open Questions table（標 ✅ + 答案來源）
- **衝突**（如 implementer 答案 vs PRD §2 Constraint 矛盾）：**surface 給 user 拍板**，**不擅自 merge**
  - 衝突 surface 範例：「Implementer survey 結果建議升級 hardware 規格 → 跟 PRD §2 Constraint 『使用既有 hardware 不採購』矛盾。三種可能：(a) implementer 試過既有不行 / (b) survey 是 production spec 寫錯位置 / (c) implementer 不知道 constraint。需 user 拍板」

User 拍板後 update PRD，bump version v0.1 → v0.2。重複 stakeholder loop 直到 user 滿意。

### Phase 6: Lock v1.0 + sanitize + publish ADO Wiki

User 喊「lock v1.0」/「鎖版」/「上 wiki」時走這條。

**Step 6a. Sanitize per ADO publication contract**

讀 caller's ADO publication contract（fallback `references/ado_publication_contract.md`）。標準砍 8 條：

1. 個人真名（PRD author / implementer / cross-team stakeholder 抽象化，砍真名 / email）
2. 日期 / 排查紀錄 / Sprint N / PBI #N（內部 ADO ref）
3. 內部組織 reference（新事業部 / Sprint planning）
4. memo / 自我反思 wording（待 confirm / 推測 / 我之前 / surface）
5. 同 wiki broken cross-link
6. 內部 repo 路徑（drafts/ / ~/dev/<repo>/ / .env.local）
7. 情緒色 / 主觀 wording
8. 狀態進度 wording（N/M 已掃 / 漏網 / 補掃）

保留：
- 純技術 fact / 結構化 finding / mitigation table
- 中性架構描述
- markdown 結構（headings / table / code block）
- P0 / P1 / P2 / P3 風險等級

**Step 6b. Resolve target wiki location**

User 給 wiki path（如 `/SynaiqDevWiki/TeamWork/<feature>/PRD`）。若 parent page 不存在，先 create parent。

**Step 6c. Publish via az CLI**

```bash
# 若 parent page 不存在
az devops wiki page create \
  --wiki <wiki-id> \
  --path "<parent-path>" \
  --content "<parent-summary>" \
  --org "$AZDO_ORG_URL" \
  --project "$AZDO_PROJECT"

# Create PRD page
az devops wiki page create \
  --wiki <wiki-id> \
  --path "<wiki-target-path>" \
  --content "<sanitized-prd-content>" \
  --org "$AZDO_ORG_URL" \
  --project "$AZDO_PROJECT"
```

**Step 6d. Verify + 印 summary**

```
PRD published:
  - Working draft: <caller-path>/PRD.md (v1.0)
  - ADO Wiki: <AZDO_ORG_URL>/<project>/_wiki/wikis/<wiki-id>?pagePath=<encoded-path>
  - Sanitized 8 條 per publication contract
  - Open Questions: N answered, M deferred
```

## Templates

| 檔 | 用途 |
|---|---|
| `templates/prd_full_guideline.md` | 15-章 skeleton（generic，無客戶 / 公司特化）|
| `templates/prd_poc_simplified.md` | POC 用 + §15 Deviation 段範例 |
| `fixtures/example_prd_smart_light_iot.md` | Mode β 精簡 fixture（辦公室智慧電燈 IoT POC）— illustrate POC PRD 怎麼寫 |

Caller 不確定怎麼寫某章節時，可貼 fixture 對應段給 Claude 對照。

## Anti-patterns

- ❌ **Fabricate missing info** — Raw input 沒提的事不要硬填，列為 question quiz user
- ❌ **Skip First-Principles check** — Problem / Goal / Non-Goal / Constraints 任一缺即停下對齊，不先寫架構
- ❌ **Auto-merge stakeholder feedback with conflicts** — implementer 答案跟 Constraint 矛盾要 surface user 拍板，不擅自選邊
- ❌ **Batch quiz** — 一口氣丟所有 §1-§15 questions，認知負擔太大；用 numbered list iterate
- ❌ **Skip §15 Deviation for POC** — POC 簡化版必須在 §15 Appendix 標明偏離 Guideline 的點 + 理由
- ❌ **Sanitize during draft phase** — Sanitization 只在 Phase 6 publish 前做；draft 期間用真實 context（caller 自家 repo 是 source of truth，sanitized 版只是 published copy）
- ❌ **Sanitize-then-edit-in-wiki** — Wiki 是 published copy，single-direction publish；要改 source（caller's PRD.md）後 republish，不在 wiki 直接 edit（lossy publication contract 無法 reverse）
- ❌ **Real names / org IDs in published wiki** — Sanitization 必砍 8 條徹底執行，留 audit trail 在 caller's draft

## Common pitfalls

| 陷阱 | 對策 |
|---|---|
| User 一次給太多 raw input 一口氣消化 | 識別最 critical 章節（§1 + §2 + §11）先 quiz，其他章節 deferred |
| First-Principles 缺 Constraints 但 user 急著走 §6 架構 | 拒走 §6，回到 §2 拍板 Constraints |
| Implementer review 直接改 caller's draft（不走 Q&A loop）| Diff caller's draft 識別變動，分類 fact / 答案 / 衝突 |
| POC 寫法 vs Production 寫法混用 | Phase 1 對齊 caller 是 POC 還是 Production scope，後續一致套用 |
| ADO Wiki sanitize 後幾乎全砍 | 預期行為 — 公開化 contract 是 lossy transform，sanitized 版必然薄；caller's draft 是 source of truth |
| Wiki page parent 不存在 | Phase 6b 先 create parent；az 不會 auto-create ancestor |
| 中文化過頭把 industry term 譯成生造詞 | 保留 JWT / OAuth / API / token / WinForm / ONNX / mp4 等 industry-standard term |

## 跟其他 skill 的關係

- **`prd-breakdown`（同 repo）**：拿 prd-create 產出的 PRD.md → 拆 vertical slice → push ADO tasks。Chain：`prd-create` → `prd-breakdown` → ADO
- **`spec` skill（同 repo）**：caller 自家開發 spec workflow（spec.md / plan.md / tasks.md / report.md）。`prd-create` 產出 PRD 作 input；`spec` 是「caller 自身 codebase 開發 spec」不是「產品需求 PRD」
- **`goal-engineer`（同 repo）**：當 PRD 要交 agent 無人值守跑，§13 的執行紀律對齊它的 `references/loop-run-protocol.md`（同一份正典）。分工：prd-create 寫「build 什麼」、loop-run-protocol 寫「agent 怎麼無人值守跑 + 回報」。goal-engineer 本身做的是 generate-and-select dispatch（≠ build-to-spec PRD），兩者 archetype 不同
- 這些 skill 透過 markdown 文件對接，不互相 import

## Important rules

收尾 invariants — 即使前面 step 都讀過，這幾條是核心：

1. **Quiz before fabricate** — 不確定的事一律列為 question 給 user，不擅自 hard-code
2. **First-Principles gate** — Problem / Goal / Non-Goal / Constraints 缺一即停下對齊，不先寫架構
3. **Surface conflicts, don't auto-merge** — implementer review 跟 Constraint 衝突要 surface user，不擅自選邊
4. **Caller's draft is source of truth** — Wiki 是 published copy，single-direction；改要在 caller's draft 後 republish
5. **Sanitization is lossy by design** — 必砍 8 條徹底執行，sanitized 版必然比 source 薄
6. **PAT via env var only** — `AZURE_DEVOPS_EXT_PAT` 環境變數，永不上 argv
7. **POC must have §15 Deviation** — POC 簡化版必須標明偏離 Guideline 的點 + 理由
8. **No Python wrapper** — Claude 透過 Bash 直接 `az`；不寫 / 不召喚 Python helper script
9. **Industry term retain English** — JWT / OAuth / API / token / WinForm / ONNX / mp4 等不譯
10. **Public repo discipline** — 此 skill repo 為 public；fixtures 用 placeholders（無真名 / 真客戶 / 真政治 context）
11. **執行模式分形** — Phase 1 先鎖定「人跑 / agent 跑」，缺則 quiz 不預設；agent-run PRD 的 §13 要帶無人值守執行紀律（對齊 `goal-engineer/references/loop-run-protocol.md`），human-run 不帶

## Acknowledgments

Algorithm 內化（重寫成 prompt，未 vendor）：

- **Caller's PRD authoring Guideline** (caller-supplied) — 15 章結構 + First-Principles 啟動 + POC Deviation pattern
- **caller's `doc_writing.md` 紀律** (caller-supplied) — PRD 撰寫紀律 + 受眾中文化
- **caller's `ado.md` 紀律** (caller-supplied) — 公開化 contract 必砍 8 條 + ADO Wiki 同步工作流
- **Real-world PRD authoring experience** (internal) — Quiz loop / Stakeholder merge / Sanitize-publish pattern 從實戰提煉

Mode β fixture (`example_prd_smart_light_iot.md`) 案例為 generic 辦公室智慧電燈 IoT POC，無 IP 爭議，跟既有 PRD 結構 parallel illustrate。
