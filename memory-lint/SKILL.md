---
name: memory-lint
description: "掃描 Claude Code memory（~/dev/kc_claude_memory/）找出重複規則、過時狀態、索引不一致、衝突 feedback。輸出報告讓 user 決定怎麼處理。"
version: 0.1.0
triggers: ["/memory-lint", "memory lint", "掃 memory", "memory 健檢"]
---

# memory-lint — Memory 品質健檢

定期掃 memory 目錄找毛病，**只報告不自動改**。每個發現都要 user 決定處理。

## 使用方式

```
/memory-lint
```

不帶參數。skill 會自動掃預設路徑 `~/dev/kc_claude_memory/`。

---

## 執行流程

### 1. 掃描範圍

- 路徑：`~/dev/kc_claude_memory/`（不含 `archive/` 子資料夾）
- 檔案：所有 root 層 `*.md`
- 參考：讀 `MEMORY.md` 作為「應該存在的檔案清單」

### 2. 檢查項目

對應用 grep / 檔案 mtime / 內容比對判斷，每項命中報告：

#### A. 索引不一致

- **MEMORY.md 列出但檔案不存在** → missing file
- **檔案存在但 MEMORY.md 沒列** → orphan file
- **MEMORY.md 描述跟檔案 frontmatter description 明顯不符** → description drift

#### B. 過時狀態

- **`project_*.md` 檔案 mtime > 30 天** → 可能 stale，建議 review
- **`memory_summary.md` mtime > 7 天** → 需要更新
- **frontmatter `type: project` 且內文提到「進行中」/「active」但檔案 > 60 天沒改** → 疑似結束未歸檔

#### C. 重複 / 衝突 feedback

- **兩個以上 feedback_*.md 包含相似規則**（例如「不要過度道歉」同時出現在 `interaction_style` 跟 `dev_style`）
- **規則直接衝突**（A 檔說「做 X」、B 檔說「不要做 X」）

#### D. 命名慣例違規

- **沒有 prefix 的 `.md` 檔案**（除了 `MEMORY.md`）
- **prefix 不在認可清單內**：`user_`, `feedback_`, `project_`, `people_`, `reference_`, `memory_`

#### E. Frontmatter 缺失

- 檢查每份 md 第一段是否有 YAML frontmatter 含 `name` / `description` / `type`
- 缺欄位 → 列出來

#### F. 檔案過大

- 任一檔案超過 300 行 → 警告（可能該拆或該歸檔）

### 3. 輸出格式

繁體中文報告，以嚴重程度分段：

```markdown
# 🔍 Memory Lint 報告

**掃描時間：** YYYY-MM-DD HH:MM
**掃描檔案：** N 個

## 🔴 嚴重（建議立即處理）

- [類別] 描述 — 建議動作

## 🟡 警告（建議 review）

- [類別] 描述

## 🟢 OK（通過）

- 索引一致性
- 命名慣例
- Frontmatter 完整性
- （等等通過項目）

## 📊 統計

| 類別 | 檔案數 |
|------|--------|
| user_ | N |
| feedback_ | N |
| project_ | N |
| people_ | N |
| reference_ | N |
| memory_ | N |
| archive/ | N |

**總計：** XX 個活檔 + YY 個歸檔
```

### 4. 不做的事

- **不自動修改任何檔案**。只報告，user 決定處理。
- **不自動刪除**。即使判斷是 orphan，也只建議 user 刪。
- **不跨機器操作**。這個 skill 只看本機 memory 目錄。

---

## 範例輸出

```markdown
# 🔍 Memory Lint 報告

**掃描時間：** 2026-04-16 18:30
**掃描檔案：** 19 個（含 MEMORY.md）

## 🔴 嚴重

- [索引不一致] `feedback_test_ci.md` 被 MEMORY.md 列出但檔案不存在 → 建議移除 MEMORY.md 對應行
- [衝突] `feedback_interaction_style.md` 跟 `feedback_dev_style.md` 都有「不要過度道歉」規則 → 建議合併到 interaction_style

## 🟡 警告

- [過時] `project_bes_startup.md` 最後更新 2026-04-01，45 天未變動但 status 仍為「擱置中」 → review 是否該歸檔
- [Dashboard 過期] `memory_summary.md` 最後更新 5 天前，建議更新

## 🟢 OK

- 命名慣例：全部符合 prefix 規則
- Frontmatter：全部有 name/description/type
- 檔案大小：全部 < 300 行

## 📊 統計

| 類別 | 檔案數 |
|------|--------|
| user_ | 2 |
| feedback_ | 9 |
| project_ | 6 |
| people_ | 1 |
| reference_ | 3 |
| memory_ | 1 |

**總計：** 22 個活檔，0 個歸檔
```

---

## 注意事項

- 本 skill 是**純 read-only**，不改 memory 任何檔案
- 讀取範圍限 `~/dev/kc_claude_memory/` 根目錄，archive/ 子資料夾跳過（除非 user 明確要求）
- 報告在對話中印出，不另存檔案（如果 user 要存，可以手動把報告貼到某處）
- 未來擴充方向：定期 cron 執行、跨 machine 比對、自動 PR 建議修補
