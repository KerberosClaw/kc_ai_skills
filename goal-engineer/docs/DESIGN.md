# goal-engineer — 為什麼它不叫 loop-engineer 了

> **English summary:** Design notes for `goal-engineer` (formerly `loop-engineer`). It authors a blind-runnable *dispatch spec* for an unattended, goal-driven evaluator-optimizer loop of the **generate-and-select** kind (produce candidates → grade → iterate by reason-code → human picks the winner). One narrow exception: when a build spec is **already frozen** (approved ADR / locked design / machine-checkable AC) and the only missing piece is the unattended-execution wrapper, it packages a *lean build dispatch* instead of redirecting to a full PRD — gated by the Frozen Spec Check; it still never authors build specs or product decisions. It is the **upstream spec author, not a runtime** — the spec is executed by Claude Code's built-in `/goal`, a headless `claude -p` session, or any unattended agent. Renamed from `loop-engineer` because that name over-claimed the whole "Loop Engineering" idea while the skill only covers the inner, convergent goal-loop; the "loop" word belonged to the engine (`/goal`) and the recurring-heartbeat flavor, neither of which this skill is.

## 這東西在做什麼

把一句模糊的「我想叫 agent 自己去磨 X」變成一份**新 session 能 blind 跑的 dispatch 規格** —— 它產候選、自己依 rubric 評分、依原因碼迭代、留最好的,人只看 🟢🟡🔴 推播、在 gate 挑最終那一個。

它**只寫規格,不跑迴圈**。

## 為什麼改名(loop-engineer → goal-engineer)

原名是個 over-claim。坊間講的 "Loop Engineering"(Addy Osmani 那套)是一整個系統:**心跳(cron)+ work tree + skill + 連接器 + 子 agent + 記憶脊柱**,核心賣點是「靠心跳自動重新進場、持續續跑」。這支 skill 只做其中**內圈那一塊** —— 收斂型的 goal-loop(跑到目標就停),沒有外圈心跳。

掛 "loop-engineer" 這名字,等於替「組合後的完整系統」佔名,結果一看就名實不符(「這比較像 cron job、不像 loop」)。真正的問題不在 skill,在名字:

- 「loop 一直跑」那個印象,招牌該給**引擎**(Claude Code 內建 `/goal`)和**心跳**(任意排程器),不是給「寫規格的人」。
- 這支 skill 的本體是「把要交給引擎跑的那個 **goal**,連同所有紀律一起工程化」。所以 → `goal-**engineer**`,坐在 `/goal` 之上。

而當初會想固化它,其實是因為**同一套規格手寫了三遍**(系列抽卡一次、一份 agent-run PRD 一次、又一次)—— 那個「loop」感長在**人類重複勞動**裡,不在 runtime 裡。固化重複勞動正是 skill 的本職;改名只是把名字擺回正確的位置。

## 四軸定位（叫對工具用)

這支不是一條鏈上的一環,而是四個正交軸的其中兩軸。關鍵是把「內容規格由誰寫」跟「無人值守 dispatch 由誰包」拆開 —— 之前只按 WHAT 路由,漏掉「規格已凍結、只差打包」這格:

| 軸 | 管什麼 | 誰 |
|---|---|---|
| **內容規格**(WHAT) | 決定 build 什麼 / generate 什麼 | `prd-create`(build PRD)、**`goal-engineer`**(generate-and-select 規格) |
| **dispatch 打包** | 把已定義的工作包成 agent 可 blind 跑的執行規格 | **`goal-engineer`**(generate-and-select;或凍結 build spec 的 lean dispatch,Frozen Spec Check 把關) |
| **執行紀律**(HOW,給 agent 跑) | 紅綠燈 / 3 出口 / delta / pre-flight / 機器 AC / stop-and-ask / 可重現 | `references/loop-run-protocol.md`(內容無關、可共用) |
| **心跳**(WHEN,選用) | 要不要週期再進場 | 任意排程器(cron / launchd / CI / skill-cron) |

判準一句話:**要不要產 PRD,看「build spec 需不需要被寫出來」;要不要用 goal-engineer,看「工作是不是只剩把凍結規格包成無人值守 dispatch」。**

## 跟容易搞混的東西劃界

- **vs Claude Code `/goal`(引擎)**:`/goal` 給條件、每輪用獨立小模型判達標、達標自停 —— 它**跑迴圈**。本 skill **寫規格**(達標的定義 + 兩層閘 + 原因碼 + 對抗審查 + 通知),產出可丟給 `/goal` 跑。`/goal` 的判官是單一 yes/no、對主觀目標太粗;本 skill 的評估層補的就是這塊。
- **vs `prd-create`(build-to-spec)**:要**從 raw input 寫出 build spec**(產 PRD、補產品決策、定 AC)—— 那是 prd-create,本 skill 不碰。它的 §13 Test Strategy 在 agent-run 時,執行紀律對齊本 skill 的 `loop-run-protocol.md`(同一份正典)。**窄例外**:build spec 已凍結(已核可 ADR / 鎖定設計 / AC 可機器檢核)、只差無人值守打包 → 本 skill 出 lean build dispatch(SKILL.md「Frozen Spec Check」六條全過才放行),不必為一個已經拍板的決策回頭跑整份 PRD;dispatch 只包執行紀律,一樣不補任何規格決策。
- **vs 心跳 / cron / skill-cron**:本 skill 的 dispatch 是**收斂型**(跑到目標就停),不是週期重跑。要週期再進場,把 dispatch 做成 headless 入口、交任意排程器點火 —— **scheduler-agnostic**,就像它對通知 **channel-agnostic** 一樣,不寫死哪個排程器。

## 收斂 vs 週期(為什麼「沒有循環續跑」不是缺點)

這支真正服務的活(抽卡、bug-hunt、候選擇優)全是**收斂型**:跑到命中目標就收工,不是每天醒來重跑。所以「沒有循環續跑」不是缺口 —— 是這類活本來就該收斂。週期續跑是**另一種 use case**(每日掃資料、盯新文),需要時加一層心跳即可,不是本 skill 的核心。
