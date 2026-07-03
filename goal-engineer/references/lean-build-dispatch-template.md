# `<ADR / feature>` Lean Build Dispatch — `<one-line goal>`

> Self-contained hand-off spec for an **unattended build-to-spec run of a FROZEN spec**. A fresh-session agent runs this **blind**; the human only watches 🟢🟡🔴 notifications and approves at gates. Fill every `<...>`; leave **no `TBD`**(a vague field = an un-runnable spec).
> 🔴 **Entry condition**: this template is only valid AFTER the Frozen Spec Check (SKILL.md) passes — the spec exists, is approved/locked, and every AC is machine-checkable. **This dispatch never adds product decisions**; a gap found mid-run is `SPEC_GAP` → stop-and-ask, not an invitation to improvise.
> 🔴 **Secrets never go in this file**(tokens / keys / passwords / webhook URLs / chat_ids → env or config, always). Operational references (hostnames / paths / service names) are fine in a private/internal dispatch — declare which in §0 **Visibility**(same rule as `dispatch-template.md`).

## 0. Operator contract（先讀 — 這份 dispatch 的憲法）
- **Visibility:** `<private/internal — real infra refs OK as spec | shared/public — must abstract/redact infra refs>`
- **規格主版本(SSOT):** `<approved ADR / doc path / work item>` — 狀態:`<approved / locked,日期>`
- 🔴 **不得重新詮釋規格**:實作疑義一律回 SSOT 查;SSOT 沒答案 = `SPEC_GAP` → 🔴 stop-and-ask,不腦補。
- **「🟢 綠」的定義:** §3 DoD 全勾 **且** §7 驗證指令全綠 — 缺一不可,**不准提前報綠(false completion 是本型 dispatch 的頭號風險)**。

## 1. Scope / non-scope
- **本 run 做:** `<exactly which changes>`
- **明確不做:** `<out of scope — 即使「順手」也不做>`

## 2. Authority boundary（授權邊界）
- **已授權(可自主):** `<repo / files / db / dev|staging 環境,agent 可全權>`
- **stop-and-ask(遇到即停、發 🔴 待人):** `<規格外衝突 / 白名單外新依賴 / 既有資料的修改刪除 / ...>`
- 🔴 **禁止(獨立人工 gate,agent 不得自行續跑):** prod 部署 / prod db migration / merge / `<...>`。staging 驗完 ≠ 可進 prod — **staging → prod 是硬性兩階段**,第二階段永遠是人。

## 3. Implementation checklist / DoD
| # | item | file/component | required change | verification |
|---|---|---|---|---|
| 1 | `<item>` | `<path>` | `<what changes>` | `<test / command>` |
| 2 | ... | ... | ... | ... |

## 4. Risk sections（依規格性質列,只列本 run 真的有的;例:db migration / API 相容 / UI 行為 / 資料安全）
- **`<風險類別>`:** `<徵兆 → 對策 → 驗證方式>`
- **`<風險類別>`:** ...

## 5. Pre-flight gate（fail-fast,任何工作開始前跑、硬擋）
0. **通知測得通**(送測試 ping;失敗 → 不開跑。見 `notify-protocol.md`)。
1. `<runtime / 服務 / 依賴檢查>`
2. `<輸入 / 測試環境(staging / dump)備齊>`
3. `<smoke:最小一項端到端,例如對 dump 空跑一次 migration>`

## 6. Execution procedure（新 session 照這個跑）
1. 讀本 dispatch + SSOT;load state(`<state file>` 存在則 resume,否則 fresh)。
2. 按 §3 checklist 逐項:實作 → 跑該項 verification → 綠才勾,並 append run log 一筆(項次 + 判定 + 原因碼 + delta)。
3. 沒過 → 記原因碼(§9)、照該碼預設動作調整;每輪報 **delta(往 DoD 推進了什麼)**,連 2 輪無 delta → `ESCALATE`。
4. milestone(一批 checklist 項完成)→ 🟢 通知(粒度照 `notify-protocol.md`,不 per-item 洗版)。

## 7. Verification protocol（機器可檢核 — 全綠才算完成）
逐條列**確切指令 + 通過門檻**:
- `<lint / typecheck 指令>` → `<門檻>`
- `<unit / integration / e2e 指令>` → `<門檻>`
- `<build / migration 驗證指令>` → `<門檻>`

**綠 = §3 全勾 + 本節指令全綠**;任何 silent cap(略過的測試 / 抽樣驗證)要明講、別藏。

## 8. Notification（triggers/format SSOT = `notify-protocol.md`）
- **Channel:** `<telegram / discord / slack / imessage / other>`
- **Credential source:** `<env vars / NOTIFY_CONFIG 路徑 — secret 本身不寫在這>`
- **Triggers + format:** per `notify-protocol.md`(pre-flight 測通 · milestone 🟢 · 事故已處理 🟡 · blocked 🔴 · 收工總結)。不在此重定義。
- 每輪 delta 報「往 DoD 推進了什麼」,不是「候選變好了」。

## 9. Failure / stop conditions
- **3 出口:** `NEEDS_INPUT`(缺料 / 缺決策)/ `ESCALATE`(連 2 輪無 delta)/ `REFUSE`(越過 §2 授權)— 全部發 🔴。
- **輪數上限:** `<≤N 輪 / 時間盒>`。
- **原因碼(讓迭代針對性、不亂猜):**

| code | 意思 | 預設動作 |
|---|---|---|
| `TEST_FAIL` | §7 某驗證指令紅 | 修到綠;同一項連 2 輪紅 → `ESCALATE` |
| `MIGRATION_RISK` | 不可逆操作 / 資料毀損徵兆 | 立即停手 → 🔴 stop-and-ask |
| `SPEC_GAP` | SSOT 答不了的實作疑義 | 🔴 stop-and-ask,不腦補、不自己補決策 |
| `AUTH_BOUNDARY` | 下一步需越過 §2 授權 | `REFUSE` + 🔴 |

## 10. Final handoff
- 交付:`<branch + PR / spec 指定的形式>` + run log + §7 驗證報告。
- **人批准 merge / deploy / 接受最終報告** — 不是「人挑候選」。agent 不得自行 merge、不得自行進 prod、不得把「staging 全綠」升級解讀成「可以上了」。

---

## Worked example (abstract — replace with your task)

> **`ADR-042` Lean Build Dispatch — schema migration + classifier rule + settings page toggle, staging-verified**
> - **SSOT:** `docs/adr/042-<name>.md`(approved `<date>`);本 dispatch 不重述決策、只包執行。
> - **Scope:** migration script + rule change + one UI toggle;**不做** prod 部署、不動其他 schema。
> - **Authority:** 可自主 — repo `<X>`、staging db(dump 副本);禁止 — prod、merge。
> - **DoD:** 3 items,each with a test/command in §3。
> - **Risk:** db migration(先對 dump 空跑、驗 row count + rollback script)。
> - **Verification:** `<test suite>` 全綠 + migration dry-run 無 diff 異常。
> - **Stop:** `SPEC_GAP` 或 `MIGRATION_RISK` 即 🔴;≤6 輪。
> - **Handoff:** PR + run log;人審後自己按 merge、自己排 prod migration 時段。
