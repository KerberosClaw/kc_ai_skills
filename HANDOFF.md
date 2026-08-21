# HANDOFF — kc_ai_skills 維護接手

> 給接手繼續整理這個 repo 的 agent。讀這份就知道現況＋剩餘工項＋紅線。
> 建立：2026-07-15；更新：2026-07-30（frontmatter 一致性 + 第二輪 pattern lint 已收）。

## 現況

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
