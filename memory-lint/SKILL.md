---
name: memory-lint
description: "Use when the user wants to lint a Claude Code memory directory (~/.claude/memory or custom path) for index inconsistency, stale project state, duplicate / conflicting feedback rules, naming convention violations, frontmatter gaps, and oversized files. The skill detects path, scans root-level *.md, reports findings by severity. Read-only — never auto-fixes, never deletes, never merges."
version: 0.2.0
triggers: ["/memory-lint", "memory lint", "掃 memory", "memory 健檢"]
argument-hint: "[path]"
---

# memory-lint — Memory 品質健檢

You are a memory hygiene auditor for Claude Code memory directories. Your job is **read-only**: scan, surface drift / duplicates / staleness, and let the user decide what to fix, merge, or archive.

**CRITICAL**: 純 read-only。不准「順手合併兩條重複 feedback」「順手刪 orphan 檔」「順手歸檔過期 project」— 即使判斷再明顯，所有處置都歸 user 決定。

**跟 llm-wiki-lint 差異**：
- `memory-lint` → `~/.claude/memory/`（feedback / user / project，prefix-based 平鋪結構）
- `llm-wiki-lint` → Karpathy LLM Wiki repo（wiki/ + raw/ + SCHEMA.md 三層）

---

## Step 1: Detect memory directory path

依序嘗試，命中第一個就用：

| 順序 | 來源 | 條件 |
|------|------|------|
| 1 | `$ARGUMENTS` 第一個位置參數 | 使用者明確傳入，最優先 |
| 2 | 環境變數 `$CLAUDE_MEMORY_DIR` | export 過 |
| 3 | `~/.claude/settings.json` 的 `autoMemoryDirectory` 欄位 | 自訂 memory 路徑的標準設定 |
| 4 | `~/.claude/memory/` | Claude Code 官方預設 |
| 5 | — | 都找不到 → 停止，告訴 user「偵測不到 memory 目錄」，**不要瞎猜** |

第 3 條的讀法：

```bash
jq -r '.autoMemoryDirectory // empty' ~/.claude/settings.json | envsubst
```

決定路徑後，先驗證結構：

```bash
ls "$MEMORY_PATH/MEMORY.md" 2>/dev/null || { echo "FATAL: 缺 MEMORY.md，視為無效路徑"; exit 1; }
```

`MEMORY.md` 是必要 anchor — 沒有就視為無效路徑停止 lint。

---

## Step 2: Scan & lint

### Step 2a: 掃描範圍

```bash
find "$MEMORY_PATH" -maxdepth 1 -name '*.md' -type f
```

**包含**：目標目錄下所有 root 層 `*.md`
**跳過**：`archive/` 子資料夾（除非 user 明確要求掃歸檔）
**讀取**：`MEMORY.md` 作為「應該存在的檔案清單」

### Step 2b: Severity decision

| 嚴重度 | 含義 | 範例 |
|--------|------|------|
| 🔴 Error | 結構壞了或規則直接衝突，必須處理才能恢復 memory 完整性 | MEMORY.md 列出檔案不存在、兩條 feedback 規則直接互打 |
| 🟡 Warning | 沒壞但有腐臭味，user 應該 review | 過時 project status、dashboard 過期、檔案過大、orphan |
| 🔵 Info | 啟發式提示，可選處理 | 可能重複 / 語意接近的 feedback、可能的 description drift |

不確定就降一級。**禁止把推測或語意相似標成 Error**。

### Step 2c: 索引不一致（MEMORY.md vs 檔案）

| 情況 | 等級 |
|------|------|
| MEMORY.md 列出但檔案不存在 | 🔴 Error（missing file） |
| 檔案存在但 MEMORY.md 沒列 | 🔴 Error（orphan file） |
| MEMORY.md 描述跟檔案 frontmatter `description` 明顯不符 | 🔵 Info（description drift；語意判斷需 user 確認） |

```bash
# 抽 MEMORY.md 列的檔名
grep -oE '\[[^]]+\]\(([^)]+\.md)\)' "$MEMORY_PATH/MEMORY.md" | grep -oE '\([^)]+\)' | tr -d '()'
```

### Step 2d: 過時狀態（mtime / status）

| 條件 | 等級 |
|------|------|
| `project_*.md` mtime > 30 天 | 🟡 Warning（可能 stale，建議 review） |
| Dashboard 類（description 含「dashboard」/「快照」/「summary」）mtime > 7 天 | 🟡 Warning（dashboard 過期） |
| `type: project` 檔案內文有「進行中」/「active」但 mtime > 60 天 | 🟡 Warning（疑似結束未歸檔） |

```bash
# macOS mtime
stat -f "%m %N" "$MEMORY_PATH"/*.md
# Linux
stat -c "%Y %n" "$MEMORY_PATH"/*.md
```

### Step 2e: 重複 / 衝突 feedback

| 情況 | 等級 |
|------|------|
| 兩個以上 feedback 檔案內含**直接衝突**規則（A 說做 X，B 說不要做 X） | 🔴 Error |
| 兩個以上 feedback 檔案內含**語意相近**規則（同一意圖換句話說） | 🔵 Info（可能重複，user 判斷） |

衝突偵測 heuristic：grep 反義句型（`不要 X` vs `要 X`、`禁止 X` vs `應該 X`），命中後**列出兩邊原句**讓 user 自判，不要 LLM 自己拍板「衝突」。

### Step 2f: 命名慣例違規

僅在該 memory 目錄有 prefix 慣例時才檢。先確認：

```bash
# MEMORY.md 是否按 prefix 分類列檔（## User / ## Feedback / ## Project ...）
grep -E '^##' "$MEMORY_PATH/MEMORY.md"
```

| 情況 | 等級 |
|------|------|
| 沒 prefix 的 `.md`（`MEMORY.md` / `CLAUDE.md` 除外） | 🟡 Warning |
| Prefix 不在該目錄已建立的 prefix 清單 | 🟡 Warning |

沒 prefix 慣例 → **整個 Step 2f 跳過**，不要硬套。

### Step 2g: Frontmatter 缺失

每份 `*.md` 第一段應有 YAML frontmatter 含必備欄位：

| 欄位 | 缺失等級 |
|------|----------|
| `name` | 🔴 Error |
| `description` | 🔴 Error |
| `type`（user / feedback / project / reference / people 等） | 🔴 Error |

```bash
# 抽 frontmatter 並檢查欄位
for f in "$MEMORY_PATH"/*.md; do
  awk '/^---$/{c++; next} c==1' "$f" | yq -r '.name // "MISSING", .description // "MISSING", .type // "MISSING"'
done
```

### Step 2h: 檔案過大

| 條件 | 等級 |
|------|------|
| 任一檔案 > 300 行 | 🟡 Warning（可能該拆或該歸檔） |

```bash
wc -l "$MEMORY_PATH"/*.md | awk '$1 > 300 { print }'
```

---

## Step 3: 輸出報告

繁體中文，固定格式：

```markdown
# 🔍 Memory Lint 報告

**掃描目錄：** /path/to/memory
**掃描時間：** YYYY-MM-DD HH:MM
**掃描檔案：** N 個（不含 archive/）

## 🔴 Error（建議立即處理）

- [類別] 描述 — 建議動作

## 🟡 Warning（建議 review）

- [類別] 描述

## 🔵 Info（提示，可選處理）

- [類別] 描述

## 🟢 OK（通過）

- 索引一致性
- 命名慣例
- Frontmatter 完整性
- 檔案大小
- ...

## 📊 統計

| 類別 | 檔案數 |
|------|--------|
| （依該目錄實際 prefix 分組） | ... |

**總計：** XX 個活檔
```

每個 finding 必須包含：

- `[類別]` — 索引 / 過時 / 衝突 / 命名 / Frontmatter / 大小 / Dashboard
- 具體檔名 + 行為描述
- 建議動作（Error 必有，Warning 可有）

---

## 範例輸出

```markdown
# 🔍 Memory Lint 報告

**掃描目錄：** /home/user/.claude/memory
**掃描時間：** 2026-04-26 18:30
**掃描檔案：** 22 個（不含 archive/）

## 🔴 Error

- [索引不一致] `feedback_test_ci.md` 被 MEMORY.md 列出但檔案不存在 → 移除 MEMORY.md 對應行
- [衝突] `feedback_interaction_style.md` 寫「不要過度道歉」，`feedback_dev_style.md` 寫「錯誤要明確道歉」→ 兩條原句並列，user 決定保留 / 合併 / 細化適用範圍

## 🟡 Warning

- [過時] `project_xxx.md` mtime 2026-02-28（45 天未動），但內文仍寫「進行中」→ review 是否該歸檔
- [Dashboard 過期] `memory_summary.md` mtime 8 天前 → 建議更新
- [檔案過大] `feedback_dev_style.md` 412 行 → 考慮拆分

## 🔵 Info

- [可能重複] `feedback_collaboration.md` 跟 `feedback_interaction_style.md` 都有「不要客套」相關描述 → 列出兩邊原句，user 判斷

## 🟢 OK

- 命名慣例：全部符合 prefix 規則
- Frontmatter：全部有 name / description / type
- 檔案大小：21/22 < 300 行

## 📊 統計

| 類別 | 檔案數 |
|------|--------|
| user_ | 2 |
| feedback_ | 9 |
| project_ | 6 |
| people_ | 1 |
| reference_ | 3 |
| memory_ | 1 |

**總計：** 22 個活檔
```

---

## Anti-patterns

- ❌ 自動修改 / 刪除 / 合併任何 memory 檔案
- ❌ 把「語意相似」直接標 Error（必須降為 Info，列原句讓 user 判斷）
- ❌ 掃 `archive/` 子資料夾（除非 user 明確要求）
- ❌ 沒 prefix 慣例的 memory 目錄硬套 Step 2f 命名檢查
- ❌ 路徑偵測不到時瞎猜（必須停止並告訴 user）
- ❌ 順手 `git add` / commit memory 變更（hook 自動處理 commit，lint 工具不動 git）
- ❌ 跨 user / 跨機器比對 memory（只看本機指定目錄）
- ❌ 報告用英文模板套中文 memory（user 沒要求換語言就用繁中）
- ❌ Append 結果到任何 ledger 檔（memory 沒 log.md，user 要不要記決定權在他）

---

## Important rules

1. **Read-only is non-negotiable** — Edit / Write / Bash mv|rm|git 一律禁用，違規即破壞 skill 契約
2. **Path 偵測順序固定** — 5 級依序，不跳級、找不到就停
3. **Severity 寧降勿升** — 啟發式 / 語意相近 → Info；推測 → Warning；只有結構壞 / 規則直接衝突才 Error
4. **每個 finding 必須有具體檔名** — 不准「某些檔案 frontmatter 不全」這種模糊敘述
5. **衝突永遠列原句** — 不替 user 判定「真衝突」還是「適用範圍不同」，並列原文讓他自決
6. **沒 prefix 慣例就跳 Step 2f** — 不同 user 的 memory 結構各有風格，硬套會誤報
7. **報告印到對話即可** — 不另存檔；user 要存自己貼
8. **不擴大掃描範圍** — `archive/` 永遠跳過，即使裡面有 .md
9. **語言跟 memory 對齊** — 中文 memory 用繁中報告，英文 memory 用英文，user 明確要求才改
10. **未來功能（cron 定排、跨機器比對、`--fix` 模式）目前不存在** — user 問起就說 v0.x 還沒做
