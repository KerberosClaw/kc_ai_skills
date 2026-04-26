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

---

## 套用 checklist（寫新 skill 時）

```
[必備]
- [ ] frontmatter description 寫成 trigger condition + 分工說明
- [ ] 正文第一句 "You are a ..." 設定 role
- [ ] 用 Step 1 / Step 1a / Step 1b 階層
- [ ] 至少一個 decision table（sizing / defaults / mode）
- [ ] 至少一段 anti-patterns 用 ❌ 列出

[高頻推薦]
- [ ] 重要事項用 **CRITICAL** / **MANDATORY** 標記
- [ ] code block 完整可執行（不留 pseudocode）
- [ ] output 結構明確（含檔名 / json schema）
- [ ] 結尾有 "Important rules" section（5-10 條）

[場景選用]
- [ ] 有外部 script？→ Agent vs Script 分權 section
- [ ] 主 SKILL.md > 5KB？→ 拆 references/ 子檔
- [ ] 長 workflow / 會跨 session？→ State persistence + resume 設計
- [ ] 接 $ARGUMENTS？→ argument-hint + flag 說明
- [ ] 自我改進 / iteration loop？→ cross-iteration history awareness
```

---

## 反例：常見的「LLM-unfriendly」寫法

- description 只寫功能 → trigger 不夠精準，skill 啟動率低
- 沒設 role → LLM 用 default helpful assistant 風格答題
- step 寫得像 high-level overview → LLM 自由發揮 = 不可預測
- 沒有 anti-patterns → LLM 容易踩明顯坑
- code 用 `# do X here` placeholder → LLM 要自己想 = 變數
- 結尾沒收尾 rules → context 長時忘記核心 invariants
