---
name: memory-lint
description: "掃描 Claude Code memory 目錄找出重複規則、過時狀態、索引不一致、衝突 feedback。輸出報告讓 user 決定怎麼處理。"
version: 0.1.0
triggers: ["/memory-lint", "memory lint", "掃 memory", "memory 健檢"]
---

# memory-lint — Memory 品質健檢

定期掃 memory 目錄找毛病，**只報告不自動改**。每個發現都要 user 決定處理。

## 使用方式

```
/memory-lint [path]
```

可選參數 `path`：memory 目錄路徑。不帶時自動偵測：

## Memory 路徑偵測順序

依序嘗試，命中第一個就用：

1. **使用者在指令傳入的 `path` 參數** — 最優先
2. **環境變數 `$CLAUDE_MEMORY_DIR`**
3. **`~/.claude/settings.json` 的 `autoMemoryDirectory` 欄位**（自訂 memory 路徑的標準設定）
   ```bash
   jq -r '.autoMemoryDirectory // empty' ~/.claude/settings.json | envsubst
   ```
4. **`~/.claude/memory/`**（Claude Code 官方預設）
5. 都找不到 → 告訴使用者「偵測不到 memory 目錄」並停止，不要瞎猜

決定路徑後，先 `ls` 確認目錄存在且包含 `MEMORY.md`。沒有就視為無效路徑。

---

## 執行流程

### 1. 掃描範圍

- 目標目錄下所有 root 層 `*.md`
- **跳過 `archive/` 子資料夾**（除非 user 明確要求掃歸檔）
- 讀 `MEMORY.md` 作為「應該存在的檔案清單」

### 2. 檢查項目

對應用 grep / 檔案 mtime / 內容比對判斷：

#### A. 索引不一致

- **MEMORY.md 列出但檔案不存在** → missing file
- **檔案存在但 MEMORY.md 沒列** → orphan file
- **MEMORY.md 描述跟檔案 frontmatter description 明顯不符** → description drift

#### B. 過時狀態

- **`project_*.md` 檔案 mtime > 30 天** → 可能 stale，建議 review
- **dashboard 類（description 提到「dashboard」或「快照」的檔案）mtime > 7 天** → 需要更新
- **frontmatter `type: project` 且內文提到「進行中」/「active」但檔案 > 60 天沒改** → 疑似結束未歸檔

#### C. 重複 / 衝突 feedback

- **兩個以上 feedback 檔案包含語意相近的規則**（例如「不要過度道歉」同時出現在多個檔案）
- **規則直接衝突**（A 檔說「做 X」、B 檔說「不要做 X」）

#### D. 命名慣例違規（僅適用於有 prefix 慣例的 memory）

偵測方式：先看 MEMORY.md 有沒有 prefix 分類慣例（例如把檔案按 `user_` / `feedback_` / `project_` 等分段列出）。有的話才做這項檢查。

- 沒有 prefix 的 `.md` 檔案（除了 `MEMORY.md` 跟 `CLAUDE.md`）
- prefix 不在該目錄建立的 prefix 清單內

#### E. Frontmatter 缺失

- 檢查每份 md 第一段是否有 YAML frontmatter 含 `name` / `description` / `type`
- 缺欄位 → 列出來

#### F. 檔案過大

- 任一檔案超過 300 行 → 警告（可能該拆或該歸檔）

### 3. 輸出格式

繁體中文報告（英文環境 user 可要求改英文），以嚴重程度分段：

```markdown
# 🔍 Memory Lint 報告

**掃描目錄：** /path/to/memory
**掃描時間：** YYYY-MM-DD HH:MM
**掃描檔案：** N 個（不含 archive/）

## 🔴 嚴重（建議立即處理）

- [類別] 描述 — 建議動作

## 🟡 警告（建議 review）

- [類別] 描述

## 🟢 OK（通過）

- 索引一致性
- 命名慣例
- Frontmatter 完整性
- 檔案大小

## 📊 統計

| 類別 | 檔案數 |
|------|--------|
| （依該目錄實際 prefix 分組） | ... |

**總計：** XX 個活檔
```

### 4. 不做的事

- **不自動修改任何檔案**。只報告，user 決定處理。
- **不自動刪除**。即使判斷是 orphan，也只建議 user 刪。
- **不跨機器操作**。這個 skill 只看本機指定的 memory 目錄。

---

## 範例輸出

```markdown
# 🔍 Memory Lint 報告

**掃描目錄：** /home/user/.claude/memory
**掃描時間：** 2026-04-16 18:30
**掃描檔案：** 19 個（不含 archive/）

## 🔴 嚴重

- [索引不一致] `feedback_test_ci.md` 被 MEMORY.md 列出但檔案不存在 → 建議移除 MEMORY.md 對應行
- [衝突] `feedback_interaction_style.md` 跟 `feedback_dev_style.md` 都有「不要過度道歉」規則 → 建議合併

## 🟡 警告

- [過時] `project_xxx.md` 最後更新 2026-02-28，45 天未變動但 status 仍為「進行中」 → review 是否該歸檔
- [Dashboard 過期] `memory_summary.md` 最後更新 8 天前，建議更新

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

**總計：** 22 個活檔
```

---

## 注意事項

- 本 skill 是**純 read-only**，不改 memory 任何檔案
- 讀取範圍限指定目錄的根層，`archive/` 子資料夾跳過
- 報告在對話中印出，不另存檔（要存可手動貼到某處）
- 不同 user 的 memory 目錄可能沒有 prefix 慣例 — 那就跳過 D 項檢查，其他檢查照做
- 未來擴充方向：cron 定期執行、跨 machine 比對、自動修補建議（需 user explicit 同意才動）
