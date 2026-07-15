# SKILL.md 寫作 Patterns（從 0x0funky 五份歸納）

歸納來源：

- `agent-sprite-forge/skills/generate2dsprite/SKILL.md`
- `agent-sprite-forge/skills/generate2dmap/SKILL.md`
- `vibehq-hub/.claude/skills/run-teamwork/SKILL.md`
- `vibehq-hub/.claude/skills/benchmark-loop/SKILL.md`
- `vibehq-hub/.claude/skills/optimize-protocol/SKILL.md`

分三層：**必備 / 高頻推薦 / 場景選用**。

---

## 必備（5 份都有）

### P1. Frontmatter description = trigger condition

不是描述「做什麼」，是描述「**何時被叫用 + 怎麼分工**」。Codex / Claude 讀 description 決定要不要啟用這個 skill。

❌ `"Generate 2D sprites from prompts"`
✅ `"Use when Codex should infer the asset plan from a natural-language request, call built-in image_gen for solid-magenta raw sheets, and use the local processor only for chroma-key cleanup, frame extraction, alignment, QC, and transparent exports."`

### P2. 角色定位開頭（You are a ...）

正文第一句設定 agent persona / role，給 LLM 進入該心智模型。

範例：
- `You are a professional technical recruiter and team architect.`
- `You are an autonomous benchmark runner for VibeHQ.`
- `You are a senior framework engineer working on VibeHQ.`

### P3. Step-by-step Workflow（編號 + 子步驟）

`Step 1 / Step 1a / Step 1b / Step 2 ...` 的階層結構，子步驟極細，給確切的 file path / bash command / json schema。**不要 pseudocode，給可 copy-paste 的真內容**。

### P4. Decision frameworks 表格化

給 LLM「不知道時的 fallback」+ 視覺化決策樹。

範例：
```
| Domains | Team size | When |
|---------|-----------|------|
| 1       | PM + 1    | API only, CLI |
| 2       | PM + 2    | Full-stack |
| 3       | PM + 3    | Full-stack + infra |
```

### P5. Anti-patterns 明列

用 ❌ 列「不該做什麼」比寫 should 更有效（負面 framing 對 LLM 更約束）。

範例：
```
- ❌ 2 agents in same directory
- ❌ Splitting one codebase by "feature"
- ❌ Designer agent without substantial UI deliverables
```

---

## kc_ai_skills framework 自定 frontmatter 擴充

除了 0x0funky 通用的 `name + description + argument-hint`，kc_ai_skills 自己的 skill loader 多支援三個欄位（**寫 kc_ai_skills 內的 skill 必加**）：

### EX1. `version`

語意化版本號（semver）：

```yaml
version: 0.1.0
```

- 用途：skill 變更追蹤、breaking change 判斷
- `0.x.x` = `status: experimental` 或 `status: mvp`，還在 iterate 階段，介面可能變
- `1.0.0+` = `status: stable`，breaking change 要 bump major
- patch（0.1.0 → 0.1.1）= bug fix / 文案修
- minor（0.1.0 → 0.2.0）= 新功能不 break 既有
- major（0.x → 1.0）= breaking 介面變

### EX2. `status`

成熟度標記（必填）：

```yaml
status: mvp
```

- `experimental` = 還在摸索，入口/流程可能大改，只適合早期試用
- `mvp` = 可用，但仍在調整；version 應維持 `0.x.x`
- `stable` = 常用且成熟；version 應為 `1.0.0+`，破壞既有用法要 bump major
- 不要用 `status` 取代 version：status 說「穩定度」，version 說「變更序列」

### EX3. `triggers`

Explicit trigger pattern list（指令觸發 + 自然語言觸發都可）：

```yaml
triggers:
  - "/llm-wiki-lint"
  - "wiki lint"
  - "掃 wiki"
```

- 用途：補強 description 的 trigger 判斷，命中任一觸發詞 = 啟用 skill
- canonical 格式 = YAML block list（每個 trigger 一行），不要用 inline array
- **中文指令式**（「掃 wiki」「整理 memory」「投履歷前查公司」）特別需要 explicit list — 因為自然中文沒有 standardize trigger phrase
- 跟 description 不衝突 — description 寫**情境**（「Use when ...」），triggers 列**字面觸發詞**
- slash command 形式（`/skill-name`）也要列進來

### 為什麼 0x0funky 沒這兩個

- 0x0funky 的 skill 跑在 Codex / Claude Code 原生 skill loader，那邊用 `description` + `argument-hint` 就夠（英文 trigger 自然包在 description 裡）
- kc_ai_skills 是**自有 skill loader**，要支援中文 trigger + 版本管理 + 成熟度標記，故擴充
- **互不衝突，並存使用** — 套 0x0funky patterns 不會把這兩欄位拿掉

---

## 高頻推薦（4-5 份有）

### P6. Critical / Mandatory 強調語

不能忽略的事項用 `**CRITICAL**` / `**MANDATORY**` 標記。LLM 對視覺強調有 attention bias。

範例：`**CRITICAL**: Always include --auto-kickstart and CLAUDECODE= clearing.`

### P7. Code blocks 完整可執行

bash / node / json 都寫完整可執行的 — 連 path、env var、flag、windows vs unix 差異都明寫。LLM 不用「填空」就能套用。

### P8. Output schema 明確

Output 結構 spec 在 SKILL.md 內，不靠 agent 自己發明檔名 / 欄位。範例：generate2dsprite 列出每個 bundle type 的 file 清單；optimize-protocol 給完整 markdown changelog template。

### P9. 「Important rules / principles」結尾

收尾用編號列 5-10 條核心 invariants，提醒「即使前面 step 都讀過了，這幾條是核心」。LLM 在 long context 下，結尾的 rules 比中段的 step 更易 retain。

---

## 場景選用（看 skill 性質決定）

### P10. Agent vs Script 分權

當 skill = 「agent + 外部 script」配合場景時用。明確寫「Agent decides X, script does Y」。

範例（agent-sprite-forge）：
```
- Decide the asset plan yourself.
- Write the art prompt yourself. Do NOT default to the prompt-builder script.
- Use the script only as a deterministic processor.
- Treat script flags as execution primitives chosen by the agent.
```

純 agent-driven 的 skill（vibehq-hub 三個）就不用這條。

### P11. Resources / References lazy load

當 SKILL.md 主檔太長時，拆 `references/` 子檔，主檔 link 過去。LLM 必要時才讀，避免主檔爆 token。

範例：
```
references/modes.md          ← agent 困惑時讀
references/prompt-rules.md   ← prompt 鐵律
references/layered-map-contract.md ← 進階 case 才讀
```

### P12. State persistence / Resume design

長 workflow（會跨 session、可能 context 壓縮）必加。State 寫到磁碟，skill 開頭先檢查能否 resume。

範例（benchmark-loop）：
```
**ALWAYS start here.** Read ~/.vibehq/analytics/optimizations/loop-state.json if it exists.
- If it exists and phase is NOT "completed", resume from the saved phase.
- If it does NOT exist OR phase is "completed", this is a fresh run.
```

### P13. Argument-hint frontmatter 欄位

skill 接 `$ARGUMENTS` 時用。frontmatter 加 `argument-hint` + 內文再詳細解釋每個 flag 的 default 和語意。

範例：
```yaml
argument-hint: '"<project description>" [--port <number>] [--max-iterations <number>]'
```

### P14. Cross-iteration history awareness

需要學習 / 自我改進的 skill 用。讀過去執行 history 找 trend，決定是否 escalate / refine fix / detect regression。

範例（optimize-protocol Step 1c）：
```
| Pattern | What it means | How to handle |
|---------|--------------|---------------|
| Problem fixed in iteration N, reappears in N+1 | Fix was incomplete or bypassed | Strengthen, don't re-implement |
| New problem in N+1 that didn't exist in N | Side-effect of a previous fix | Trace back; refine that fix |
```

### P15. Defaults 表 + Resources section（agent-sprite-forge 風格）

當 skill 有大量參數選擇時用。`Defaults` section 給 fallback 心智，`Resources` section 列可選參考檔。

### P16. 薄殼 / 本體分層（from mattpocock/skills invocation 慣例）

當一組 skill 有「user 打的入口」跟「可重用的紀律」兩種角色時用：

- **入口殼**（user-invoked）：只做編排、可以短到一行（「跑 X 紀律 + 套 Y」）；description 以人類可讀一行摘要開頭（slash 選單用）——仍照 P1 寫觸發情境、兩面不互斥，字面觸發詞交 `triggers` 欄位承擔
- **紀律本體**（model-invoked）：可重用的流程 / checklist；description 寫給模型看（塞滿 "Use when ..." 觸發語句）
- **鐵律：入口殼可以呼叫紀律本體，永遠不呼叫另一個入口殼**（編排不套編排）
- 同一 skill 可兼兩角（自帶觸發詞、又被入口以紀律身分呼叫，如 grill）；鐵律限制的是呼叫對方的「編排面」，呼叫其「紀律面」不受限
- **互引一律 prose 呼叫**（「跑 `grill` skill」），**禁止跨目錄深連結**別的 skill 的檔案；共用參考檔放在「擁有它的 skill」目錄內，別人要用就呼叫該 skill。（prose 指出「正典在某檔」不算深連結；禁的是把「讀取他 skill 的檔案」寫成執行步驟）

判準：「模型自主伸手拿它有用嗎？」——可重用是抽成 skill 的理由，不是留 model-invoked 的判準。

### P17. 停止句 + 不阻塞條款（防偷跑）

Agent 容易偷跑的環節（未對齊先動工、沒證據先下結論、未確認先寫測試），放**明文停止句**：

- 格式：「**X 未發生前，禁止 Y**」（例：「共同理解未確認前禁動手」「no red-capable command, no hypothesis」）
- 完成判準用 checklist，不用形容詞（「跑過至少一次、貼出輸出」而不是「充分驗證」）
- **必配不阻塞條款**：user 不在場（背景 / 無人值守）→ 照建議答案 / 自排序續走，假設明文標「未確認」——停止句擋的是偷跑，不是把 agent 卡死
- **不阻塞條款只適用「資訊不足」類閘**；授權閘 / 安全閘 / 破壞性動作閘沒有 fallback，一律停下等人

---

## 發布前：對抗審查（互動詢問；public skill 必做）

skill 寫完、**release 前主動問 user 要不要對抗審查**（不要等 user 自己喊——這是 leak 防線）：

> 「skill 寫好了，要先派對抗審查再 release 嗎?
> 1. 派 sub-agent 審　2. 不用　3. 其他（自訂輪數/順序/reviewer，例「兩輪，先 sub-agent 後 codex」）」

- 每位 reviewer：**獨立、預設找碴**，分兩塊——
  - 🔴 **LEAK 獵殺（public skill 紅線）**：NSFW／公司·客戶·同事／個人身份／真實 credential（token·chat_id·webhook）／真實機器名·絕對路徑·repo·IP，連「間接暗示私密來源」的指紋都抓。**範例一律抽象。**
  - **品質**：pattern 合規（上述那些）＋ bug ＋ blind-runnable。
- 多輪：修完一輪再審下一輪，全過才 release。
- 🔴 **為什麼必做**：public skill 一旦 leak 就追不回（曾發生過）。codex + 獨立 LLM sub-agent 交叉審最穩。

## 套用 checklist（寫新 skill 時）

```
[必備]
- [ ] frontmatter description 寫成 trigger condition + 分工說明
- [ ] 正文第一句 "You are a ..." 設定 role
- [ ] 用 Step 1 / Step 1a / Step 1b 階層
- [ ] 至少一個 decision table（sizing / defaults / mode）
- [ ] 至少一段 anti-patterns 用 ❌ 列出

[kc_ai_skills 自定擴充（寫 kc_ai_skills 內 skill 必加）]
- [ ] frontmatter `version` 欄位（semver，初版 0.1.0）
- [ ] frontmatter `status` 欄位（experimental / mvp / stable，且與 version 對齊）
- [ ] frontmatter `triggers` 欄位（block list，含 slash command + 中文自然語言觸發詞）

[高頻推薦]
- [ ] 重要事項用 **CRITICAL** / **MANDATORY** 標記
- [ ] code block 完整可執行（不留 pseudocode）
- [ ] output 結構明確（含檔名 / json schema）
- [ ] 結尾有 "Important rules" section（5-10 條）

[場景選用]
- [ ] 有外部 script？→ Agent vs Script 分權 section
- [ ] 主 SKILL.md > 5KB 且有「進階 / 少用才讀」段落？→ 拆 references/ 子檔（緊湊單體可豁免）
- [ ] 長 workflow / 會跨 session？→ State persistence + resume 設計
- [ ] 接 $ARGUMENTS？→ argument-hint + flag 說明
- [ ] 自我改進 / iteration loop？→ cross-iteration history awareness
- [ ] 有「入口編排 + 可重用紀律」兩種角色？→ 薄殼 / 本體分層（P16）
- [ ] 有 agent 易偷跑的環節？→ 停止句 + 不阻塞條款（P17）

[發布前]
- [ ] release 前問 user 要不要對抗審查（public skill 必做：leak 掃 + 品質；codex + 獨立 sub-agent 交叉、可多輪）
```

---

## 反例：常見的「LLM-unfriendly」寫法

- description 只寫功能 → trigger 不夠精準，skill 啟動率低
- 沒設 role → LLM 用 default helpful assistant 風格答題
- step 寫得像 high-level overview → LLM 自由發揮 = 不可預測
- 沒有 anti-patterns → LLM 容易踩明顯坑
- code 用 `# do X here` placeholder → LLM 要自己想 = 變數
- 結尾沒收尾 rules → context 長時忘記核心 invariants
