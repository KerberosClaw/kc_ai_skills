# `<ADR / feature>` Lean Build Dispatch — `<one-line goal>`

> Self-contained hand-off spec for an **unattended build-to-spec run of a FROZEN spec**. A fresh-session agent runs this **blind**; the human only watches 🟢🟡🔴 notifications and approves at gates. Fill every `<...>`; leave **no `TBD`**(a vague field = an un-runnable spec).
> 🔴 **Entry condition**: this template is only valid AFTER the Frozen Spec Check (SKILL.md) passes — the spec exists, is approved/locked, and every AC is machine-checkable. **This dispatch never adds product decisions**; a gap found mid-run is `SPEC_GAP` → stop-and-ask, not an invitation to improvise.
> 🔴 **Secrets never go in this file**(tokens / keys / passwords / webhook URLs / chat_ids → env or config, always). Operational references (hostnames / paths / service names) are fine in a private/internal dispatch — declare which in §0 **Visibility**(same rule as `dispatch-template.md`).

## 0. Operator contract（先讀 — 這份 dispatch 的憲法）
- **Visibility:** `<private/internal — real infra refs OK as spec | shared/public — must abstract/redact infra refs>`
- **規格主版本(SSOT):** `<approved ADR / doc path / work item>` — 狀態:`<approved / locked,日期>`
- 🔴 **不得重新詮釋規格**:實作疑義一律回 SSOT 查;SSOT 沒答案 = `SPEC_GAP` → 🔴 stop-and-ask,不腦補。
- **「任務完成」的定義:** §3 DoD 全勾、§7 驗證通過、§7.1 `doc-qa:qa` 依已核准出口條件通過且有證據，並已執行 §7.2 `align` 後收尾回報。milestone 🟢 只是階段進度，不代表整個任務完成；不得在測試全綠時跳過 QA／文件對齊就報完成。

## 1. Scope / non-scope
- **本 run 做:** `<exactly which changes>`
- **明確不做:** `<out of scope — 即使「順手」也不做>`

## 2. Authority boundary（授權邊界）
- **已授權(可自主):** `<repo / files / db / dev|staging 環境,agent 可全權>`
- **QA 授權:** `<已確認的測試網址／環境、頁面／角色、可拋棄資料範圍、可寫入動作／不可逆動作限制、帳號的安全取得方式>`。正式環境唯讀；測試環境寫入也不能超過這份授權。
- **文件對齊授權:** `<本次可修改文件的 repo>`；跨 repo 引用可唯讀查證，其他 repo 文件飄移只回報，取得 user 明確授權才改。
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
4. 確認 §7.1／§7.2 的兩個完整 skill 與其 references 在執行端可讀，且有實機 QA 所需的瀏覽器能力。缺少依賴就回報，不把名稱當成已安裝，也不自行安裝或以 AC 測試取代 QA。

## 6. Execution procedure（新 session 照這個跑）
1. 讀本 dispatch + SSOT;load state(`<state file>` 存在則 resume,否則 fresh)。
2. 按 §3 checklist 逐項:實作 → 跑該項 verification → 綠才勾,並 append run log 一筆(項次 + 判定 + 原因碼 + delta)。
3. 沒過 → 記原因碼(§9)、照該碼預設動作調整;每輪報 **delta(往 DoD 推進了什麼)**,連 2 輪無 delta → `ESCALATE`。
4. milestone(一批 checklist 項完成)→ 🟢 通知(粒度照 `notify-protocol.md`,不 per-item 洗版)。
5. 實作完成後依序完成 §7 驗證 → §7.1 `doc-qa:qa` → §7.2 `align` → §10 收尾回報。已授權這條無人值守主線，不在每一階段重問要不要繼續；遇 §2／§9 的界線才停。

## 7. Verification protocol（機器可檢核 — AC／測試驗證）
逐條列**確切指令 + 通過門檻**:
- `<lint / typecheck 指令>` → `<門檻>`
- `<unit / integration / e2e 指令>` → `<門檻>`
- `<build / migration 驗證指令>` → `<門檻>`

**本節全綠只代表 AC／測試驗證完成，不能取代以下實機 QA。** 任何 silent cap(略過的測試 / 抽樣驗證)要明講、別藏。

### 7.1 實機 QA：`doc-qa:qa`

- **執行端 skill:** `<doc-qa:qa 的 SKILL.md 可讀位置與版本；保留整個 skill 資料夾>`
- **QA 材料／輸出:** `<spec／需求來源、對應程式版本、測試環境與角色、QA 報告／案例矩陣／截圖的保存位置>`
- 讀取並執行 `doc-qa:qa` 的階段 0–4，依其 references 完成範圍稽核、挖掘、案例、實跑與證據報告。範圍／環境／寫入授權已在本 dispatch 決定的就直接承接；缺少的部分如實標記，不能自選正式環境或修改其資料。
- 保留 `PASS`／`FAIL`／`UNCLEAR`／`BLOCKED`／`NOT RUN` 與 QA 整體狀態、版本、證據邊界。出口沿用已核准需求與 QA 報告契約；不自創覆蓋率、不把「報告產出」等同「QA 通過」。
- QA 本身不修程式。發現缺陷時，由原執行 agent 在 §2 已授權範圍與 §9 次數／時間上限內修正，再跑相關驗證與新一輪 QA，保留前輪證據。需產品決策、越權或已達停止條件時，不改預期結果來求 PASS；如實收尾或回報阻塞。
- 沒環境或案例未跑完，照 skill 出 `尚未實跑`／`部分執行` 報告，不能以單元測試綠燈冒充。若無法繼續 QA，仍可把既有可確認資訊交給 align 整理文件，最終清楚回報未完成項目，不宣稱整條任務成功。

### 7.2 文件對齊：`align`

- **執行端 skill:** `<align 的 SKILL.md 可讀位置與版本；包含 references/criteria.md>`
- **目標 repo:** `<§2 授權修文件的 repo>`；帶入最新 QA 報告與證據位置。
- QA 後讀取並執行 align，檢查整個目標 repo，不只本次 diff；沿引用跨 repo 查證，只修授權 repo 的文件。歷史衝突保留原文加註，已部署環境唯讀；其他 repo 的文件落差列待授權。
- 不改產品程式、原始需求、測試預期或 QA 矩陣的真實結果來消除落差。不確定處與未覆蓋區域如實列出，不為對齊再部署或寫入正式環境。
- 將修訂、歷史加註、查核依據與待確認／待授權項目交給 §10；不另開票、不新增結案狀態或歸檔程序。執行中若發現 skill 不可用，回報未執行及原因，不跳過後仍宣稱完整完成。

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
- 在 QA 與 align 之後，由原執行 agent 統一收尾回報：實作成果與 `<branch + PR / spec 指定的形式>`、run log、§7 驗證報告、§7.1 QA 真實結果／版本與證據入口、§7.2 文件修訂及未確認／外 repo 待授權項目。用既有結果管道，不另建排程。
- 依證據區分完成與仍待處理；未跑 QA、未修缺陷、未執行 align 或尚未覆蓋的區域都不能藏掉。其他 repo 待授權不自動擴張本次修改範圍，也不等於整個任務驗收失敗。
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
> - **QA:** 用 `doc-qa:qa` 在已授權的測試介面／角色實跑並留下矩陣與證據；沒有介面或環境時如實標記，不拿測試全綠代替。
> - **Docs:** QA 後執行 align，只修授權 repo 的文件；外 repo 落差列待授權。
> - **Handoff:** PR + run log + QA 結果 + 文件修訂摘要;人審後自己按 merge、自己排 prod migration 時段。
