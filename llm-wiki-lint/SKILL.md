---
name: llm-wiki-lint
description: "掃描 Karpathy LLM Wiki pattern 的三層 repo（raw/ + wiki/ + schema），檢查 frontmatter 完整性、source traceability、stale claims、orphan pages、missing topics、data gaps、cross-page contradictions。純 read-only，只報告不自動改。"
version: 0.1.0
triggers: ["/llm-wiki-lint", "llm wiki lint", "wiki lint", "掃 wiki"]
---

# llm-wiki-lint — Karpathy LLM Wiki 三層健檢

針對採用 [Karpathy LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) 的 repo（`raw/` + `wiki/` + `SCHEMA.md` / `log.md` / `index.md`）做 lint。**只報告不自動改**。

**跟 memory-lint 差異**：
- `memory-lint` 針對 `~/.claude/memory/`（feedback / user profile / project，prefix-based）
- `llm-wiki-lint` 針對 LLM Wiki repo（wiki/ 主題頁 + frontmatter + raw source traceability + index 一致性）

---

## 使用方式

```
/llm-wiki-lint [path]
```

可選參數 `path`：wiki repo root 路徑（含 `wiki/` + `SCHEMA.md` + `index.md`）。

## Path 偵測順序

依序嘗試，命中第一個就用：

1. **使用者在指令傳入的 `path` 參數** — 最優先
2. **環境變數 `$WIKI_REPO_DIR`**
3. **當前工作目錄 `$PWD`** — 若含 `SCHEMA.md` + `wiki/` 子目錄則採用
4. 都找不到 → 告訴使用者「偵測不到 wiki repo」並停止，不要瞎猜

決定路徑後，先 `ls` 確認：
- `<path>/SCHEMA.md` 存在
- `<path>/wiki/` 目錄存在
- `<path>/index.md` 存在（warning 不存在 → 建議新建）
- `<path>/log.md` 存在（warning 不存在 → 建議新建）

---

## 執行流程

### 1. 掃描範圍

- `<path>/wiki/*.md` — 所有主題頁
- `<path>/SCHEMA.md` / `index.md` / `log.md` — schema 層
- `<path>/raw/**` — 存在性檢查（gitignored 所以本地才看得到）
- **跳過**：`<path>/journal/`（非 wiki 一部分）、`<path>/drafts/`、`<path>/scripts/`

### 2. 檢查項目

#### A. Frontmatter 完整性

每個 `wiki/*.md` 開頭應有 YAML frontmatter 含 4 必備欄位：

- `title` — 主題名
- `type` — `overview` / `entity` / `concept` / `comparison` / `synthesis` 之一（Karpathy 5 類）
- `last_updated` — 日期（YYYY-MM-DD）
- `sources` — list，指向 raw/ 或外部來源

檢查：
- 缺 frontmatter → **error**
- 缺任一必備欄位 → **error**
- `type` 不在 5 類內 → **error**
- `last_updated` 格式錯誤 → **warning**
- `sources` 空 list → **warning**（資料缺口，見 §G）

#### B. Index 一致性

- `index.md` 列出但 `wiki/` 下檔案不存在 → **error**（missing file）
- `wiki/` 下檔案存在但 `index.md` 沒列 → **error**（orphan file）
- `index.md` 的 `last_updated` / `type` 跟檔案 frontmatter 不一致 → **warning**（drift）

#### C. Stale claims（陳舊聲明）

- **檔案 mtime vs frontmatter `last_updated` 差 > 14 天** → **warning**（frontmatter 沒跟上）
- **frontmatter `last_updated` > 60 天** 且 `type` = overview / synthesis → **warning**（建議 review）
- **內文提到「待 XXX 驗證」「規劃中」「尚未」等不確定詞 + `last_updated` > 30 天** → **warning**（可能已有進展沒回寫）

#### D. Orphan pages（孤立頁面）

檢查 wiki/ 頁面間 cross-ref：

- 一頁**無任何入站 cross-ref**（其他 wiki 頁都沒連到它） → **warning**
- 例外：`index.md` 提到即不算 orphan

#### E. Missing topic pages（缺失主題頁）

- `index.md` 某類別（e.g. Infrastructure）**空**但其他類別有 → **warning**
- **常見領域缺**（啟發式）：若 repo 提到 database / deployment / security 但對應頁不存在 → **info**
- `wiki/` 有頁但 `index.md` 未分類 → **error**

#### F. Missing cross-refs（缺 cross-ref）

啟發式檢查：

- 頁 A 內文提到頁 B 的 entity / 關鍵詞（如 `RAGFlow` / `Mini-Wally` / 特定 host 名），但沒用 markdown link 連到 B → **info**
- **不強制**，只提示（人讀仍能理解 context）

#### G. Data gaps（資料缺口）

- `sources` 欄位空 / 指向消失的 raw 檔案 → **error**（traceability 斷鏈）
- 主題頁內文 `raw/xxx` 路徑 ref → 對照 `raw/**` 實際存在性（若 raw/ 是 gitignored 須 local 才能檢）
- 主題頁 Open questions 段 > 3 個月未解 → **warning**

#### H. Cross-page contradictions（矛盾）

啟發式（粗略檢查，需人工確認）：

- 同一 entity（e.g. `prod-dgx-01`）在不同頁描述狀態不一致 → **warning**
- 同一數字（e.g. DB 容量 / 壓測 concurrent 數）在不同頁不同 → **warning**
- 需要人工判斷是真矛盾還是更新時差

#### I. SCHEMA.md 宣告 vs 實況

- SCHEMA.md 說「15 主題頁」但實際 17 → **error**（需同步）
- SCHEMA.md 的 type 列表跟實際使用不一致 → **warning**

### 3. 輸出格式

繁體中文報告（英文環境 user 可要求改英文）：

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

### 4. 不做的事

- **不自動修改任何檔案**
- **不自動刪除**（orphan / missing 都只建議）
- **不跨機器**（只看本機指定 path）
- **不訪問外部 API**（純 local grep / read）
- **不寫 log.md**（lint 結果由使用者決定要不要 append）

---

## 範例輸出

```markdown
# 🔍 LLM Wiki Lint 報告

**掃描目錄：** /Users/otakubear/dev/kc_juhan
**掃描時間：** 2026-04-30 14:20
**掃描檔案：** 17 個 wiki 頁 + SCHEMA.md + index.md + log.md

## 🔴 Error

- [Frontmatter] `wiki/architect_cheatsheet.md` 缺 `sources` 欄位 → 補上
- [Index 一致性] `index.md` 列 `wiki/old_topic.md` 但檔案不存在 → 移除 index 對應行
- [SCHEMA] SCHEMA.md 宣告「15 主題頁」但實際 17 → 更新 SCHEMA.md

## 🟡 Warning

- [Stale] `wiki/stress_test_findings.md` last_updated 2026-04-19（已 11 天），但檔案 2026-04-28 有改動 → 更新 frontmatter
- [Orphan] `wiki/architect_cheatsheet.md` 無入站 cross-ref → review 是否該整合進 index
- [Contradiction] `prod-dgx-01` 在 topology.md 寫「gateway + DB」，在 architecture.md 寫「主 brain」→ 同步描述

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

## 注意事項

- 本 skill **純 read-only**，不改任何檔案
- **不處理 `journal/` / `drafts/` / `scripts/`**（非 wiki 一部分）
- `raw/` 存在性檢查僅在 local（gitignored，遠端看不到）
- 報告在對話中印出，不另存檔（要存可手動貼到某處 or append log.md DECISION entry）
- 未來擴充方向：
  - `--fix` 模式（自動補 frontmatter / 更新 index，需 user explicit 同意）
  - cross-ref auto-insert suggestion
  - Git history 分析（stale 檢查更精準）
  - 跟 `memory-lint` 共用 config / convention
