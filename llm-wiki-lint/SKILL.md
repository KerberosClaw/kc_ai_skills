---
name: llm-wiki-lint
description: "Use when the user wants to lint a repo following the Karpathy LLM Wiki pattern (raw/ + wiki/ + SCHEMA.md / index.md / log.md). The skill detects path, scans wiki pages + schema layer, reports frontmatter gaps, broken in-body links, source traceability breaks, stale claims, orphan pages, index synopsis contradictions, and SCHEMA-vs-reality drift. Phase 1 is read-only report; Phase 2 (fix + log.md LINT entry) only runs after the user explicitly approves."
version: 0.3.1
triggers: ["/llm-wiki-lint", "llm wiki lint", "wiki lint", "掃 wiki", "wiki 健檢"]
argument-hint: "[path]"
---

# llm-wiki-lint — Karpathy LLM Wiki 三層健檢

You are a documentation auditor for repos following the [Karpathy LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). Scan the three layers (`raw/` + `wiki/` + `SCHEMA.md` / `index.md` / `log.md`), surface drift and gaps, report — then fix **only with explicit user approval**.

**CRITICAL — 兩段式契約**：
- **Phase 1（report）純 read-only**。掃描期間任何「順手補一下 frontmatter」「順手更新 index」都是違規。
- **Phase 2（fix）必須等 user 對報告明確點頭**（「修」「fix」「都修掉」）才啟動。User 只說「跑 lint」= 只做 Phase 1。

**跟 memory-lint 差異**：
- `memory-lint` → Claude memory 目錄（feedback / user profile / project，prefix-based）
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

### Step 1b: 載入 repo 自有規約（lint 的 source of truth）

**不要硬編碼 Karpathy 預設值 — 以目標 repo 自己的宣告為準**：

| 規約 | 來源 | fallback |
|------|------|----------|
| type allow-list | `SCHEMA.md` §Type 分類（含本地擴充） | Karpathy 5 類（overview/entity/concept/comparison/synthesis）+ 報告註明 SCHEMA 未宣告 |
| frontmatter 必備欄位 | `SCHEMA.md` §Frontmatter 欄位 | title / type / last_updated / sources |
| lint 後是否 append log.md | `SCHEMA.md` §Lint 節奏 | 不 append |
| 額外文件風格規則（如「body 禁 date marker」） | repo 的 `CLAUDE.md` / `docs/` 規則檔（如有） | 跳過此項檢查 |

---

## Step 2: Scan & lint（Phase 1 — read-only）

### Step 2a: 掃描範圍

```bash
find "$WIKI_PATH/wiki" -maxdepth 1 -name '*.md' -type f
find "$WIKI_PATH/wiki" -mindepth 1 -maxdepth 1 -type d   # 子目錄偵測 — 上面那條只看 .md，抓不到目錄
```

**包含**：
- `<path>/wiki/*.md` — 所有主題頁（第二條指令找到子目錄時列出並在報告標註，等 user 決定是否納入）
- `<path>/SCHEMA.md` / `index.md` / `log.md` — schema 層
- `<path>/raw/**` — 存在性檢查（gitignored，本地才看得到）

**跳過**：`<path>/journal/`、`<path>/drafts/`、`<path>/scripts/`（非 wiki 一部分）

**工具紀律**：解析 frontmatter / 比對清單一律用 `python3` stdlib（`re` + `glob`），**不要依賴 `yq` / `jq`**（目標機器不保證裝了）。

### Step 2b: Severity decision

| 嚴重度 | 含義 | 範例 |
|--------|------|------|
| 🔴 Error | 結構壞了或宣告與實況矛盾 | 缺必備 frontmatter 欄位、index 列出檔案不存在、body 連結指向已刪頁、SCHEMA.md 數字錯 |
| 🟡 Warning | 沒壞但有腐臭味，user 應該 review | last_updated 漂移、orphan page、stale claim、index 摘要與頁面內容矛盾 |
| 🔵 Info | 啟發式提示，可選處理 | 缺 cross-ref、可能的 missing topic |

不確定時就降一級（warning → info）。**禁止把推測寫成 error**。

### Step 2c: Frontmatter 完整性

每個 `wiki/*.md` 開頭應有 YAML frontmatter，必備欄位以 Step 1b 載入的清單為準：

| 欄位 | 規則 | 缺失等級 |
|------|------|----------|
| `title` | 主題名（string） | 🔴 Error |
| `type` | **在 Step 1b 載入的 allow-list 內** | 🔴 Error（缺欄位 / 不在 allow-list） |
| `last_updated` | YYYY-MM-DD | 🔴 Error（缺）/ 🟡 Warning（格式錯） |
| `sources` | list，指向 `raw/` 或外部來源 | 🔴 Error（缺欄位）/ 🟡 Warning（空 list — 見 Step 2i） |

```bash
python3 - <<'EOF'
import re, glob
for f in sorted(glob.glob("wiki/*.md")):
    s = open(f, encoding="utf-8-sig").read()   # utf-8-sig 吃掉 BOM；\r?\n 容忍 CRLF（Windows 編輯過的檔）
    m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n", s, re.S)
    if not m: print(f"NO-FRONTMATTER {f}"); continue
    fm = m.group(1)
    for field in ("title", "type", "last_updated", "sources"):
        if not re.search(rf"^{field}:", fm, re.M): print(f"MISSING {field} {f}")
EOF
```

### Step 2d: Index 一致性

| 情況 | 等級 |
|------|------|
| `index.md` 列出但 `wiki/` 下檔案不存在 | 🔴 Error（missing file） |
| `wiki/` 下檔案存在但 `index.md` 沒列 | 🔴 Error（orphan file） |
| `index.md` 的 `last_updated` / `type` 跟檔案 frontmatter 不一致 | 🟡 Warning（drift） |
| `index.md` 標頭宣稱頁數 ≠ 實際頁數 | 🔴 Error |

### Step 2e: Index 摘要 vs 頁面內容矛盾

index 每列通常帶「一句話」摘要。**逐列對照該頁當前核心結論** — 摘要還在講已被頁面推翻的舊事實（例：摘要說「服務 X 運行中、不能停」，頁面已改寫成「服務 X 已停用」）→ 🟡 Warning。這是日期 drift 抓不到的：日期可能同步了、摘要忘了改。

### Step 2f: Body 連結完整性（in-body link integrity）

掃每頁 body 的兩種站內連結，目標不存在 → 🔴 Error：

- markdown link：`[...](some_page.md)` → `wiki/some_page.md` 必須存在（含連字號 / 大寫 / `./` 前綴 / `#anchor` 變體）
- wikilink：`[[some_page]]` 與別名形式 `[[some_page|顯示文字]]` → `wiki/some_page.md` 必須存在

**捕捉要寬不要窄** — 斷鏈檢查的失敗模式是「沉默通過」：regex 漏掉的連結形式不會報錯，user 會誤以為全綠。寬鬆捕捉任何 `.md` 目標，再正規化比對：

```bash
python3 - <<'EOF'
import re, glob, os
for f in sorted(glob.glob("wiki/*.md")):
    s = open(f, encoding="utf-8-sig").read()
    for t in re.findall(r"\]\(([^)#\s]+\.md)(?:#[^)]*)?\)", s):
        if t.startswith(("http://", "https://")): continue   # 外部連結不在此檢查
        rel = t[2:] if t.startswith("./") else t
        if not os.path.exists(os.path.join("wiki", rel)): print(f"BROKEN-LINK {f} -> {t}")
    for t in re.findall(r"\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]*)?\]\]", s):
        if not os.path.exists(f"wiki/{t.strip()}.md"): print(f"BROKEN-WIKILINK {f} -> {t}")
EOF
```

### Step 2g: Stale claims（陳舊聲明）

| 條件 | 等級 |
|------|------|
| git 最後 commit 日 vs frontmatter `last_updated` 差 > 14 天 | 🟡 Warning（frontmatter 沒跟上實際改動） |
| frontmatter `last_updated` > 60 天 且 `type` ∈ {overview, synthesis} | 🟡 Warning（建議 review） |
| 內文含未完成標記 + `last_updated` > 30 天 | 🟡 Warning（可能已有進展沒回寫） |

未完成標記的關鍵詞清單**跟 wiki 語言對齊**（Rule 9）：中文 wiki 掃「待 XXX 驗證」「規劃中」「尚未」；英文 wiki 掃 "TBD" / "pending" / "not yet" / "WIP" / "to be verified"。

```bash
# git repo 用 commit 日（mtime 在 clone / checkout 後不可靠）；非 git repo 才 fallback stat
git -C "$WIKI_PATH" log -1 --format=%cs -- "wiki/<page>.md"
```

### Step 2h: Orphan pages（孤立頁面）

- 一頁**沒有任何其他主題頁連到它**（只有 `index.md` 列出）→ 🟡 Warning
- `index.md` **不算**入站 ref — index 列出是 Step 2d 的強制要求，每頁都有；若把它當例外，凡通過 2d 的頁面永遠不會是 orphan，本檢查形同虛設

### Step 2i: Data gaps（資料缺口）

| 條件 | 等級 |
|------|------|
| `sources` 欄位空 / 指向消失的 raw 檔案 | 🔴 Error（traceability 斷鏈；raw 可能被搬移過 — 報告附 `find raw -iname` 找到的新位置候選） |
| 主題頁內文 `raw/xxx` 路徑 ref → `raw/**` 實際不存在 | 🔴 Error（local 才能查） |
| 主題頁 Open questions 段 > 3 個月未解 | 🟡 Warning |

### Step 2j: Cross-page contradictions（矛盾）

啟發式（粗略，需人工確認）— **永遠 Warning，不要升 Error**：

- 同一 entity（同一台主機 / 同一服務名）在不同頁描述狀態不一致
- 同一數字（容量 / 並發數 / 頁數）在不同頁不同
- Output 必須註明「需人工確認，可能是更新時差」

### Step 2k: SCHEMA.md 宣告 vs 實況

| 情況 | 等級 |
|------|------|
| SCHEMA.md 說「N 主題頁」但實際 M（N≠M） | 🔴 Error |
| 實際使用的 type 不在 SCHEMA 宣告清單（反向也算：宣告了沒人用不報） | 🟡 Warning — 修法二選一：頁面改 type，或 SCHEMA 擴充收編（報告兩案並列，user 拍板） |

### Step 2l: Repo 自有風格規則（Step 1b 有載入才跑）

例：repo 規定「wiki body 不留 date marker（更新/校正註記），事件日期除外」→ 掃 `（YYYY-MM-DD 驗證）` `（校正）` 類 pattern → 🟡 Warning。**事件本身的日期（「X 月 X 日起」「YYYY-MM-DD 到期」）不算違規** — 逐筆判斷，不確定就標 Info。

### Step 2m: Missing topics / cross-refs（啟發式，永遠 Info）

- `index.md` 某類別空但其他類別有 → 🔵 Info
- 頁 A 內文高頻提到頁 B 的主題詞但沒連結 → 🔵 Info

---

## Step 3: 輸出報告（Phase 1 結束點）

繁體中文，固定格式（英文 wiki 才用英文）：

```markdown
# 🔍 LLM Wiki Lint 報告

**掃描目錄：** /path/to/team-wiki
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
- ...

## 📊 統計

| Type | 頁數 |
|------|------|
| （依 Step 1b 載入的 allow-list 動態列出實際使用的 type） | N |

**總計：** XX 個 wiki 頁
```

每個 finding 必須包含：

- `[類別]` — Frontmatter / Index / Link / Stale / Orphan / SCHEMA / Contradiction / Style / Data gap
- 具體檔名 + 行為描述
- 建議動作（Error 必有，Warning 可有）

報告結尾固定問一句：**「要修嗎？修的話哪些（全修 / 只修 Error / 指定項）？」** — 不要替 user 決定。

---

## Step 4: Fix（Phase 2 — 必須 user 明確點頭才跑）

User 對報告回「修」後：

### Step 4a: 修機械項

Error + 指定的 Warning，典型：index reconcile（補列 / 砍幽靈列 / 日期同步 / 頁數標頭）、補 frontmatter（從 index 值 + 頁內資料來源段重建）、移除斷鏈、修 sources 路徑、SCHEMA 數字 / type 清單同步。

**修不動的（需 user 判斷的內容矛盾、大範圍風格清理）→ 列為 deferred，寫進 LINT entry，不要硬修。**

### Step 4b: 重跑驗證

Phase 1 同套檢查重跑，機械項應歸零。報告殘留項。

### Step 4c: log.md LINT entry

**僅當 repo SCHEMA 規定 lint 須留痕**（Step 1b 載入）才 append，格式跟著該 repo log.md 既有 entry 走，內容含：findings 分類 + 修了什麼 + deferred 什麼。SCHEMA 沒規定 → 問 user 要不要記。

### Step 4d: Commit

跟著目標 repo 的 commit 慣例（有 PR 流程走 PR）。Commit message 描述 lint 範圍 + 修正類別，不逐項展開。

---

## 範例輸出（虛構 repo，僅示意格式）

```markdown
# 🔍 LLM Wiki Lint 報告

**掃描目錄：** /path/to/team-wiki
**掃描時間：** 2026-01-15 14:20
**掃描檔案：** 17 個 wiki 頁 + SCHEMA.md + index.md + log.md

## 🔴 Error

- [Frontmatter] `wiki/cheatsheet.md` 缺 `sources` 欄位 → 補上來源連結
- [Index] `index.md` 列 `wiki/old_topic.md` 但檔案不存在 → 移除 index 對應行
- [Link] `wiki/onboarding.md` 連到 `data_model.md`（頁已刪）→ 移除或改指現行頁
- [SCHEMA] SCHEMA.md 宣告「15 主題頁」但實際 17 → 更新 SCHEMA.md

## 🟡 Warning

- [Stale] `wiki/load_test.md` last_updated 2026-01-04，但 git 最後 commit 2026-01-13 → 更新 frontmatter
- [Index 摘要] `wiki/service_inventory.md` 摘要寫「服務 X 運行中」，頁面現況已改「服務 X 已停用」→ 改寫摘要
- [Contradiction] `db-host-01` 在 topology.md 寫「gateway + DB」，在 architecture.md 寫「僅 DB」→ 同步描述（需人工確認，可能是更新時差）

## 🔵 Info

- [Cross-ref] `wiki/security.md` 提到「訊息佇列」9 次但沒連 `mq_pipeline.md` → 考慮補連結

## 🟢 OK

- Body 連結完整性：除 1 項均 OK
- Type 分類：全部在 SCHEMA allow-list 內

## 📊 統計

| Type | 頁數 |
|------|------|
| overview | 6 |
| concept | 4 |
| synthesis | 5 |
| sop | 2 |

**總計：** 17 個 wiki 頁

要修嗎？修的話哪些（全修 / 只修 Error / 指定項）？
```

---

## Anti-patterns

- ❌ Phase 1 改任何檔案（連「補個 frontmatter」都不行）
- ❌ User 沒點頭就進 Phase 2（「跑 lint」≠「修」）
- ❌ 硬編碼 Karpathy 5 類當 type 鐵律 — repo SCHEMA 擴充的 type 是合法的
- ❌ 依賴 `yq` / `jq`（用 python3 stdlib）
- ❌ 用 mtime 判 stale（git repo 一律用 commit 日）
- ❌ 訪問外部 API / 抓 Git remote（純 local read；`git log` 是 local）
- ❌ 掃 `journal/` / `drafts/` / `scripts/`（非 wiki 一部分）
- ❌ 路徑偵測不到時瞎猜（必須停止並告訴 user）
- ❌ 把啟發式（cross-ref 缺失、可能矛盾）標成 Error
- ❌ 範例 / 報告裡塞任何真實組織的內部名稱（host / 產品 / 路徑）— 示意一律虛構

---

## Important rules

1. **兩段式契約是核心** — Phase 1 read-only；Phase 2 等明確點頭。違規即破壞 skill 契約
2. **Repo 規約 > skill 預設** — type 清單、必備欄位、log 留痕政策都先讀目標 repo 的 SCHEMA / 規則檔
3. **Path 偵測順序固定** — 不要倒過來、不要跳級、找不到就停
4. **Severity 寧降勿升** — 啟發式 → Info；推測 → Warning；只有結構壞了才 Error
5. **每個 finding 必須有具體檔名** — 不准「某些頁面 frontmatter 不全」這種模糊敘述
6. **Contradiction 永遠標需人工確認** — 你看到的可能只是更新時差
7. **`raw/` 是 gitignored** — 遠端跑（CI / cloud agent）就 skip raw 存在性檢查，並在報告註明
8. **修不動的列 deferred 不硬修** — 內容矛盾、大範圍風格清理要 user 判斷
9. **語言跟 wiki 對齊** — 中文 wiki 用繁中報告，user 明確要求才改
10. **報告 / 範例永遠虛構化** — 不洩任何真實內部 context
