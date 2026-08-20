# AI Skills：真的會做事的那種

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[English](README.md)

一組解決真實問題的 AI agent skill — 不是那種「幫我摘要這份 PDF」的 skill，而是「幫我掃一下 repo 有沒有把 API key 推上去」的那種。適用於任何支援 skill / prompt 載入的 LLM 客戶端，雲端本地都行。

> Skills 遵循 [Claude Code skill 規範](https://code.claude.com/docs/en/skills)（SKILL.md + scripts/），但概念不限定於特定框架。把它們想成你的 AI 真的會照著做的 checklist。

> **安全聲明：** 這些 skills 設計用於本地開發和受信任的內網環境。與外部服務互動的 skill（如 `searxng`）預設採用安全設定（TLS 驗證啟用），但不包含額外的認證機制。部署到敏感環境前請先檢閱各 skill 的設定。

## Skills

依「你想完成什麼」分組 — 每個 skill 仍是獨立的根目錄資料夾，分組只是張地圖。

### 工作流入口

| Skill | 它到底幹嘛 |
|-------|----------|
| [workflow-router](workflow-router/) | 給最容易混的中間地帶當入口：PRD、SD、FR、AC、ADR、拆票、實作、release、無人值守。它最多問一個澄清問題，告訴你該用哪顆 specialist skill，用白話說原因，然後交棒。它刻意不自己寫 PRD/spec/ADR |

### 生成與創作

| Skill | 它到底幹嘛 |
|-------|----------|
| [gpt-image-gen](gpt-image-gen/) | 把 Codex 哄去幫你生圖。先擬一份精準的雙語 prompt，跟你來回改到你明確說「生」，才真的呼叫 Codex CLI 文生圖 — 那道硬拍板閘門是因為「看起來不錯」不等於「生」，而每張圖都燒真金白銀的額度。文生圖 + 圖生圖（丟張本機參考圖就能 codex `-i` 鎖臉/鎖角色），給你一張 jpg，而且絕不主動把預覽視窗糊你臉上 |
| [character-lora](character-lora/) | 把原創角色從「一個點子 + 一張定版 look」帶到一顆能跨角度跨場景守住身份的 LoRA。orchestrate 整條 pipeline — 定義 → 多角度資料集（出圖 delegate 給 gpt-image-gen）→ caption → 該 base 的訓前功課 → 本機 GPU 訓練 → 驗收 — 每個燒錢步驟都 gate。鐵律：訓練前先讀那個 base 自己的訓練文件，憑印象配參數就是角色每次「抽籤」的元兇 |
| [rewrite-tw](rewrite-tw/) | 正體中文（台灣）校閱，門檻故意調高：只挑真的會讓讀者讀錯的語病（主詞遺失、句子斷裂、量詞誤用、連接詞邏輯反了），加上台灣工程師根本不會那樣講的用詞。純風格偏好、標點細節、沒有好中譯的英文詞一律放行。引用來源的原詞只提示不逕改，免得跟出處對不上。先出唯讀報告，你點頭才動檔案 |
| [rewrite-tone](rewrite-tone/) | 把你乾巴巴的技術文件變成別人真的想讀的東西。踩坑故事永遠比白皮書好看 |

### 文件與簡報

| Skill | 它到底幹嘛 |
|-------|----------|
| [md2pdf](md2pdf/) | 把你的 Markdown 轉成不像 2003 年電腦產出的 PDF。自動處理 Mermaid 圖表、CJK 字型、ASCII art 轉換 — 因為我們已經幫你把所有詭異的 edge case 都踩完了 |
| [md2ppt](md2ppt/) | md2pdf 的吵鬧弟弟。把你的 Markdown 報告變成簡報品質 .pptx，透過互動式設計對話 + 可重用的 Python build script。Generic markdown→pptx 工具（Marp、pandoc）產出來的 slide 技術上對但視覺上爛 — md2ppt 跟你一張一張對話討論 layout，然後吐一份 hand-coded script，內容改動 re-run 5 秒重產。可選 LibreOffice self-check。Brand template 整合走 ad-hoc helpers — 試過 prescribed workflow，5 輪「等等這不是 cover layout」後退掉 |
| [conference-report](conference-report/) | 你去了場研討會，錄了演講、拍了投影片，回家抱著一堆音檔加糊掉的照片，外帶一句「改天再來整理」的空頭支票。這個 skill 幫你重建忠實的逐場筆記（投影片畫面 + 講者逐字稿，還會標出 Whisper 的幻覺，免得你引用到機器的白日夢），然後在動筆前先問清楚你到底要哪種報告 — 單場、整天、還是跨天綜合 |

### 規格與交付

| Skill | 它到底幹嘛 |
|-------|----------|
| [prd-create](prd-create/) | 把一堆會議紀錄、散落的對話訊息、hand-waved 的需求，拼成一份照你 org guideline 的結構化 PRD — 缺的它 quiz 你、不亂編，stakeholder 衝突 surface 給你拍板、不擅自選邊，最後 sanitize + 發布到 ADO Wiki。純 prompt-driven、無 Python。prd-create → prd-breakdown → ADO 這條 chain 的前半 |
| [prd-breakdown](prd-breakdown/) | 拿一份完成的 PRD，沿 vertical slice 拆成 Azure DevOps 工作項（HITL/AFK 標記 + blocked_by 依賴），再用 az CLI 推上去 — fingerprint 標記做 idempotent、重跑不會重複建項。prd-create → prd-breakdown → ADO 這條 chain 的後半 |
| [spec](spec/) | Spec-driven 開發流程 — 從模糊想法到驗收結案。一個指令，自動判斷專案狀態，引導你走完：需求釐清 → 審查 → 實作 → 驗收 → 結案報告。因為「先寫再說」就是你之後要全部重寫的原因 |
| [goal-engineer](goal-engineer/) | 給那種「想丟給 agent 自己磨一整晚、又不想全程盯著」的場景。它用訪談式問答幫你把一條目標驅動的 evaluator-optimizer loop（generate-and-select 型:產候選 → 依 rubric 評 → 依原因碼迭代 → 你挑最終那個）釘死，吐一份新 session 能 blind 執行的 dispatch 文件，你只要看著紅黃綠燈通知滾進來就好。它是**寫規格的上游、不是引擎** — dispatch 丟給 Claude Code 內建的 `/goal`、headless `claude -p`、或任何無人值守 agent 去跑。不是 `/goal` 本身、不是 build-to-spec 的 PRD 作者（那是 prd-create）、也不是 cron 定時器。唯一窄例外：build spec **已經凍結**（核可的 ADR / 鎖定的設計 / 可機器檢核的 AC）、只差無人值守執行的包裝 → 它直接出一份 lean build dispatch，不會逼你為一個已經拍板的決策回頭寫整份 PRD。通知通道隨你換（Telegram/Discord/Slack/iMessage），而且內建一道「ship 前要不要先對抗審查?」的閘 — 因為我們自己每次都忘記問 |

> 不確定用哪顆時，先用 `workflow-router`。最短判斷法：產品需求走 `prd-create`；repo 內的 SD / 工程 AC / 實作走 `spec`；單一重要技術決策走 `adr`；核可 PRD 拆票走 `prd-breakdown`；凍結目標要無人值守跑走 `goal-engineer`。

### 工程紀律

> 這一組是交付流程前、中、後都會用到的行為護欄。`grill` / `diagnose` / `adr` 的紀律機制參考 [mattpocock/skills](https://github.com/mattpocock/skills)（MIT），中文重寫、並調整成本 repo 慣例。

| Skill | 它到底幹嘛 |
|-------|----------|
| [grill](grill/) | 「先討論」的制度化。你丟個模糊想法，它不准自己動手，一次問你一題、每題附建議答案，問到雙方理解一致才放行。最鋒利的一條規則：grep 查得到的事不准問你 — 拷問你之前先拷問 filesystem。詞彙飄了還會順手幫 repo 養一本 CONTEXT.md 詞彙表 |
| [diagnose](diagnose/) | 先架測謊機，再准審問。沒有一條能重現症狀的指令之前，禁止提任何 root cause 理論；要猜也得一次列 3-5 個假說、附可否證預測、排好序先給你過目。專治 AI（和人類）讀兩眼 code 就宣稱「找到原因了」的老毛病 |
| [adr](adr/) | 幫你記架構決策，但它的第一件事是勸你別記。三重閘（難回頭 / 沒脈絡會困惑 / 真實取捨）全過才動筆，預設格式是標題加三句話 — ADR 的價值在「記下為什麼」，不在填滿模板。特別會盯兩種東西：刻意偏離顯然路徑的決策、和被否決的方案 |
| [prep-repo](prep-repo/) | 推上 GitHub 之前的「我是不是忘了什麼」checklist。README、commit、機敏資訊、broken link、專案結構、測試、CI、Docker、最後清理 — 就是那些你凌晨兩點一定會忘的東西 |

### 研究與安全

| Skill | 它到底幹嘛 |
|-------|----------|
| [searxng](searxng/) | 讓你的本地 LLM 能搜尋網路，而且不用把搜尋紀錄送給 Google |
| [repo-scan](repo-scan/) | 安裝之前先幫 GitHub repo 做安全掃描。靜態分析、依賴審計、供應鏈風險、Issues 漏洞回報、維護者健康度 — 因為 `npm install 不知名套件` 不該是一場賭博 |
| [ctf-kit](ctf-kit/) | Windows 應用程式驗證繞過的實戰 playbook — VMProtect、Themida、網路驗證，都能打。從 67+ 次失敗中淬煉出來的，省你重踩一遍。附帶即用型 Frida 偵察腳本和零依賴 PE 分析器。搭配 [ljagiello/ctf-skills](https://github.com/ljagiello/ctf-skills) 覆蓋更廣的 CTF 場景 |
| [job-scout](job-scout/) | 投履歷之前先把公司查清楚。薪資、評價、紅旗、財務狀況 — 就是你上次面試前應該做但沒做的功課 |

### AI 知識庫衛生

| Skill | 它到底幹嘛 |
|-------|----------|
| [memory-lint](memory-lint/) | AI memory 養久了會堆積重複規則、過時的「進行中」專案、孤兒檔案。這個 skill 把它們全部掃出來，免得 Claude 哪天很有自信地把錯的規則搬出來打臉你。分三段：掃描階段純 read-only，也是預設行為；只有你點名的 finding 才會真的動檔案，改完再交給獨立行程複驗，沒過就回退 |
| [llm-wiki-lint](llm-wiki-lint/) | Karpathy 的 LLM Wiki pattern 有個盲點 — 超過 15 頁之後，陳舊聲明、孤立 cross-ref、缺失主題會默默腐爛。這個 skill 是 lint pass：矛盾、source traceability、data gap、frontmatter 完整性、index drift。針對 `raw/` + `wiki/` + `schema` 三層 repo。純 read-only。搭配 [memory-lint](memory-lint/) 做 full-stack AI 知識庫保健 |
| [llm-benchmark](llm-benchmark/) | 在你浪費 30 分鐘下載一個塞不進 GPU 的模型之前，先搞清楚哪個 Ollama 模型適合你的顯卡 |
| [wrap-up](wrap-up/) | 你昨天查了六小時才搞懂的事，compact 之後只剩一行摘要 — 隔天的 session 只好從頭再推一次，而它需要的那張底圖還躺在桌面，等你下週大掃除順手刪掉。這個 skill 在你收工前把產出收進專案（照你專案自己的規矩搬、接雙向 ref、把躺在草稿裡的結論併回正式文件），然後派一個完全不知道發生過什麼事的 sub-agent，從入口檔開始考試。判準是行為性的：不是「連結都通了」，是「陌生人接得住」。答對還不算過 — 講不出依據在哪個檔，就代表下次還是找不到。這條是我們自己重踩同一個坑之後才寫的 |

### 自動化與監看

| Skill | 它到底幹嘛 |
|-------|----------|
| [skill-cron](skill-cron/) | 一個管理器統治所有排程。註冊任何 skill 做 crontab 定時執行 + Telegram 推播 — 因為 `claude -p` 不支援 `/skill` 語法，總得有人把橋搭起來。設定存 `~/.claude/configs/`，日誌自動輪替，crontab entries 自動管理 |

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
├── SKILL.md          # Frontmatter（name, description, version, status, triggers）+ 指令
└── scripts/          # 可執行腳本（選用）
    └── script.py
```

## 相關專案

- [kc_tradfri_mcp](https://github.com/KerberosClaw/kc_tradfri_mcp) — 「把客廳的燈打開」— 對，我們真的讓 AI 去做這件事了
- [kc_openclaw_local_llm](https://github.com/KerberosClaw/kc_openclaw_local_llm) — 我們測了 13 個本地 LLM，只有 2 個能穩定呼叫 tool。完整報告在這裡
```
