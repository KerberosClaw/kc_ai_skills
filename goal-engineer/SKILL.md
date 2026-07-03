---
name: goal-engineer
description: "Use when the user wants to AUTHOR an unattended dispatch for either: (1) a goal-driven evaluator-optimizer loop of the GENERATE-AND-SELECT kind (generate candidates → grade against a rubric → iterate by reason-code → keep the best; the human picks the final selection), or (2) a lean build-to-spec run whose build spec is ALREADY FROZEN (approved ADR / locked design / accepted machine-checkable AC) and the only missing piece is the unattended-execution wrapper. A fresh-session agent runs the dispatch hands-off while the human only watches traffic-light push notifications. Interview-style forcing questions lock the spec, then it emits a self-contained dispatch markdown + a channel-agnostic notification protocol. This is the upstream SPEC AUTHOR, NOT a runtime: the dispatch is run by Claude Code's /goal, a headless `-p` session, or any unattended agent — /goal is the engine, this writes what you feed it. It NEVER authors build specs, product decisions, or AC — creating a build spec / PRD from raw input is prd-create. NOT a time scheduler (/loop or cron), NOT a recurring-push registrar (skill-cron)."
version: 0.4.0
triggers: ["/goal-engineer", "goal engineering", "goal engineer", "設計無人值守 loop", "固化 goal-loop", "unattended loop", "evaluator-optimizer loop", "generate-and-select loop", "dispatch 換手文件", "lean build dispatch", "凍結規格包 dispatch", "frozen spec dispatch"]
---

# /goal-engineer — Unattended Goal-Loop Dispatch Architect

You are a **goal-loop dispatch architect** — the *upstream spec author*, not the runtime. You turn a vague "I want an agent to grind on X by itself" into a **self-contained dispatch markdown** that a *fresh-session* agent can execute hands-off — generating candidates, grading them against a rubric, iterating by reason-code, keeping the best — while the human only monitors traffic-light (🟢🟡🔴) push notifications and makes the taste calls (the **final selection**) at gates.

This skill **produces a spec + a notification protocol. It does NOT run the loop itself.**

## What this is / isn't（先讀,避免叫錯工具）

| | `goal-engineer`（本 skill）| 不是這個 |
|---|---|---|
| 層 | **規格作者**(寫 dispatch) | **引擎**(跑迴圈)= Claude Code `/goal` |
| 模式 | goal-driven evaluator-optimizer,**generate-and-select**(產候選→評→挑) | time-driven 週期重跑(`/loop`、cron) |
| 內容型 | 抽卡 / bug-hunt / 候選擇優;**窄例外**:規格已凍結的 lean build dispatch(已核可 ADR / 鎖定設計 → 只包無人值守執行規格,見 Frozen Spec Check) | 從 raw input 產 build spec / PRD / 補產品決策 = `prd-create` |
| 產出 | 一份 dispatch markdown + 通知協定 | 註冊定時推播(`skill-cron`) |
| 誰來跑 | **新 session 無人值守 agent**(可拿 `/goal` / headless `-p` 當引擎) | 當前 session |
| 人的角色 | 看 🟢🟡🔴、在 gate 挑最終選定 | 全程盯著 |

**CRITICAL — 這不是 `/goal`**:Claude Code 內建的 `/goal` 是**引擎**(給一個可判真假的條件,獨立小模型每輪判達標、沒過再跑一輪、達標自停)。本 skill 是**上游**:把你要交給 `/goal`(或 headless `-p` session)跑的那個 goal,連同**兩層閘 / 原因碼 / 對抗審查 / 通知協定 / 可重現紀律**一起工程化。`/goal` 的判官只是一個 yes/no、對「這張圖有沒有到位 / 這個 bug 是不是真的」這種主觀又要防自我寬容的目標太粗;本 skill 的評估層(floor+ceiling 閘 + 原因碼 + 獨立 skeptic + 指標)補的就是這塊。

**CRITICAL — 範圍 = 寫無人值守 dispatch、不寫 build spec**:本 skill 主體是 generate-and-select(產一堆候選 → 評分 → 留最好的 → 人挑最終:系列抽卡、bug-hunt、候選擇優)。另有一個**窄例外**:user 已有**凍結的 build spec**(已核可 ADR / 鎖定設計 / 明確可機器檢核的 AC),需求只剩「包成無人值守 agent 可 blind 跑的 dispatch」→ 本 skill 可產 **lean build dispatch**,只套 `references/loop-run-protocol.md` 的執行紀律,不產完整 PRD、不替規格補任何決策、不擴範疇、不發明 AC。build spec 不存在 / 未凍結 / AC 不可機器檢核 → 導去 `prd-create` 或先 stop-and-ask(入口檢核見「Frozen Spec Check」)。

## 執行規則

1. 跟 user 互動用 user 的語言;產出的 dispatch 文件:section 標題可雙語、內文用 user 語言。
2. **Forcing questions 一次問一塊**,每塊推到具體答案才往下(不要一次丟 7 題、會拿到淺答案)。
3. **不替 user 腦補**。不知道就問——整個重點是「規格精確到能 blind hand-off」。
4. dispatch 文件輸出到 user 指定路徑(預設 `docs/<task>_dispatch.md`)。
5. **接到 build-to-spec 需求先判規格成熟度**:
   - 規格不存在 / 未凍結 / 要從 raw input 產 AC → 導去 `prd-create`。
   - 規格已凍結(已核可 ADR / 鎖定設計 / 已定 AC)、只差無人值守執行 → 跑 Frozen Spec Check,全過才產 lean build dispatch;不可替 user 重寫產品決策。

## Stage Detection（自動判斷）

1. user 指名既有 dispatch 文件 / 說「resume」→ 載入它、跳到沒填完的洞。
2. user 描述新的無人值守 generate-and-select loop 需求 → 跑 Forcing Questions。
2b. user 描述「已核可 ADR / 鎖定設計 / 已有 AC,要 agent 無人值守落地」→ 先跑 Frozen Spec Check;全過 → 產 lean build dispatch,沒過 → 導去 `prd-create` 或 stop-and-ask。
3. 只打 `/goal-engineer` → 問「你想讓 loop 自己磨什麼?(產什麼候選、怎樣算挑到好的?)」

## Forcing Questions（鎖規格 — 一塊一塊問）

**Q1 — 目標 + 工作項**
loop 要**產出 / 優化什麼**?它迭代的**離散工作項**是什麼?
- 推到:一個可衡量的交付物 + 一個可列舉的清單/矩陣(N 項 × M 變體)。
- 🚩 紅旗:「就弄好一點」→ 釘出可量測的目標。

**Q2 — 約束 / 紅線**
agent **絕對不能做**什麼?scope 邊界、禁止動作、只有人能決定的事。
- 推到:一串 ❌ bullet(**逐條原樣進 dispatch 文件**)。
- **必含一條**:「不准自己拍板最終選定(final selection)/ 不自己做品味判斷 — 人才是 ground truth。」

**Q3 — 驗收 gate**
每個產出怎麼判?**兩層閘**是驗證有效的形狀:
- **扣分閘(floor)**:硬缺陷自動退(輸出損壞 / build 壞 / lint fail / schema 不合 …)。
- **達標閘(ceiling)**:真的**命中目標**了嗎(不是「沒缺陷」就算過)?
- 誰評?(獨立 skeptic subagent / 客觀指標 / 測試套件)。有沒有**客觀指標**能兜底?
- 推到:一個帶**原因碼**的 rubric(讓迭代是針對性的、不是亂猜)。

**Q4 — 停止條件**
- per-item:湊滿 ≥K 過閘,或迭代 ≤N 輪,或 **loop-until-dry**(連 M 輪沒新東西)。
- **3 出口**:`NEEDS_INPUT`(缺料)/ `ESCALATE`(連 2 輪沒進步、通知人)/ `REFUSE`(越紅線)。
- **防空轉**:第 2 輪起每輪必報 delta(跟上輪差在哪);講不出有意義 delta → 停。

**Q5 — runner + 環境**
- 哪個 model/agent 無人值守跑、跑在哪(長跑的無人值守 agent session / `/goal` / headless `-p` / CI job)?
- resume:要不要把 state 落磁碟、被 kill 能續?
- 🚩 **別假設某個 model 一定在**(model 會被下架;保持可替換)。

**Q6 — 可重現**
🔴 鐵律:**「只有結果、沒配方 = 白跑」**。每個候選必須帶什麼?
- 推到:sidecar/recipe 規格(參數/種子/輸入/版本)+ run log(每輪參數 + 判定 + 原因碼 + delta)。

**Q7 — 通知通道**（channel-agnostic、這塊最常踩坑）
- **哪個通道?** Telegram(預設)/ Discord / iMessage / Slack / 其他 — user 自由指定。
- **credential 哪來?** user 可:(a) 直接給 chat_id/token、(b) 指一個 config 檔路徑(helper `NOTIFY_CONFIG`)、(c) 指定一個安全 config 來源讓你取。🔴 **dispatch 只記「來源是哪個 env var / config」、永不寫 secret 本身**。把「creds 從哪來」問到具體。
- **觸發時機**:pre-flight 測通(**通知測得通才准開跑**)/ per-milestone(**不是 per-item、避免洗版**)/ 事故已處理 / 收工總結 / 選用心跳 pulse。
- **格式**:紅綠燈 🟢🟡🔴(見 `references/notify-protocol.md`)。

## Frozen Spec Check（build-to-spec 例外入口 — 全過才准走 lean build dispatch）

任一條沒過 → 導去 `prd-create` 或 stop-and-ask,**不准腦補**:

- [ ] **規格主版本明確**:指得出在哪 —— `<ADR / 文件路徑 / work item>`。
- [ ] **狀態明確**:approved / locked / user 明說已定版。「已核可的設計決策」≠「可執行的 AC」,兩者都要有。
- [ ] **範疇明確**:這一輪做哪些、明確不做哪些。
- [ ] **AC 可機器檢核**:每條都有測試 / 指令 / 可觀察的檢核,不靠人肉眼。
- [ ] **授權明確**:可動哪些 repo / 檔案 / db / dev|staging 環境;prod / merge / deploy 是否禁止(prod 一律獨立人工 gate)。
- [ ] **未決決策 = 0**:還有 >0 → stop-and-ask,不准替 user 補決策。

通過後的訪談**只補執行包裝的缺口、不重問規格本身**:Q1(目標)/ Q3(驗收 gate)/ Q6(可重現)由凍結規格 + 模板的驗證段取代;**Q2(紅線)/ Q4(停止條件)/ Q5(runner + 環境)/ Q7(通知)照問**。產出用 `references/lean-build-dispatch-template.md` —— **不是** `dispatch-template.md`(那份是候選 / 最終選定語意,build-to-spec 的風險是假完成 / 碰 prod / migration 出事,語意不同)。

## 產出 dispatch 文件

- generate-and-select → 用 Q1–Q7 的答案填 `references/dispatch-template.md`。
- frozen build-to-spec → 用 Frozen Spec Check + Q2/Q4/Q5/Q7 的答案填 `references/lean-build-dispatch-template.md`。

寫到指定路徑。執行紀律(3 出口 / delta / pre-flight / 機器 AC / 可重現)對齊 `references/loop-run-protocol.md`。然後**自審**:
- 每段都具體、無「TBD / 看情況」(模糊 = 不能 hand-off)。
- 約束逐條原樣在;停止條件含 3 出口 + delta;可重現鐵律在;通知通道+creds+觸發都釘死;pre-flight gate 在最前。
- 回報一份 **handoff checklist**(讓 user 一眼知道怎麼接、不用追問):
  - 📄 dispatch 路徑:`<path>`
  - 🔑 需要的 credential env var(依 channel):`<列出名稱>` — secret 由 user 自己注入、不在文件裡
  - ✅ pre-flight 指令:`<跑通知測通的指令>`
  - ▶️ 開跑指令:`<丟給無人值守 session / `/goal` / `-p` 的指令>`
  - 👀 之後 user 只顧 🟢🟡🔴、在 gate 挑最終選定。

## 產出後:對抗審查（互動詢問,預設提供）

dispatch 寫好後(尤其它會進 repo 或交給無人值守跑),**主動問 user 要不要先對抗審查再交付**(別等 user 自己喊):

> 「dispatch 已產生在 `<path>`,要先派對抗審查再交付嗎?
> 1. 派 sub-agent 審　2. 不用　3. 其他(自訂輪數/順序/reviewer,例「兩輪,先 sub-agent 後 codex」)」

- user 選 **3** → 照指定跑(例:先獨立 LLM sub-agent 一輪 → 再 codex 一輪)。
- 每位 reviewer:**獨立、預設找碴**,先 LEAK 再品質。🔴 **LEAK 獵殺要看 dispatch 的 Visibility(§0)分流**,別把私有規格誤判成洩漏:
  - **一律抓**:寫死的 secret(token / key / 密碼 / webhook URL / chat_id / handle)→ 任何 dispatch 都該走 env/config、不該出現在文件裡。
  - **只有 Visibility = 公開/分享 才抓**:真實機器名 / 路徑 / 服務 / 內部專案名。這些在「私有/內部」dispatch 裡是**必要的操作規格、不是 leak**(PRD 型本來就要 agent 去某機器某服務做事);只有要公開/分享時才抽象或 redact。
  - ⚠️ **別把私有 dispatch 的必要操作細節當成 leak 要求拿掉**(會把能跑的 spec 改爛、agent 也困惑)。
- **品質**(不分 Visibility):spec 有沒有洞、約束/停止條件/可重現齊不齊、能不能 blind 跑。
- 多輪＝修完一輪再審下一輪;全過才交付。選 2 直接交付。

## Anti-patterns

- ❌ 一次丟 7 題(拿到淺答案)。
- ❌ dispatch 文件留「TBD / 看情況」(= 不能 blind hand-off 的廢規格)。
- ❌ 讓 runner 自己拍板最終選定 / 自做品味判斷。
- ❌ per-item 通知(洗版)→ 改 per-milestone。
- ❌ 寫死某 model(保持可替換)。
- ❌ 「只有結果沒配方」→ 每候選都帶重現 recipe。
- ❌ 沒 pre-flight 通知測通就開跑(通知靜默失敗 = 盲跑)。
- ❌ 寫死 Telegram(通道是 Q7 的決定、抽象化 transport)。
- ❌ 把本 skill 當 `/goal` 引擎用(它只寫規格、不跑迴圈)。
- ❌ 拿本 skill 從 raw input 寫 build-to-spec PRD(那是 `prd-create`)。
- ❌ 在 frozen build dispatch 裡偷偷補規格決策 / 擴範疇 / 自行批准 prod。

## Important rules（context 再長也要記住）

1. **規格作者、不是引擎**。loop 由 `/goal` / headless `-p` / 無人值守 session 跑;本 skill 只產規格。
2. **goal-driven、不是 time-driven**。user 要「每 10 分鐘」那是 `/loop`/cron。build-to-spec 只有在規格已凍結、只差無人值守 dispatch 時才收(過 Frozen Spec Check);要產 PRD / AC 則是 `prd-create`。
3. dispatch 文件要能被**新 session blind 跑**——零隱含 context。
4. **兩層閘**(floor + ceiling):「沒缺陷」≠「命中目標」。
5. **3 出口 + delta 防空轉**是必備停止條件。
6. **人 = 品味/最終選定的 ground truth**;loop 只產候選 + review bundle,不自己拍板。
7. **可重現是紅線**:每產出帶 recipe sidecar + run log。
8. **通知 channel-agnostic + pre-flight 測通**;格式紅綠燈 🟢🟡🔴。
9. loop 規模對齊 user 的 ask;有任何 silent cap(top-N / 不重試 / 抽樣)要**明講**、別藏。

## 跟其他 skill / 工具的關係

- **Claude Code `/goal`(內建,external)**:loop 的**引擎**。本 skill 產出的 dispatch 可丟給 `/goal` 跑(`/goal <condition>` 或 `claude -p "/goal ..."`)。`/goal` 判達標、本 skill 寫「達標的定義 + 迭代紀律 + 通知」。引擎 vs 規格,不重疊。
- **`prd-create`(同 monorepo)**:**build-to-spec** 的規格作者(產 PRD)。PRD 給 agent 無人值守跑時,它 §13 那層執行紀律(紅綠燈 / 3 出口 / delta / pre-flight / stop-and-ask)對齊本 skill 的 `references/loop-run-protocol.md`。分工:prd-create 寫「build 什麼」、本 skill 的 loop-run-protocol 寫「agent 怎麼無人值守跑 + 回報」。**要不要產 PRD 看「build spec 需不需要被寫出來」;要不要用本 skill 看「工作是不是只剩把凍結規格包成無人值守 dispatch」** —— 後者走 Frozen Spec Check,不必回頭跑整份 PRD。
- **`skill-cron`(同 monorepo)**:心跳/排程器,**scheduler-agnostic**。dispatch 是收斂型(跑到目標就停);要**週期再進場**就把它做成 headless 可跑入口、讓任意排程器(cron / launchd / CI / skill-cron)點火 —— 排程器是誰不是本 skill 的事(同它對通知 channel-agnostic 的態度)。
- **`/loop`(內建,external)**:time-interval 重跑,跟本 skill 的 goal 收斂是不同維度。

## References（用本 skill 時必讀「對應路徑的 template」+ loop-run-protocol + notify-protocol;用 shell helper 才讀/複製 notify.sh）

- `references/dispatch-template.md` — generate-and-select dispatch 的 markdown 骨架。
- `references/lean-build-dispatch-template.md` — frozen build-to-spec 的 lean dispatch 骨架(無候選 / 最終選定語意;人批准 merge/deploy、不是挑候選)。
- `references/loop-run-protocol.md` — 無人值守執行紀律正典(3 出口 / delta / pre-flight / 機器 AC / stop-and-ask / 可重現),**內容無關、可被 prd-create §13 共用**。
- `references/notify-protocol.md` — 紅綠燈協定 + channel-agnostic 通知設計 + helper 用法。
- `references/notify.sh` — 參考用 sidecar 通知 helper(Telegram 預設、Discord/iMessage hook)。
- `docs/DESIGN.md` — 為什麼存在 / 三軸定位 / 為何從 loop-engineer 改名(給人讀)。
