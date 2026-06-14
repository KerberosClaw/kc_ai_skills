# `<task>` Dispatch — `<one-line goal>`

> Self-contained hand-off spec for an **unattended evaluator-optimizer loop**. A fresh-session agent runs this **blind**; the human only watches 🟢🟡🔴 notifications and picks at gates. Fill every `<...>`; leave **no `TBD`** (a vague field = an un-runnable spec).
> 🔴 **Secrets never go in this file** (tokens / keys / passwords / webhook URLs / chat_ids / handles → env or config, always). **Operational references** (hostnames / paths / service & internal-project names) are *fine in a private/internal dispatch* — that's the spec, a PRD-type loop legitimately tells the agent which machine/service to hit — but become a **leak if the dispatch is shared/public**, so abstract or redact them then. Declare which in §0 **Visibility**.

## 0. Goal & scope
- **Visibility:** `<private/internal — real infra refs OK as spec | shared/public — must abstract/redact infra refs>`
- **Goal:** `<measurable target — what "done/good" means>`
- **Scope this run:** `<exactly which items; what is explicitly out>`

## 1. Architecture / runner
- **Runner:** `<model/agent, kept swappable — do not hardcode a model that may be deprecated>`
- **Where:** `<unattended host/session, e.g. a long-running agent session or a CI job>`
- **Dispatched how:** `<command/entry the human runs to kick it off>`
- **Resume:** `<persist state to disk so a killed run continues? where (e.g. state.json)?>`

## 2. Inputs (ready / to-prepare)
- ✅ `<asset/data already in place — relative path preferred>`
- ⏳ `<asset still to prepare, and by whom>`

## 3. Work items (matrix)
`<the enumerable list the loop iterates over — N items × M variants>`

| item | variant A | variant B |
|---|---|---|
| `<item1>` | ✔ | ✔ |

## 4. Constraints / hard lines（逐條 verbatim 進 runner prompt）
- 🔴 `<forbidden action / scope guard>`
- 🔴 **Do not self-approve the final selection / do not make subjective approval calls — the human is ground truth.** Produce candidates + a review bundle, hand off.
- 🔴 `<reproducibility / safety / privacy red line>`

## 5. Evaluation / gates（怎麼判每個 candidate）
- **Floor gate（扣分閘，硬缺陷自動退）：** `<auto-reject defects — invalid/broken output, fails a hard check>`
- **Ceiling gate（達標閘，真的命中目標嗎）：** `<positive criterion that means it HITS the goal — not just "no defect">`
- **Grader：** `<who/what judges — an independent skeptic subagent (default-refute) / a test suite / an objective metric>`；能量化就加客觀指標兜底。
- **Reason-codes（讓迭代針對性、不亂猜）：**

| code | 意思 | 預設動作 |
|---|---|---|
| `<R1>` | `<what failed>` | `<how to adjust next round>` |
| `<R2>` | ... | ... |

## 6. Stop conditions
- **per-item:** hit **≥K** passing, OR iterate **≤N** rounds, OR **loop-until-dry** (M consecutive rounds with nothing new) — first to fire wins.
- **3 exits:** `NEEDS_INPUT` (missing material) / `ESCALATE` (no progress 2 rounds → notify human) / `REFUSE` (crosses a red line).
- **anti-spin:** from round 2, every round states a **delta** vs last; no meaningful delta → stop.

## 7. Reproducibility（鐵律：只有結果、沒配方 = 白跑）
- 🔴 every candidate carries a **`.recipe` sidecar** (`<params/inputs/versions/...>`).
- 🔴 a **run log** per round: params + verdict + reason-code + delta.
- a milestone notification carries enough handle (`<item id / batch / round>`) for the human to map a pick back to its recipe.

## 8. Notification（triggers/format SSOT = `notify-protocol.md`）
- **Channel:** `<telegram / discord / slack / imessage / other>`
- **Credential source:** `<which env vars (e.g. TELEGRAM_BOT_TOKEN+TELEGRAM_CHAT_ID); where the secret lives — a private config / NOTIFY_CONFIG path. The secret itself is NOT written here.>`
- **Triggers + format:** per `notify-protocol.md` (pre-flight test · per-milestone 🟢 · 🟡 incident-handled · 🔴 blocked · finish summary). Do not redefine here — reference it.

## 9. Pre-flight gate（fail-fast，最前面跑）
0. **Notification test passes** (send a test ping; `notify.sh` returns non-zero on failure → do not start the loop).
1. `<runtime/service ready check>`
2. `<inputs present + required tools available (curl / python3 / ...)>`
3. `<smoke 1 item end-to-end before the full matrix>`

## 10. Execution procedure（per-item loop — 新 session 照這個跑）
1. Load state (resume if `<state file>` exists, else fresh) + read this dispatch.
2. For each work item × variant:
   a. **Generate** a candidate (write a *draft* `.recipe` now — a crash still leaves a reproducible artifact).
   b. **Floor gate** → fail: log reason-code, apply the code's default action, retry (respect ≤N).
   c. **Ceiling gate** → fail: log reason-code, adjust, retry.
   d. **Pass** → finalize the `.recipe` + append run log.
   e. Check **stop conditions** (≥K / ≤N / dry / delta); hit an exit → handle (`NEEDS_INPUT`/`ESCALATE`/`REFUSE`).
3. On milestone (a batch/phase done) → 🟢 notify (+ review bundle if media).
4. On finish → assemble review bundle, 🟢 summary notify, hand candidates to the human.
5. 🔴 Never self-select the final selection — that's the human's call.

## 11. Fallback
- `<if approach A fails (e.g. the primary producer refuses / a gate never passes), what is plan B>`

---

## Worked example (abstract — replace with your task)

> **`bug-hunt` Dispatch — find & verify real bugs in module `<X>`, 0 false positives**
> - **Goal:** ≥5 confirmed, reproducible bugs, each with a failing test.
> - **Runner:** a general agent on a long-running unattended session; resumes from `state.json`.
> - **Work items:** files in `<X>/` × {correctness, edge-case, concurrency} lenses.
> - **Constraints:** 🔴 don't "fix" anything — report only. 🔴 don't self-mark a bug "real" — an independent skeptic verifies. 🔴 human triages the final list.
> - **Evaluation:** floor = reproduces on current HEAD; ceiling = a *minimal failing test* exists. Grader = independent skeptic subagent, default-refute. Reason-codes: `NOREPRO`→drop, `FLAKY`→stabilize, `KNOWN`→dedup.
> - **Stop:** ≥5 confirmed OR 8 rounds OR 2 dry rounds.
> - **Reproducibility:** each finding → `.recipe` (file:line, repro steps, test snippet) + round log.
> - **Notification:** telegram (creds from `NOTIFY_CONFIG`); 🟢 per finding-batch, 🔴 ESCALATE if 2 dry rounds.
