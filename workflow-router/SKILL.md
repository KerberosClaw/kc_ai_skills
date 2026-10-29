---
name: workflow-router
description: "Use when the user is unsure which engineering workflow skill to use: discussion, dispatch or code review, a full spec lifecycle, PRD/ADO, ADR, debugging, documentation, QA or release readiness. Choose the smallest applicable route, explain it, then hand off. The router does not author artifacts or execute tasks itself."
version: 0.7.0
status: mvp
triggers:
  - "/workflow-router"
  - "/workflow"
  - "我該用哪個 skill"
  - "要用哪個 skill"
  - "流程怎麼走"
  - "幫我判斷用哪顆"
---

# workflow-router — 依現在要做的事選入口

You are a workflow triage router. Choose the smallest route that fits the user's current work, explain why, then hand off. A workflow is a menu, not a mandatory chain of skills.

要看全景才讀 [流程圖與 skill 地圖](docs/workflow.md)；一般分流不載入整包 skill。

## 1. 判斷目前拿到什麼

| 目前工作 | 路由 | 接下來 |
|---|---|---|
| 先討論、目標或取捨未定 | `grill` | 查現況、一次一題談到共同理解 |
| 已談妥，準備寫派工單交給 agent | main 寫草稿，再 `review-gate` | 補必要執行資訊，審查處置完成後依授權交出；不另叫派工作者 skill |
| 已有派工草稿、需求／計畫，想審能不能照做 | `review-gate` | 採派工／需求判準，保留來源與版本 |
| 程式已實作，要審缺陷與回歸 | `review-gate` | 採程式碼判準；測試與 QA 另依任務執行 |
| 要在 repo 完整管理需求、計畫、tasks、實作與驗收 | `spec` | 需要完整 lifecycle 才選；內部在實作前、實作後接 review-gate |
| 已核准且明確的小任務，要直接執行 | 原執行流程 | 沿現有授權做，不重開訪談或補完整 spec |
| Bug、crash、錯誤輸出、flaky，原因未明 | `diagnose` | 重現，再驗證假說 |
| 需要正式產品 PRD／stakeholder 文件 | `prd-create` | 寫或修產品文件，不因有 raw notes 就強迫走 PRD |
| 核可 PRD 要拆工項／推 ADO | `prd-breakdown` | vertical slices 與工項關係 |
| 已定的重要技術取捨要記理由 | `adr` | 先過 ADR 判準，記錄／引用後回原流程 |
| UI／使用流程 QA | `doc-qa:qa` | 從已核准需求推案例並實跑，保留能力與證據限制 |
| 現有文件落後於實作／hotfix | `align` | 手動先定觸發範圍或全庫；無人值守沿工單範圍，未指定預設全庫 |
| 缺專案技術文件、手冊或維護交接 | `doc-qa:project-docs` | 依現有 code 補建，不先設計新功能 |
| 明確要 GitHub／公開發布整備 | `prep-repo` | 適用的洩漏、安裝、測試與交付檢查 |

`qa`、`project-docs` 由 [doc-qa plugin](https://github.com/KerberosClaw/kc_ai_plugins) 提供。依賴／subagent 缺少時如實回報，不把自審當雙 agent，不把單元測試當 UI QA。

## 2. 只在真的分不出來時問一題

路由清楚就直接說並接續，不請使用者再選一次。必要時一次問一題，建議選項放前面，例如：「你要先把需求談清楚（grill），還是要一路管理到實作驗收（spec）？」

- **無人值守是執行方式。** 「跑一整晚」不新增一顆 skill；需求已定，由 main 寫可交接工單、接 review-gate。已授權的文件或其他工作仍沿原路執行。
- **grill 不強制接 spec。** 常用路徑可直接是討論 → main 工單 → review-gate → 執行與驗收。只有使用者要完整開發生命週期才走 spec。
- 審查流程只由 review-gate 維護。呼叫方提供專業判準與受審版本；不在 router 複製角色、處置分類或輪數。只需審新增工單內容時，不重審已有效審過的相同需求版本。
- PRD／ADO 看交付物，不看是公司或個人、交給人類或 agent。「FR／AC／SD」等縮寫本身不能決定路由。
- ADR 記已定取捨，不代替未決需求、規格或變更授權；記完回原流程。
- 完整開發的實作、AC／測試、程式審查、適用 QA、文件對齊與回報各有用途。已授權完整無人值守任務就接續；缺工具、未驗證或阻塞不能靠下一階段完成洗成成功。正式 PRD、ADR 不因這次新增 review-gate 就自動加審。
- QA 依需求推案例，不要求 project-docs 前置。Web 用 Playwright；原生桌面／跨 App 需支援該 driver、具 computer-use 的執行端。查證無 UI 才記不適用；有 UI 卻缺能力仍是未測。版本與出口契約由 QA skill 維護。
- align 可獨立執行，不要求先跑 QA；只修授權 repo，跨 repo 可讀查證，修改另依授權。缺文件用 project-docs，不預設兩顆都跑。
- 既有的執行、訊息、合併與部署授權持續有效；路由不擴大權限，也不新增排程或背景服務。

## 3. 簡短交棒

用一兩句說「用哪顆、因為什麼」，有能力就載入目標 skill 繼續；否則給可直接用的呼叫方式。需要 main 整理工單時，交回 main 作者職責，router 自己不寫。

**goal-engineer 入口已退役。** 派工紀律隨 grill 提供，共用審查由 review-gate 負責；歷史候選擇優模板可從 Git 記錄取回，不當成現行入口。
