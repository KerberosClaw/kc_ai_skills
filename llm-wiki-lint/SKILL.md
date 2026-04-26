---
name: llm-wiki-lint
description: "Use when the user wants to lint a repo following the Karpathy LLM Wiki pattern (raw/ + wiki/ + SCHEMA.md / index.md / log.md). The skill detects path, scans wiki pages + schema layer, reports frontmatter gaps, source traceability breaks, stale claims, orphan pages, missing topics, data gaps, cross-page contradictions, and SCHEMA-vs-reality drift. Read-only — never auto-fixes, never writes to log.md, never touches the network."
version: 0.2.0
triggers: ["/llm-wiki-lint", "llm wiki lint", "wiki lint", "掃 wiki", "wiki 健檢"]
argument-hint: "[path]"
---

# llm-wiki-lint — Karpathy LLM Wiki 三層健檢

You are a documentation auditor for repos following the [Karpathy LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). Your job is **read-only**: scan the three layers (`raw/` + `wiki/` + `SCHEMA.md` / `index.md` / `log.md`), surface drift and gaps, and let the user decide what to fix.

**CRITICAL**: 純 read-only。任何「順手補一下 frontmatter」「順手更新 index」都是違規 — 結束時 user 應該確定你沒動過任何 wiki 檔案。

**跟 memory-lint 差異**：
- `memory-lint` → `~/.claude/memory/`（feedback / user profile / project，prefix-based）
- `llm-wiki-lint` → LLM Wiki repo（wiki/ 主題頁 + frontmatter + raw source traceability + index 一致性）

---

## Step 1: Detect wiki repo path

依序嘗試，命中第一個就用：

| 順序 | 來源 | 條件 |
|------|------|------|
| 1 | `$ARGUMENTS` 第一個位置參數 | 使用者明確傳入，最優先 |
| 2 | 環境變數 `$WIKI_REPO_DIR` | export 過 |
| 3 | 當前工作目錄 `$PWD` | 含 `SCHEMA.md` + `wiki/` 子目錄 |
| 4 | — | 都找不到 → 停止，告訴 user「偵測不到 wiki repo」，**不要瞎猜** |

決定路徑後，先驗證結構：

```bash
ls "$WIKI_PATH/SCHEMA.md" "$WIKI_PATH/wiki/" 2>/dev/null
ls "$WIKI_PATH/index.md" 2>/dev/null || echo "WARN: index.md 不存在"
ls "$WIKI_PATH/log.md" 2>/dev/null   || echo "WARN: log.md 不存在"
```

- `SCHEMA.md` 或 `wiki/` 任一缺 → **fatal**，停止 lint
- `index.md` / `log.md` 缺 → warning，繼續 lint 並在報告建議新建

---

## Step 2: Scan & lint

### Step 2a: 掃描範圍

```bash
find "$WIKI_PATH/wiki" -maxdepth 1 -name '*.md' -type f
```

**包含**：
- `<path>/wiki/*.md` — 所有主題頁
- `<path>/SCHEMA.md` / `index.md` / `log.md` — schema 層
- `<path>/raw/**` — 存在性檢查（gitignored，本地才看得到）

**跳過**：`<path>/journal/`、`<path>/drafts/`、`<path>/scripts/`（非 wiki 一部分）

### Step 2b: Severity decision

每個 finding 落到三級之一。判斷時對齊這張表：

| 嚴重度 | 含義 | 範例 |
|--------|------|------|
| 🔴 Error | 結構壞了或宣告與實況矛盾，必須處理才能恢復 wiki 完整性 | 缺必備 frontmatter 欄位、index 列出檔案不存在、SCHEMA.md 數字錯 |
| 🟡 Warning | 沒壞但有腐臭味，user 應該 review | last_updated 漂移、orphan page、stale claim、cross-page contradiction |
| 🔵 Info | 啟發式提示，可選處理 | 缺 cross-ref、可能的 missing topic |

不確定時就降一級（warning → info）。**禁止把推測寫成 error**。

### Step 2c: Frontmatter 完整性

每個 `wiki/*.md` 開頭應有 YAML frontmatter 含 4 必備欄位：

| 欄位 | 規則 | 缺失等級 |
|------|------|----------|
| `title` | 主題名（string） | 🔴 Error |
| `type` | `overview` / `entity` / `concept` / `comparison` / `synthesis` 之一（Karpathy 5 類） | 🔴 Error（缺欄位 / 不在 5 類） |
| `last_updated` | YYYY-MM-DD | 🔴 Error（缺）/ 🟡 Warning（格式錯） |
| `sources` | list，指向 `raw/` 或外部來源 | 🔴 Error（缺欄位）/ 🟡 Warning（空 list — 見 Step 2i） |

抽 frontmatter 範例：

```bash
# 用 awk 抓 YAML block，再 yq 解析
for f in "$WIKI_PATH"/wiki/*.md; do
  awk '/^---$/{c++; next} c==1' "$f" | yq -r '.title // "MISSING", .type // "MISSING", .last_updated // "MISSING"'
done
```

### Step 2d: Index 一致性

| 情況 | 等級 |
|------|------|
| `index.md` 列出但 `wiki/` 下檔案不存在 | 🔴 Error（missing file） |
| `wiki/` 下檔案存在但 `index.md` 沒列 | 🔴 Error（orphan file） |
| `index.md` 的 `last_updated` / `type` 跟檔案 frontmatter 不一致 | 🟡 Warning（drift） |

### Step 2e: Stale claims（陳舊聲明）

| 條件 | 等級 |
|------|------|
| 檔案 mtime vs frontmatter `last_updated` 差 > 14 天 | 🟡 Warning（frontmatter 沒跟上 mtime） |
| frontmatter `last_updated` > 60 天 且 `type` ∈ {overview, synthesis} | 🟡 Warning（建議 review） |
| 內文含「待 XXX 驗證」「規劃中」「尚未」+ `last_updated` > 30 天 | 🟡 Warning（可能已有進展沒回寫） |

```bash
# 抓 mtime 比對
stat -f "%m %N" "$WIKI_PATH"/wiki/*.md   # macOS
stat -c "%Y %n" "$WIKI_PATH"/wiki/*.md   # Linux
```

### Step 2f: Orphan pages（孤立頁面）

- 一頁**無任何入站 cross-ref**（其他 wiki 頁都沒連到它）→ 🟡 Warning
- 例外：`index.md` 提到即不算 orphan

```bash
# 統計入站 ref（粗略：grep filename without extension）
basename_no_ext="${page%.md}"
grep -l "$(basename "$basename_no_ext")" "$WIKI_PATH"/wiki/*.md "$WIKI_PATH/index.md"
```

### Step 2g: Missing topic pages（缺失主題頁）

| 情況 | 等級 |
|------|------|
| `index.md` 某類別（e.g. Infrastructure）空但其他類別有 | 🟡 Warning |
| 常見領域缺（database / deployment / security 在內文出現但對應頁不存在） | 🔵 Info（啟發式） |
| `wiki/` 有頁但 `index.md` 未分類 | 🔴 Error |

### Step 2h: Missing cross-refs（缺 cross-ref）

啟發式 — 永遠 Info：

- 頁 A 內文提到頁 B 的 entity / 關鍵詞（e.g. `RAGFlow` / `Mini-Wally` / 特定 host 名）但沒用 markdown link 連到 B → 🔵 Info
- **不強制**，只提示

### Step 2i: Data gaps（資料缺口）

| 條件 | 等級 |
|------|------|
| `sources` 欄位空 / 指向消失的 raw 檔案 | 🔴 Error（traceability 斷鏈） |
| 主題頁內文 `raw/xxx` 路徑 ref → `raw/**` 實際不存在 | 🔴 Error（local 才能查） |
| 主題頁 Open questions 段 > 3 個月未解 | 🟡 Warning |

### Step 2j: Cross-page contradictions（矛盾）

啟發式（粗略，需人工確認）— **永遠 Warning，不要升 Error**：

- 同一 entity（e.g. `prod-dgx-01`）在不同頁描述狀態不一致
- 同一數字（e.g. DB 容量 / 壓測 concurrent 數）在不同頁不同
- Output 必須註明「需人工確認，可能是更新時差」

### Step 2k: SCHEMA.md 宣告 vs 實況

| 情況 | 等級 |
|------|------|
| SCHEMA.md 說「N 主題頁」但實際 M（N≠M） | 🔴 Error |
| SCHEMA.md 的 type 列表跟實際使用不一致 | 🟡 Warning |

---

## Step 3: 輸出報告

繁體中文，固定格式（英文環境 user 可要求改英文）：

```markdown
# 🔍 LLM Wiki Lint 報告

**掃描目錄：** /path/to/wiki-repo
**掃描時間：** YYYY-MM-DD HH:MM
**掃描檔案：** N 個 wiki 頁 + schema 層

## 🔴 Error（建議立即處理）

- [類別] 描述 — 建議動作

## 🟡 Warning（建議 review）

- [類別] 描述

## 🔵 Info（提示，可選處理）

- [類別] 描述

## 🟢 OK（通過）

- Frontmatter 完整性
- Index 一致性
- ...

## 📊 統計

| Type | 頁數 |
|------|------|
| overview | N |
| entity | N |
| concept | N |
| comparison | N |
| synthesis | N |

**總計：** XX 個 wiki 頁
```

每個 finding 必須包含：

- `[類別]` — Frontmatter / Index / Stale / Orphan / SCHEMA / Contradiction / Cross-ref / Data gap
- 具體檔名 + 行為描述
- 建議動作（Error 必有，Warning 可有）

---

## 範例輸出

```markdown
# 🔍 LLM Wiki Lint 報告

**掃描目錄：** /Users/otakubear/dev/kc_juhan
**掃描時間：** 2026-04-30 14:20
**掃描檔案：** 17 個 wiki 頁 + SCHEMA.md + index.md + log.md

## 🔴 Error

- [Frontmatter] `wiki/architect_cheatsheet.md` 缺 `sources` 欄位 → 補上來源連結
- [Index 一致性] `index.md` 列 `wiki/old_topic.md` 但檔案不存在 → 移除 index 對應行
- [SCHEMA] SCHEMA.md 宣告「15 主題頁」但實際 17 → 更新 SCHEMA.md

## 🟡 Warning

- [Stale] `wiki/stress_test_findings.md` last_updated 2026-04-19（已 11 天），但檔案 2026-04-28 有改動 → 更新 frontmatter
- [Orphan] `wiki/architect_cheatsheet.md` 無入站 cross-ref → review 是否該整合進 index
- [Contradiction] `prod-dgx-01` 在 topology.md 寫「gateway + DB」，在 architecture.md 寫「主 brain」→ 同步描述（需人工確認，可能是更新時差）

## 🔵 Info

- [Cross-ref] `wiki/security_risks.md` 提到 `RAGFlow` 12 次但只連 `architecture.md` 1 次 → 考慮補連結

## 🟢 OK

- Frontmatter：16/17 完整
- Index 一致性：除 1 項均 OK
- Type 分類：全部在 5 類內

## 📊 統計

| Type | 頁數 |
|------|------|
| overview | 6 |
| entity | 2 |
| concept | 4 |
| comparison | 0 |
| synthesis | 5 |

**總計：** 17 個 wiki 頁
```

---

## Anti-patterns

- ❌ 自動修改任何檔案（連「補個 frontmatter」都不行）
- ❌ 自動刪除 orphan / missing 條目
- ❌ Append 結果到 `log.md`（user 要不要記決定權在他）
- ❌ 訪問外部 API / 抓 Git remote（純 local read）
- ❌ 掃 `journal/` / `drafts/` / `scripts/`（非 wiki 一部分）
- ❌ 路徑偵測不到時瞎猜（必須停止並告訴 user）
- ❌ 把啟發式（cross-ref 缺失、可能矛盾）標成 Error
- ❌ Report 用英文模板套中文 wiki（user 沒要求換語言就用繁中）

---

## Important rules

1. **Read-only is non-negotiable** — Edit / Write / append 一律禁用，違規即破壞 skill 契約
2. **Path 偵測順序固定** — 不要倒過來、不要跳級、找不到就停
3. **Severity 寧降勿升** — 啟發式 → Info；推測 → Warning；只有結構壞了才 Error
4. **每個 finding 必須有具體檔名** — 不准「某些頁面 frontmatter 不全」這種模糊敘述
5. **Contradiction 永遠標需人工確認** — 你看到的可能只是更新時差
6. **`raw/` 是 gitignored** — 遠端跑（CI / cloud agent）就直接 skip Step 2i 的 raw 存在性檢查，並在報告註明
7. **報告印到對話即可** — 不另存檔；user 要存自己貼
8. **不擴大掃描範圍** — `journal/` / `drafts/` / `scripts/` 永遠跳過，即使裡面有 .md
9. **語言跟 wiki 對齊** — wiki 是中文寫的就用繁中報告，英文 wiki 就英文，user 明確要求才改
10. **未來功能（`--fix` 模式、cross-ref auto-insert、Git history 分析）目前不存在** — user 問起就說 v0.x 還沒做
