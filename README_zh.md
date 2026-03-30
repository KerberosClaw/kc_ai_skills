# AI Skills：真的會做事的那種

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[English](README.md)

一組解決真實問題的 AI agent skill — 不是那種「幫我摘要這份 PDF」的 skill，而是「幫我掃一下 repo 有沒有把 API key 推上去」的那種。適用於任何支援 skill / prompt 載入的 LLM 客戶端，雲端本地都行。

> Skills 遵循 [Claude Code skill 規範](https://code.claude.com/docs/en/skills)（SKILL.md + scripts/），但概念不限定於特定框架。把它們想成你的 AI 真的會照著做的 checklist。

> **安全聲明：** 這些 skills 設計用於本地開發和受信任的內網環境。與外部服務互動的 skill（如 `searxng`）預設採用安全設定（TLS 驗證啟用），但不包含額外的認證機制。部署到敏感環境前請先檢閱各 skill 的設定。

## Skills

| Skill | 它到底幹嘛 |
|-------|----------|
| [prep-repo](prep-repo/) | 推上 GitHub 之前的「我是不是忘了什麼」checklist。README、commit、機敏資訊、broken link — 就是那些你凌晨兩點一定會忘的東西 |
| [llm-benchmark](llm-benchmark/) | 在你浪費 30 分鐘下載一個塞不進 GPU 的模型之前，先搞清楚哪個 Ollama 模型適合你的顯卡 |
| [searxng](searxng/) | 讓你的本地 LLM 能搜尋網路，而且不用把搜尋紀錄送給 Google |
| [rewrite-tone](rewrite-tone/) | 把你乾巴巴的技術文件變成別人真的想讀的東西。踩坑故事永遠比白皮書好看 |
| [job-scout](job-scout/) | 投履歷之前先把公司查清楚。薪資、評價、紅旗、財務狀況 — 就是你上次面試前應該做但沒做的功課 |
| [repo-scan](repo-scan/) | 安裝之前先幫 GitHub repo 做安全掃描。靜態分析、依賴審計、供應鏈風險、Issues 漏洞回報、維護者健康度 — 因為 `npm install 不知名套件` 不該是一場賭博 |
| [md2pdf](md2pdf/) | 把你的 Markdown 轉成不像 2003 年電腦產出的 PDF。自動處理 Mermaid 圖表、CJK 字型、ASCII art 轉換 — 因為我們已經幫你把所有詭異的 edge case 都踩完了 |
| [spec](spec/) | Spec-driven 開發流程 — 從模糊想法到驗收結案。一個指令，自動判斷專案狀態，引導你走完：需求釐清 → 審查 → 實作 → 驗收 → 結案報告。因為「先寫再說」就是你之後要全部重寫的原因 |
| [job-radar](job-radar/) | 求職自動化的遙控器。在 Telegram 說聲「寫信」，AI 就會讀完 JD、寫好 25 封客製化求職信、打包成 zip 傳回來 -- 你咖啡都還沒喝完。搭配 [kc_job_radar](https://github.com/KerberosClaw/kc_job_radar) 使用，Docker 必備，理智選配 |

## 安裝

拿你需要的，不需要的不用管：

```bash
git clone https://github.com/KerberosClaw/kc_ai_skills.git

# 範例：安裝到 Claude Code（使用者層級）
cp -r kc_ai_skills/prep-repo ~/.claude/skills/

# 範例：安裝到 OpenClaw（workspace 層級）
cp -r kc_ai_skills/searxng ~/.openclaw/workspace/skills/
```

> **命名提示：** 複製時可自行加上前綴重新命名（如 `my_prep-repo`）。不會壞掉的。大概。

> **其他客戶端：** 每個 SKILL.md 都是獨立的 markdown 指令文件。直接複製貼上到任何 AI 對話、system prompt 或自訂指令欄位就能用。不用裝 SDK，不用 API key — 就是複製貼上。

## Skill 結構

每個 skill 遵循一個簡單到不行的規範。會寫 markdown 就會寫 skill：

```
skill-name/
├── SKILL.md          # Frontmatter（name, description, version）+ 指令
└── scripts/          # 可執行腳本（選用）
    └── script.py
```

## 相關專案

- [kc_tradfri_mcp](https://github.com/KerberosClaw/kc_tradfri_mcp) — 「把客廳的燈打開」— 對，我們真的讓 AI 去做這件事了
- [kc_openclaw_local_llm](https://github.com/KerberosClaw/kc_openclaw_local_llm) — 我們測了 13 個本地 LLM，只有 2 個能穩定呼叫 tool。完整報告在這裡
