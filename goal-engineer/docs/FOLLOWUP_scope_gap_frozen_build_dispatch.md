# FOLLOW-UP — goal-engineer scope gap: frozen build spec → lean unattended dispatch

> **Status**: **applied 2026-07-03**(v0.4.0)— kept as the design-rationale record for the frozen-spec exception. Applied with supplements the original proposal missed: README/README_zh sync, version bump + triggers, forcing-questions mapping for the lean path (Q2/Q4/Q5/Q7 still asked; Q1/Q3/Q6 replaced by the frozen spec), DESIGN.md prose (not just the table, heartbeat row kept), genericized risk sections in the template. Long-term option (extract `unattended-dispatch-engineer`) intentionally NOT taken — default = patch, revisit only if the lean path grows.
> **Origin**: hit in real use — the skill mis-routed a valid request. Root cause + a reviewed fix are below. A second reviewer (codex) independently confirmed the flaw and refined the fix; its concrete edits are embedded.
> **Scope of this task**: edit `goal-engineer` SKILL + references only. No company/internal context needed to do it — this is a pure skill-design fix.

---

## 1. The problem (one paragraph)

`goal-engineer` routes purely on **archetype**: generate-and-select stays; anything "build-to-spec" is pushed to `prd-create`. But there is a real, common case it has no exit for: **a build-to-spec task whose spec is ALREADY frozen** (an approved design-decision doc / locked design / accepted machine-checkable AC), where the *only* missing piece is the unattended-execution wrapper. For that case, forcing a full 15-chapter PRD (`prd-create`) is disproportionate — the AC is already frozen, there is nothing to *author*. Yet the unattended-run discipline that case needs (`references/loop-run-protocol.md`) **lives inside goal-engineer** and is self-described as "content-agnostic, shareable with prd-create §13". So the skill owns the exact tool the case needs, but every routing clause tells that case to go away.

**Concrete trigger**: user had an approved ADR (a small, well-scoped DB-migration + classifier + UI change — spec fully frozen) and wanted an agent to run it unattended (validate on a staging/dump env, human-gate before prod). The skill's clauses forced a redirect to `prd-create`. The team's *actual* established practice was already a lean "goal dispatch" (spec + DoD checkboxes + verify gate + traffic-light + stop-and-ask) — i.e. `loop-run-protocol` wrapped around a frozen build spec, no full PRD. The skill's wording contradicted an existing, working pattern.

## 2. Root cause (the axes)

The skill collapses three independent axes into one:

| Axis | Values |
|---|---|
| **WHAT** | generate-and-select · build-to-spec |
| **SPEC MATURITY** | raw input · **frozen** · partial |
| **RUN MODE** | human-run · unattended agent-run |

The mis-routed case = `build-to-spec + frozen + unattended`. The skill routes on WHAT only, so it sends every build-to-spec (regardless of spec maturity) to `prd-create`.

Sharp principle (use this as the north star for the fix):

> **Whether to produce a PRD depends on whether a build spec needs to be *authored*. Whether to use goal-engineer depends on whether the job is *only* to package a frozen spec into an unattended dispatch.**

## 3. The boundary that keeps this from bloating the skill

The risk of the fix is turning goal-engineer into a catch-all. Prevent that with one hard rule, stated explicitly in the skill:

> **goal-engineer never authors a build spec. It only authors the unattended-run dispatch, and only when the build spec is already frozen.** It may organize DoD / pre-flight / stop-and-ask / notification / verification commands. It may **not** add product decisions, change scope, or invent AC. If the spec is not frozen, or AC is not machine-checkable, or there are unresolved decisions → **stop-and-ask or redirect to prd-create.**

Clean division of labor:
- `prd-create` — from raw/scattered input → a build spec ("decide *what* to build").
- `goal-engineer` — from a frozen spec → an unattended dispatch ("how the agent runs / stops / reports").
- `loop-run-protocol.md` — shared HOW canon (decouple it mentally from generate-and-select; it is content-agnostic).

**Longer-term option (note, don't do now)**: extract a third skill `unattended-dispatch-engineer` that owns the frozen-spec→dispatch path. Short-term, patching goal-engineer is fine because the protocol/template/notify assets already live here. Flag this for the maintainer to decide; default = patch goal-engineer.

## 4. Concrete edits (apply to `goal-engineer/SKILL.md` unless noted)

Reviewer-proposed wording (adapt to current line numbers; genericize any example):

**(a) Frontmatter `description`** — loosen from "generate-and-select only":
```
Use when the user wants to AUTHOR an unattended dispatch for either:
(1) a generate-and-select evaluator-optimizer loop, or
(2) a lean build-to-spec run where the build spec is already frozen
(e.g. approved ADR / locked design / accepted AC) and the only missing piece
is unattended execution discipline.
NOT for creating build specs or PRDs from raw input; that is prd-create.
```

**(b) "What this is / isn't" table row (內容型)**:
```
| 內容型 | generate-and-select；或 frozen-spec build dispatch（已核可 ADR / lock 設計 → 包成無人值守執行規格） | 從 raw input 產 build PRD / 補產品決策 = prd-create |
```

**(c) CRITICAL 範圍段** — replace the "build-to-spec ... 不在本 skill" block with:
```
CRITICAL — 範圍 = unattended dispatch authoring, not build-spec authoring:
本 skill 主要服務 generate-and-select。另有一個窄例外：若使用者已有
凍結的 build spec（已核可 ADR / locked design / 明確 AC），且需求只是
「包成無人值守 agent 可 blind run 的 dispatch」，本 skill 可產 lean build
dispatch，只套 loop-run-protocol.md 的執行紀律，不產完整 PRD、不替 spec 補決策。
若 build spec 未存在 / 未凍結 / AC 不可機器檢核，導去 prd-create 或先 stop-and-ask。
```

**(d) 執行規則 5** — replace with a maturity branch:
```
5. 接到 build-to-spec 需求時先判斷 spec maturity：
   - spec 未存在 / 未凍結 / 需從 raw input 產 AC → 導去 prd-create。
   - spec 已凍結（approved ADR / locked design / accepted AC）且只差無人值守執行
     → 產 lean build dispatch；不可替 user 重寫產品決策。
```

**(e) Stage Detection** — add a branch + a gate:
```
2b. user 描述「已核可 ADR / locked design / 已有 AC，要 agent 無人值守落地」
    → 先跑 Frozen Spec Check；通過則產 lean build dispatch，不通過則導 prd-create
    或 stop-and-ask。
```
New section **Frozen Spec Check** (build-to-spec exception gate — all must pass):
```
## Frozen Spec Check（build-to-spec 例外入口）
只有全部通過才可走 lean build dispatch：
- source of truth 明確：<ADR / path / work item>。
- 狀態明確：approved / locked / user explicitly says 已定版。
- scope 明確：本 run 做哪些、不做哪些。
- AC 可機器檢核：每條都有 test / command / observable check。
- authority 明確：可改哪些 repo/files/db/dev|staging stack；prod / merge / deploy 是否禁止。
- unresolved decisions = 0；若 >0 → stop-and-ask，不准腦補。
```

**(f) Output section** — dual templates:
```
- generate-and-select → references/dispatch-template.md
- frozen build-to-spec → references/lean-build-dispatch-template.md
```

**(g) Anti-patterns** — replace the "❌ build-to-spec PRD" line:
```
- ❌ 拿本 skill 從 raw input 寫 build-to-spec PRD（那是 prd-create）。
- ❌ 在 frozen build dispatch 裡偷偷補 spec 決策 / 擴 scope / 自行批准 prod。
```

**(h) Important rules 2** — replace:
```
2. 不是 time-driven。每 10 分鐘重跑是 /loop /cron。build-to-spec 只有在 spec 已凍結
   且只差 unattended dispatch 時才收；要產 PRD/AC 則是 prd-create。
```

**(i) `docs/DESIGN.md` three-axis table** — stop routing on WHAT alone; split content-authoring from dispatch-authoring:
```
| 內容 spec authoring | 決定 build/generate 什麼 | prd-create for build PRD；goal-engineer for generate-and-select spec |
| unattended dispatch authoring | 把已定義的工作包成 agent 可 blind run 的執行規格 | goal-engineer（generate-and-select；或 frozen build spec 的 lean dispatch）|
| 執行紀律 | 紅綠燈 / 3 exits / delta / pre-flight / machine AC | loop-run-protocol.md |
```

## 5. New file: `references/lean-build-dispatch-template.md`

Do **not** reuse `dispatch-template.md` — it is soaked in candidate / variant / **final-selection** semantics. Build-to-spec risk is "false completion / touching prod / broken migration", not "human picks the best candidate". Give it its own skeleton:

```
# <ADR / Feature> Lean Build Dispatch
## 0. Operator Contract   (SSOT · frozen status · "do not reinterpret spec" · what "green" means)
## 1. Scope / Non-scope
## 2. Authority Boundary   (allowed · stop-and-ask · forbidden)
## 3. Implementation Checklist / DoD   (| item | file/component | required change | verification |)
## 4. Risk Sections   (DB migration · API compat · UI behavior · prod/data safety)
## 5. Pre-flight Gate   (notify test-through BEFORE any work)
## 6. Execution Procedure
## 7. Verification Protocol   (exact commands + pass thresholds; green = all boxes + all commands green)
## 8. Traffic-light Reporting   (🟡 milestones · 🔴 stop-and-ask · 🟢 only when fully verified, never false-report)
## 9. Failure / Stop Conditions
## 10. Final Handoff   (human approves merge/deploy / accepts final report — NOT "picks a candidate")
```

Semantic swaps vs generate-and-select dispatch:
- "human picks final selection" → **"human approves merge/deploy / accepts final report"**.
- reason codes → **`TEST_FAIL` / `MIGRATION_RISK` / `SPEC_GAP` / `AUTH_BOUNDARY`** (not candidate-quality codes).
- delta each round = "what moved toward DoD", not "how candidates improved".

## 6. Pitfalls the fix MUST preserve (reviewer-flagged)

1. **"Approved" ≠ "unattended-ready"**. An ADR may be a design decision, not executable AC. The Frozen Spec Check (4e) is mandatory — it's what stops a lean dispatch being authored on a spec that still needs decisions.
2. **Staging → prod is a hard two-phase split**. A lean build dispatch may authorize only demo/dev/staging. Prod deploy / prod DB migration is an independent **human gate** — the agent must NOT auto-continue past it. Bake this into the template's Authority Boundary + Stop Conditions.
3. **Keep goal-engineer's core intact**. generate-and-select remains the primary path; the build exception is narrow and gated. Don't let the new path leak candidate semantics or vice-versa.

## 7. Acceptance criteria for this follow-up

- [ ] SKILL.md edits (a)–(h) applied; wording matches the frozen-spec boundary in §3.
- [ ] `Frozen Spec Check` section present and referenced from Stage Detection.
- [ ] `references/lean-build-dispatch-template.md` created per §5 (no candidate/final-selection semantics).
- [ ] `docs/DESIGN.md` three-axis table updated (§4i).
- [ ] A blind read of SKILL.md now routes `build-to-spec + frozen + unattended` to a lean dispatch (with the gate), and still routes `build-to-spec + raw` to prd-create.
- [ ] No over-broadening: skill still refuses to author build specs / product decisions / AC.
- [ ] Repo is PR-driven (commits end `(#N)`) — branch → PR, do not direct-push main.
- [ ] Decide (or leave a note for the maintainer): patch goal-engineer now vs extract `unattended-dispatch-engineer` later. Default = patch now.
