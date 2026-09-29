# HANDOFF — kc_ai_skills 維護接手

> 給接手繼續整理這個 repo 的 agent。讀這份就知道現況＋剩餘工項＋紅線。
> 建立：2026-07-15；更新：2026-07-30（frontmatter 一致性 + 第二輪 pattern lint 已收）。

## 2026-07-30 歷史快照

以下 24 顆與全數一致性是當日盤點，不是現行數量；新增 skill 後請以各根目錄 SKILL.md 與雙語 README 索引核對。

- 24 顆 skill、public、MIT、雙語 README（`README.md` + `README_zh.md`）。
- **Frontmatter 已全數一致**（原 handoff 的三個待辦已於 #23 收）：24 顆全有 `version` / `status` / `triggers`；triggers 全為 YAML block list；status↔version 語意對齊（`stable` = 1.0+、`mvp` = 0.x）。
- **第二輪 pattern lint 已收**：補齊 anti-patterns / Important rules 缺口（ctf-kit / job-scout / llm-benchmark / repo-scan / skill-cron / prep-repo / spec / md2pdf），補對稱 routing 指路（rewrite-tone↔rewrite-tw、adr、diagnose）。
- adr / diagnose / grill 三顆從 mattpocock/skills 內化重寫，是這批的 canonical 範本。

## 剩餘工項（判斷後刻意不做的，接手者要動再評估）

- **大單體是否拆 `references/`**：`gpt-image-gen`（42KB）、`conference-report`（23KB）、`spec`（21KB）、`md2ppt`（20KB）、`prd-create`（19KB）、`ctf-kit`（19KB）皆 > 5KB。但 checklist 的判準是「> 5KB **且有進階/少用段落**才拆、緊湊單體可豁免」——這幾顆多為前後相依的單一流程文件，硬拆會傷可讀性。**逐顆判斷、非無腦全拆**；ctf-kit 已把細節外放到 `docs/`（vmp-guide 等）、主檔留骨架，是可參考的折衷。
- **`md2ppt` 寫死絕對路徑**（`~/.venv_pptx`、`~/.claude/skills/md2ppt/...`）：public repo 可攜性差，但改動牽動同目錄多支 script 的 import，屬需要一起驗的重構、未在本輪動。對照 `skill-cron` 用 `${CLAUDE_SKILL_DIR}` 的寫法作為目標型態。
- **description 深度一致性**：多數已帶 NOT-for 路由，少數（rewrite-tone 等薄工具）仍是一行——薄殼可接受，不強制拉長。

## 已經好的（別動壞）

- #21 的規劃類 skill 決策框、mattpocock 出處標註（Acknowledgments／README 工程紀律段的 attribution）——別砍。
- adr / diagnose / grill 是範本，其他對齊它們、不是反過來。

## 紅線

- 🔴 **public repo**：範例／fixtures 一律抽象、虛構——**禁真公司／客戶／內部 ticket／真人**（見 memory `feedback_public_skill_examples`）。寫前寫後各 grep 一次禁用詞。
- 🔴 **PR-driven**：branch + PR、不直接 push main（此 repo commit 尾帶 `(#N)`）。
- 🔴 **雙語同步**：改 `README.md` 必同步 `README_zh.md`。
- 改任何 SKILL.md 內容 → bump version（doc 澄清走 patch、新增段落走 minor、breaking 走 major）。

## 2026-09-12 文件工作流程更新

新增 [project-docs](https://github.com/KerberosClaw/kc_ai_plugins/tree/main/plugins/doc-qa/skills/project-docs)（2026-09-23 已移至 doc-qa plugin）：盤點既有專案並補齊有證據的 Markdown／Mermaid 文件，沿用組織模板、增量維護。參考目錄與驗證方法保留在 skill 的 references/；搬移／安裝需整個資料夾。[workflow-router](workflow-router/SKILL.md) 0.2.0 已加入現況文件分流，已核准文件工作可直接續跑。新 feature 設計與公開發布整備仍分別走 spec／prep-repo。

## 2026-09-23 搬遷到 plugin

`project-docs` 與 `md2pdf` 移到 [kc_ai_plugins](https://github.com/KerberosClaw/kc_ai_plugins) 的 `doc-qa` plugin（連同新公開的 `qa` 與 Playwright MCP），本 repo 刪除這兩個資料夾，正本以 kc_ai_plugins 為準。README 保留兩列並標 📦 指向新位置；workflow-router 0.2.1、prep-repo 2.3.2 補上 plugin 內的呼叫方式。之後若再把 skill 包成 plugin，照同樣做法：搬過去、這邊留 📦 列、README 的 Plugins 表加一列。

## 2026-09-29 判準外置（薄 skill、厚判準）

原則：`SKILL.md` 只寫步驟，「怎樣才算過」放 `references/` 或 `docs/`，同一套判準只留一份。步驟裡用到判準的地方要寫「先讀那份」，不能只在檔尾列參考資料，否則 agent 不讀就審。

- **ctf-kit 0.5.0**：「提方案前的 checklist」與「安全邊界」原本本體與 `docs/workflow-rules.md` 各一份且已分歧（5 條 vs 6 條），合併成聯集，只留在 `docs/workflow-rules.md`。
- **spec 1.5.0**：四份文件範本搬到 `templates/`，審查與驗收判準搬到 `references/review.md`，實作守則搬到 `references/implement.md`；本體 547 → 331 行，重複講三遍的規則收成一次。
- **prd-create 刻意不動**：§13 摘要了 `goal-engineer/references/loop-run-protocol.md`，但 README 教使用者單獨複製一支 skill，跨 skill 引用在別人機器上會斷。摘要只有一行、漂移風險低；哪天抓到兩邊不一致，再改成「複製一份進 `prd-create/references/` 加比對腳本」。

