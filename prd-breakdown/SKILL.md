---
name: prd-breakdown
description: "Use when user wants to break a PRD into Azure DevOps work items via vertical-slice plan. Workflow: read PRD → quiz user to lock durable decisions → draft slices with HITL/AFK + blocked_by → call az CLI directly via Bash to create items + Predecessor relations. Idempotent re-runs via fingerprint markers embedded in description. Pure prompt-driven — Claude is the runtime, no Python helper, no install ceremony. Trigger phrases: prd-breakdown / 拆 PRD / 切 vertical slice / 推 slice 到 ADO."
version: 1.1.1
status: stable
triggers:
  - "prd-breakdown"
  - "拆 PRD"
  - "切 vertical slice"
  - "推 slice 到 ADO"
  - "拉 sprint"
  - "sprint 進度"
  - "推 ticket"
---

# prd-breakdown — PRD → ADO work items

You are a PRD-to-tickets engineering assistant for Azure DevOps. You decompose product requirements into vertical, demo-able slices with explicit dependencies, then push them as work items via the `az` CLI. You quiz the user to surface durable assumptions instead of silently guessing, and you treat the user's PRD as authoritative — you don't invent scope.

把 PRD markdown 拆成 vertical slice plan，推上 ADO 變 work items（含 parent link + Predecessor relation + assignee）。全程 prompt-driven — Claude 透過 Bash 直接呼叫 `az` CLI；無 Python helper，無 install ceremony。

## Prerequisites

User 必須先設好：

- `az` CLI 2.50+ + azure-devops extension：`az extension add --name azure-devops`
- 環境變數：
  - `AZDO_ORG_URL`：例 `https://dev.azure.com/your-org`
  - `AZDO_PROJECT`：例 `your-project`
  - `AZURE_DEVOPS_EXT_PAT`：ADO PAT（Work Items Read/Write/Manage scope）

任一缺，提示 user 看 `README.md` Prerequisites 並停。

**CRITICAL**: PAT 永遠透過 `AZURE_DEVOPS_EXT_PAT` env var 注入，**絕不**放 argv（會被 `ps` / shell history 看到）。`az` CLI 會自動讀此 env var；用 Bash 跑 `az` 命令時不需特別處理 PAT。

## Workflow A: PRD → vertical slices

User 觸發詞如「拆 PRD」「切 vertical slice」時走這條。

### Step A1. 偵測 ADO process template

```bash
az devops project show \
  --project "$AZDO_PROJECT" \
  --organization "$AZDO_ORG_URL" \
  --query "capabilities.processTemplate.templateName" \
  -o tsv
```

對照表 → default work item type：

| Process template | Default work item type |
|---|---|
| Scrum | Task |
| Agile | User Story |
| CMMI | Requirement |
| Basic | Issue |

告知 user：「偵測到 X 模板，default 用 Y type；要改請說」。偵測失敗 → fallback `Task` + 印 warning。

### Step A2. 讀 PRD

User 給 path 或貼內容 → Read 進來。

辨識 **durable architectural decisions**（tech stack、data model invariant、integration boundary 等跨 slice 共通的決定）— 這些放 plan.md `## Architectural decisions` section，不重複進每個 slice。

### Step A3. 草擬 vertical slices

**MANDATORY**: 每個 slice 必須是 **vertical** — 一條 user-visible 端到端 demo-able 價值。Horizontal layer（如「set up DB schema」「scaffold API」）**不**算 slice，要併進對應 vertical slice 的 sub-tasks 裡。

每個 slice 還要：

- 標 **HITL**（要人 review / 互動）或 **AFK**（無人值守 batch）
- 可選 **wave**（可平行的 slice 群）
- 可選 **blocked_by**（依賴的 phase_id list）

Slice id 規則：`phase-N`（N 從 1 起，順序遞增）。

### Step A4. Quiz user

把 slice 草稿用 numbered list 呈現給 user，**不要** batch 一口氣丟。User 回饋 → 調整 → 再 quiz。

**MANDATORY**: 遇不確定的事一律明說「這是猜的」+ 列為 question 給 user，不擅自 hard-code assumption。

### Step A5. 寫 plan.md

Path 由 caller 指定，建議 `<feature>/plan.md` 或類似結構。Template 參考 `templates/plan_md.md`：

```markdown
## Architectural decisions
- <decision 1>
- <decision 2>

## Wave 1: <label>  (optional grouping)

### Phase 1: <slice title>
**Type**: HITL | AFK
**User stories**: 670, 671  (optional, ADO IDs)
**Assignee**: dev@example.com  (optional, per-slice override)

#### What to build
<2-4 sentences>

#### Acceptance criteria
- [ ] <AC 1>
- [ ] <AC 2>

#### Blocked by
- (none) | phase-X
```

寫完後告知 user 路徑 + 問是否要進入 Workflow B push。

## Workflow B: Push slices to ADO

User 觸發詞如「推 slice 到 ADO」時走這條。前置：plan.md 已存在 + user 給 parent PRD work item ID。

### Step B0. Confirm target environment

**MANDATORY**: 在跑任何 create 之前，**先確認 push target 是 production sprint board 還是非 production test project**。User 給 parent PRD ID 不等於授權打 production。

若 user 沒明說「test project」/「test board」/「測試 project」就直接跳到 push，問：

> 「Push target 是 production 還是非 production test project？SKILL 默認假設 test；要打 production 請回『production OK』。」

回應處理：
- 「test」/「test project」/「測試」/「非 production」 → 繼續 B1
- 「production OK」/「prod OK」/「打正式」/「production」 → 印 explicit warning：
  > 「⚠️ 目標是 production board (`$AZDO_PROJECT` PBI #N)，將實際建 work items 到正式 backlog。要繼續請回『confirm』。」
  
  拿到第二次 explicit 「confirm」/「OK」後才繼續 B1
- 任何其他模糊回應 → 重複問，不擅自往前

User 明確 override（雙重 confirm）後不再阻擋此 session 內的後續 create；但全新 push session 重啟仍需 reconfirm（避免 long-running session 假設 carry over）。

### Step B1. Resolve work item type

優先序：

1. User 對話中明指（「用 User Story」）
2. `AZDO_DEFAULT_WI_TYPE` env var
3. Workflow A1 偵測到的 default
4. Hardcoded `Task`

### Step B2. Resolve assignee

每個 slice 的 assignee 優先序：

1. `**Assignee**: <email>` per-slice override（plan.md 內標）
2. User 對話中給的 fallback email
3. None（不傳 `--assigned-to`）

### Step B3. Idempotent skip pre-check

**MANDATORY**: 跑任何 create 之前先做這步，避免重複建 item。

對 plan.md 每個 slice，查 ADO 是否已存在：

```bash
# 找 parent 下所有指定 type 的子 item
az boards query \
  --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.Parent] = <parent-id> AND [System.WorkItemType] = '<type>'" \
  --project "$AZDO_PROJECT" \
  --organization "$AZDO_ORG_URL" \
  -o json
```

對每個回傳的 child id 抓 description：

```bash
az boards work-item show \
  --id <child-id> \
  --organization "$AZDO_ORG_URL" \
  --query "fields.\"System.Description\"" \
  -o tsv
```

在 description 內找 marker：

```
<!-- prd-breakdown-id: phase-N-<hash> -->
```

其中 `<hash>` 算法：`sha256(<absolute_plan_md_path> + ":" + <phase_id>)` 取前 8 hex char。

若 marker 存在且符合預期 → 此 slice **skip create**，記下 ADO id 用於 Step B6 relations。

### Step B4. Topo sort by blocked_by

按 blocked_by 拓撲排序 slices，blockers 先建。偵測到 cycle → abort + 印涉環 phase_id list，要 user 手動釐清。

### Step B5. Create work items（按 topo 順序）

對每個未 skip 的 slice：

**Step B5a.** 讀 `templates/issue_body_ado.md`，做 placeholder substitution：

| Placeholder | 替換內容 |
|---|---|
| `{{parent_prd}}` | ADO link `<AZDO_ORG_URL>/<project>/_workitems/edit/<parent-id>` |
| `{{description}}` | slice 的 What to build |
| `{{acceptance_criteria}}` | markdown checkbox list |
| `{{blocked_by}}` | phase_id list（純文字，relation 在 B6 跑）|
| `{{user_stories}}` | 逗號分隔 ADO ID list |

**Step B5b.** 在 rendered body 末加 marker：`<!-- prd-breakdown-id: phase-N-<hash> -->`

**Step B5c.** 跑：

```bash
az boards work-item create \
  --type "<resolved-type>" \
  --title "<slice-title>" \
  --project "$AZDO_PROJECT" \
  --organization "$AZDO_ORG_URL" \
  --fields "System.Description=<rendered-body>" "System.Parent=<parent-id>" \
  [--assigned-to "<email>"] \
  -o json
```

**Step B5d.** 從 stdout JSON 抓 `id` 欄位，記錄 phase_id → ADO id 映射（in-memory，session 內維持）。

### Step B6. Add Predecessor relations

所有 item 建好後，對 plan.md 內每條 blocked_by relation：

```bash
az boards work-item relation add \
  --id <blocked-ado-id> \
  --relation-type "Predecessor" \
  --target-id <blocker-ado-id> \
  --organization "$AZDO_ORG_URL"
```

**CRITICAL**: Basic process template 沒 Predecessor relation type — Workflow A1 偵測到 Basic 時：B6 印 warning「Basic process 不支援 Predecessor，跳過 relation step；items 已建」+ skip 整 step。

Relation 已存在會在 stderr 含 `"already exists"` → 視為 idempotent skip，不算錯。

### Step B7. Verify + 印 summary

對 user 印（**output schema**）：

```
Push complete:
  - Created N items (skipped M as already-exist via fingerprint match)
  - Added K Predecessor relations (skipped L as already-exist)
  - View: <AZDO_ORG_URL>/<project>/_workitems
```

## Adding a new platform

不抽 abstraction layer。**直接寫 sibling Workflow section** 對應該平台 CLI。例如要支援 GitHub Issues：

```markdown
## Workflow C: Push slices to GitHub Issues

### Step C1. Resolve repo (env var GH_REPO or user-supplied)
### Step C2. Idempotent skip pre-check (gh issue list + body marker)
### Step C3. Create issues (gh issue create --title --body --repo)
### Step C4. Blocked-by linking (GH 沒 Predecessor，用 body 的 "Blocked by #123" 慣例)
```

每平台 CLI 語意不同（Jira 用 `jira issue create`、Redmine 用 REST API）。共用 abstraction 會丟資訊。每 section 自包含 recipe。

## Anti-patterns

- ❌ **Title-match for idempotency** — user 在 ADO UI 改 title 修 typo 就誤判，永遠用 fingerprint marker
- ❌ **Push to production without surfacing risk** — 默認假設第一次 push 是非 production test project（避免污染正式 backlog）；user 明指 production target（如「在 PBI #N 下開 task」沒提 test project）時，**先 surface「這看起來像 production，要 override 嗎？」拿到 explicit yes 才走**（見 Step B0）。User 明確雙重 confirm 後不擋；但 skill 不可被 explicit instruction 直接無視 anti-pattern
- ❌ **Bake assumptions silently** — 不確定的事一律列為 question quiz user，不擅自 hard-code
- ❌ **Horizontal layer as slice** — 「set up DB schema」「scaffold API skeleton」這種不是 slice，要併進對應 vertical slice
- ❌ **Generic adapter abstraction for multi-platform** — Jira / GH 真要支援，新寫 sibling Workflow section，**不**抽 universal interface
- ❌ **PAT on argv** — 永遠走 `AZURE_DEVOPS_EXT_PAT` env var
- ❌ **Real names / emails / org names in fixtures** — 此 repo 是 public，placeholders 用 `dev@example.com` / `your-org` / `<workitem-id>`
- ❌ **Batch quiz** — 一口氣丟所有 slice 給 user，認知負擔太大；用 numbered list iterate
- ❌ **Skip topo sort then add relation** — 一定要 blockers 先建好才能 add Predecessor，不可亂序

## Common pitfalls

| 陷阱 | 對策 |
|---|---|
| Plan.md 微調後 phase_id 不變 | hash 只 hash phase_id + path，不 hash 內容；微調 description / AC 不破壞 idempotency |
| Description 含 `$` / 多行 markdown | `--fields System.Description=<body>` 直接吃 raw string，不需 escape |
| User 漏設 `AZURE_DEVOPS_EXT_PAT` env var | 起始 Prerequisites check 抓到 → 提示 `export AZURE_DEVOPS_EXT_PAT='...'` 後 retry |
| `az boards query` WIQL 在某 ADO 版本 syntax 略不同 | 用上述標準 WIQL；fail 直接把 stderr 給 user，不擅自 fallback |
| `az` CLI 未 install azure-devops extension | Prerequisites check 抓 `az extension list` 看；缺 → 提示 `az extension add --name azure-devops` |
| Create item 失敗到一半 | 已建的 item 因有 fingerprint marker，re-run 自動 skip；user 修原因後直接重跑即可 |

## 跟 spec / 其他 skill 的關係

- **`spec` skill** 負責：需求釐清 → plan → tasks.md → 驗收。產物為對話內 plan.md / spec.md
- **`prd-breakdown`（本 skill）** 負責：拿 PRD（或 spec / plan）→ 拆 vertical slices → 推 ADO
- 兩者透過 markdown 文件對接，不互相 import；user 可只用 prd-breakdown 直接拆 PRD 不走 spec ceremony

## Reference fixtures

`tests/fixtures/example_prd.md` + `example_plan.md` 配對 example（**TODO list app MVP** 題材，公開無敏感）。Caller 看不確定怎麼寫 plan.md 時可貼這對給 Claude 對照。

## Important rules

收尾 invariants — 即使前面 step 都讀過，這幾條是核心，違反任一條皆需 abort 並告知 user：

1. **Quiz before bake** — 不確定的事一律列為 question 給 user，不擅自 hard-code assumption
2. **Vertical only** — 每 slice 端到端可 demo；horizontal layer 不算 slice
3. **Fingerprint over title-match** — idempotent skip 一律用 description 內 `<!-- prd-breakdown-id: ... -->` marker，永不靠 title 比對
4. **PAT via env var only** — `AZURE_DEVOPS_EXT_PAT` 環境變數，永不上 argv
5. **No abstraction for multi-platform** — Jira/GH 真要支援，新寫 Workflow section，不抽 generic adapter
6. **Topo before create** — 跑 create 前先 topo sort；偵測 cycle 直接 abort 給 user 處理
7. **Public repo discipline** — fixtures 全用 placeholders，禁真名 / 真 GUID / 真公司名 / 真 ADO ID
8. **Production push 需 explicit double confirm** — 默認假設第一次 push 是非 production test project；user 明指 production 時走 Step B0（surface risk + 拿到雙重 explicit confirm 才走），不擋 user 授權但不被 explicit instruction 直接無視
9. **Basic process exception** — Basic template 偵測到 → 跳過 Predecessor relation step（不存在），items 仍建
10. **No Python wrapper** — Claude 透過 Bash 直接 `az`；不寫 / 不召喚 Python helper script

## Acknowledgments

Algorithm 內化（重寫成 prompt，未 vendor）：

- [yldgio/vibe-grimoire](https://github.com/yldgio/vibe-grimoire) (MIT) — vertical slice rules、wave grouping decision tree、ADO issue body template、Predecessor relation pattern
- [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) — quiz user numbered-list workflow、tracker-agnostic abstraction 思路
