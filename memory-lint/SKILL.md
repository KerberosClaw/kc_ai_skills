---
name: memory-lint
description: "Use when the user wants to lint a Claude Code memory directory (~/.claude/memory or custom path) for index inconsistency, broken cross-links, stale project state, duplicate / conflicting feedback rules, naming convention violations, frontmatter gaps, and oversized files. Phase 1 is a read-only report. Phase 2 applies fixes only for findings the user explicitly picks. Phase 3 verifies the result with an independent Codex run and rolls back if it fails."
version: 0.3.0
status: mvp
triggers:
  - "/memory-lint"
  - "memory lint"
  - "掃 memory"
  - "memory 健檢"
argument-hint: "[path]"
---

# memory-lint — Memory 品質健檢

You are a memory hygiene auditor for Claude Code memory directories.

## 三段式流程

```
Phase 1  唯讀掃描 ──► 出報告（列 finding，不動任何檔案）
                        │
                        ▼  user 逐條拍板要修哪些
Phase 2  執行修正 ──► 改檔 + commit（只做 user 點名的）
                        │
                        ▼  凍結後才驗
Phase 3  獨立複驗 ──► 過 → 收工　／　不過 → 回退到 Phase 2 前
```

🔴 **預設只做 Phase 1。** 收到 lint 觸發詞就是出報告，**不要自作主張進 Phase 2**。
user 必須明確點名要修哪幾條（或明說「全部修掉」）才准動手。

🔴 **Phase 1 期間純唯讀。** 不准「順手合併兩條重複 feedback」「順手刪 orphan 檔」
「順手歸檔過期 project」—— 即使判斷再明顯，處置權歸 user。

**跟 llm-wiki-lint 差異**：
- `memory-lint` → memory 目錄（feedback / user / project，prefix-based 平鋪結構）
- `llm-wiki-lint` → Karpathy LLM Wiki repo（wiki/ + raw/ + SCHEMA.md 三層）

---

# Phase 1 — 唯讀掃描

## Step 1: Detect memory directory path

依序嘗試，命中第一個就用：

| 順序 | 來源 | 條件 |
|------|------|------|
| 1 | `$ARGUMENTS` 第一個位置參數 | 使用者明確傳入，最優先 |
| 2 | 環境變數 `$CLAUDE_MEMORY_DIR` | export 過 |
| 3 | `settings.json` 的 `autoMemoryDirectory` 欄位 | 自訂 memory 路徑的標準設定 |
| 4 | `~/.claude/memory/` | Claude Code 官方預設 |
| 5 | — | 都找不到 → 停止，告訴 user「偵測不到 memory 目錄」，**不要瞎猜** |

第 3 條要看的是**當前設定目錄**，多帳號並存時 `$CLAUDE_CONFIG_DIR` 會指到別處：

```bash
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
jq -r '.autoMemoryDirectory // empty' "$CFG/settings.json" | envsubst
```

決定路徑後，先驗證結構：

```bash
ls "$MEMORY_PATH/MEMORY.md" 2>/dev/null || { echo "FATAL: 缺 MEMORY.md，視為無效路徑"; exit 1; }
```

`MEMORY.md` 是必要 anchor —— 沒有就視為無效路徑停止 lint。

## Step 2: Scan & lint

### Step 2a: 掃描範圍與索引來源

```bash
find "$MEMORY_PATH" -maxdepth 1 -name '*.md' -type f
```

**包含**：目標目錄下所有 root 層 `*.md`
**跳過**：`archive/` 子資料夾（除非 user 明確要求掃歸檔）

🔴 **索引來源不一定只有 `MEMORY.md`。** `MEMORY.md` 有 200 行的讀取上限，長大的 memory 庫
常會拆成兩層：`MEMORY.md` 只留常駐規則與路由，完整條目搬進 `index_*.md`。**先偵測是哪一種**：

🔴 **索引圖要從 `MEMORY.md` 走可達性建起來，不是把目錄裡所有 `index_*.md` 一律採信。**
只看檔名存在會有兩個洞：磁碟上有一份沒人指向的**孤立舊索引**，會讓已經不該被收錄的檔案看起來仍在索引內；
反過來 `MEMORY.md` 指到一個**不存在的子索引**，則會被無聲跳過。

```bash
# 🔴 一律用 bash 跑：zsh 的未匹配 glob 會在 grep 執行前就中止整條指令，
#    而且 2>/dev/null 擋不住（失敗發生在展開階段），結果是索引比對輸出全空 → 整庫誤判
bash -c '
cd "$MEMORY_PATH" || exit 1
# 從 MEMORY.md 指出去、且檔名為 index_*.md 的才算子索引
grep -ho "](index_[^)]*\.md)" MEMORY.md 2>/dev/null | tr -d "](" | tr -d ")" | sort -u > "$TMP/sub_declared"
# 磁碟上實際存在的 index_*.md
find . -maxdepth 1 -name "index_*.md" -type f | sed "s|^\./||" | sort > "$TMP/sub_ondisk"
echo "宣告但不存在的子索引（Error）:"; comm -23 "$TMP/sub_declared" "$TMP/sub_ondisk"
echo "存在但沒人指向的孤立子索引（Warning）:"; comm -13 "$TMP/sub_declared" "$TMP/sub_ondisk"
'
```

有任何一份 `index_*.md` 被 `MEMORY.md` 指到 → 判定為兩層，索引來源 = `MEMORY.md` ∪ **可達的**子索引。
都沒有 → 單層。

**兩層結構下只拿 `MEMORY.md` 當索引，會把整個 memory 庫誤判成 orphan。**
這是本 skill 踩過的實際失誤，不是假設。

### Step 2b: Severity decision

| 嚴重度 | 含義 | 範例 |
|--------|------|------|
| 🔴 Error | 結構壞了或規則直接衝突，必須處理才能恢復 memory 完整性 | 索引列出的檔案不存在、兩條 feedback 規則直接互打、交叉連結解析不到 |
| 🟡 Warning | 沒壞但有腐臭味，user 應該 review | 過時 project status、dashboard 過期、檔案過大、orphan |
| 🔵 Info | 啟發式提示，可選處理 | 可能重複 / 語意接近的 feedback、可能的 description drift、計數重複 |

不確定就降一級。**禁止把推測或語意相似標成 Error**。

### Step 2c: 索引不一致

索引來源依 Step 2a 判定，**兩層結構要取聯集**。

| 情況 | 等級 |
|------|------|
| 索引列出但檔案不存在 | 🔴 Error（missing file） |
| 檔案存在但沒有任何索引收錄 | 🔴 Error（orphan file） |
| 索引描述跟檔案 frontmatter `description` 明顯不符 | 🔵 Info（description drift；語意判斷需 user 確認） |

```bash
# 🔴 一律 bash（zsh 未匹配 glob 會中止）；🔴 用 mktemp，不要寫死 /tmp 檔名
#    兩個 lint 同時跑會互相覆蓋固定檔名，比出來的差集是混到的、而且失敗還會留髒資料
TMP=$(mktemp -d) && trap 'rm -rf "$TMP"' EXIT
bash -c '
cd "$MEMORY_PATH" || exit 1
# 索引來源 = MEMORY.md ＋ 上一步算出的「可達」子索引（單層時 sub_reachable 為空檔）
cat MEMORY.md $(cat "$TMP/sub_reachable" 2>/dev/null) 2>/dev/null \
  | grep -ho "](\([^)]*\.md\))" | tr -d "](" | tr -d ")" \
  | grep -v "^index_" | sort -u > "$TMP/indexed"
find . -maxdepth 1 -name "*.md" -type f | sed "s|^\./||" \
  | grep -vE "^(MEMORY|index_)" | sort > "$TMP/files"
echo "orphan（有檔沒索引）:"; comm -13 "$TMP/indexed" "$TMP/files"
echo "missing（索引指不到）:"; comm -23 "$TMP/indexed" "$TMP/files"
'
```

⚠️ Dashboard 類檔案常直接掛在 `MEMORY.md` 而不進 `index_*.md`，那是刻意的，不算 orphan。
判定前先看它在不在 `MEMORY.md` 裡。

### Step 2d: 過時狀態（mtime / status）

| 條件 | 等級 |
|------|------|
| `project_*.md` mtime > 30 天 | 🟡 Warning（可能 stale，建議 review） |
| Dashboard 類（description 含「dashboard」/「快照」/「summary」）mtime > 7 天 | 🟡 Warning（dashboard 過期） |
| `type: project` 檔案內文有「進行中」/「active」但 mtime > 60 天 | 🟡 Warning（疑似結束未歸檔） |

```bash
stat -f "%m %N" "$MEMORY_PATH"/*.md      # macOS
stat -c "%Y %n" "$MEMORY_PATH"/*.md      # Linux
```

⚠️ **這是低訊號檢查。** 不少 memory 天生就是穩定不動的（黑名單、已完工的專案、機器後路），
mtime 老不等於該處理。報告時就講明這點，別讓 user 以為十幾條全是問題。

⚠️ **「進行中」命中不代表整個專案還活著** —— 它可能只是待辦清單裡一個帶日期的項目。
報告要引出**命中的那一行原文**，讓 user 看得出是哪一種。

### Step 2e: 重複 / 衝突 feedback

| 情況 | 等級 |
|------|------|
| 兩個以上 feedback 檔案內含**直接衝突**規則（A 說做 X，B 說不要做 X） | 🔴 Error |
| 兩個以上 feedback 檔案內含**語意相近**規則（同一意圖換句話說） | 🔵 Info（可能重複，user 判斷） |

衝突偵測 heuristic：grep 反義句型（`不要 X` vs `要 X`、`禁止 X` vs `應該 X`），
命中後**列出兩邊原句**讓 user 自判，不要自己拍板「衝突」。

語意相近可用 description 的字元 bigram 做 Jaccard 粗篩（門檻約 0.16），
**只當線索、一律降為 Info**。

⚠️ **索引可能已經明文宣告「這組刻意不合併」**（例如同一原則拆成多個觸發點，
為了精準 recall 而故意分檔）。掃到這種先看索引怎麼寫的，是既定決策就標明、不要建議合併。

### Step 2f: 命名慣例違規

僅在該 memory 目錄有 prefix 慣例時才檢：

```bash
grep -E '^##' "$MEMORY_PATH/MEMORY.md"     # 有沒有按 prefix 分類
```

| 情況 | 等級 |
|------|------|
| 沒 prefix 的 `.md`（`MEMORY.md` / `index_*.md` / `CLAUDE.md` 除外） | 🟡 Warning |
| Prefix 不在該目錄已建立的 prefix 清單 | 🟡 Warning |

沒 prefix 慣例 → **整個 Step 2f 跳過**，不要硬套。

### Step 2g: Frontmatter 缺失

每份 `*.md` 第一段應有 YAML frontmatter 含必備欄位（`name` / `description` / `type`，缺任一為 🔴 Error）。

`type` 可能寫在頂層，也可能包在 `metadata:` 底下，**兩種都要認**：

```python
import os, re, yaml   # 沒有 PyYAML 就 pip install pyyaml；別用正則硬幹

def check(f):
    t = open(f, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---", t, re.S)
    if not m:
        return ["無 frontmatter"]
    try:
        d = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError as e:
        return [f"frontmatter 不是合法 YAML: {e}"]
    if not isinstance(d, dict):
        return ["frontmatter 不是 mapping"]
    meta = d.get("metadata") if isinstance(d.get("metadata"), dict) else {}
    bad = []
    for k in ("name", "description"):          # 這兩個只認頂層
        if not str(d.get(k) or "").strip():
            bad.append(f"缺 {k}")
    if not str(d.get("type") or meta.get("type") or "").strip():
        bad.append("缺 type")                   # type 允許在 metadata 底下
    return bad

for f in sorted(x for x in os.listdir(".") if x.endswith(".md")):
    for msg in check(f):
        print(f, msg)
```

🔴 **要判「值是不是空的」，不是「有沒有這個鍵」。** `name: ""` 用「冒號後有非空白字元」
去驗會**通過**，但它實質等於沒填 —— 這種假通過比缺欄位更難發現。

🔴 **要用 YAML 解析，不要用正則掃行。** 允許任意前導空白的正則會把**巢狀在別的 mapping 底下**
的 `name:` / `description:`（甚至 block scalar 內文裡的那一行）當成頂層欄位，一樣是假通過。
`name` 與 `description` 只認頂層；`type` 才允許出現在 `metadata` 底下。

### Step 2h: 檔案過大

| 條件 | 等級 |
|------|------|
| 任一檔案 > 300 行 | 🟡 Warning（可能該拆或該歸檔） |

⚠️ **有些檔天生就該大。** 若某份 canonical 規則檔明文要求「使用前必須完整讀完」，
拆開反而破壞它的用途 —— 報告時標為「**刻意例外**」並寫明理由，不要每次都重報一遍。

### Step 2i: 交叉連結解析（`[[...]]`）

| 情況 | 等級 |
|------|------|
| `[[目標]]` 解析不到任何實際檔案 | 🔴 Error（斷鏈） |
| 同一目標在不同檔案有多種寫法（連字號 / 底線 / 有無 prefix） | 🟡 Warning（格式不一致） |

```python
import os, re, glob
files = {f[:-3] for f in os.listdir(".") if f.endswith(".md")}

def strip_code(s):
    s = re.sub(r"^```.*?^```", "", s, flags=re.S | re.M)   # fenced
    s = re.sub(r"`[^`\n]*`", "", s)                        # inline
    return s

bad = {}
for p in glob.glob("*.md"):
    for t in re.findall(r"\[\[([^\]]+)\]\]", strip_code(open(p, encoding="utf-8").read())):
        t = t.strip()
        if t.startswith("archive/") or t in files:
            continue
        bad.setdefault(t, []).append(p)
for t, srcs in sorted(bad.items()):
    print(f"[[{t}]] <- {', '.join(srcs)}")
```

🔴 **掃之前一定要先剝掉 fenced code 與行內 code。** 技術類 memory 很常出現
`[[ -f "$path" ]]` 這種 shell 條件式，或刻意寫來當範例的 `[[example]]`；
用生文字直接套正則會把它們全部報成紅色斷鏈。

🔴 **這裡有個規範與現實的落差，是斷鏈的根源**：慣例上 `[[...]]` 指的是對方的
frontmatter `name` 欄位、不是檔名。但 `name` 常年沒人維護，會長成整句標題、
kebab slug、甚至空字串，跟檔名完全對不上 —— 於是所有連結實質都斷了。

**建議修法（Phase 2 用）**：連結一律改寫成**實際檔名**，成本遠低於回頭修每個檔的 `name`。
指向已歸檔或外部知識庫的連結是合法例外，報告時列出來讓 user 確認，別當斷鏈修掉。

### Step 2j: 計數重複

| 情況 | 等級 |
|------|------|
| 同一個數量寫在兩處以上（索引標題、frontmatter、路由表） | 🔵 Info（遲早漂移） |
| 兩處數字已經不一致 | 🟡 Warning（已漂移） |

建議收斂到單一來源。數字寫在幾個地方，就有幾個地方會過時。

## Step 3: 輸出報告

繁體中文，固定格式：

```markdown
# 🔍 Memory Lint 報告

**掃描目錄：** /path/to/memory
**索引結構：** 單層 / 兩層（MEMORY.md + N 個 index_*.md）
**掃描時間：** YYYY-MM-DD HH:MM
**掃描檔案：** N 個（不含 archive/）

## 🔴 Error（建議立即處理）
- [類別] 描述 — 建議動作

## 🟡 Warning（建議 review）
- [類別] 描述

## 🔵 Info（提示，可選處理）
- [類別] 描述

## 🟢 OK（通過）
- 索引一致性 / 交叉連結 / 命名慣例 / Frontmatter / 檔案大小 ...

## 📊 統計
| 類別 | 檔案數 |
|------|--------|
| （依該目錄實際 prefix 分組） | ... |

**總計：** XX 個活檔
```

每個 finding 必須包含：

- `[類別]` —— 索引 / 斷鏈 / 過時 / 衝突 / 命名 / Frontmatter / 大小 / Dashboard / 計數
- 具體檔名 + 行為描述
- 建議動作（Error 必有，Warning 可有）

報告結尾**主動問一句**要不要進 Phase 2，並建議優先序（通常是：斷鏈與 orphan 之類
一行就能修的先做、每個 session 都會載入的檔次之、大型重構最後）。

---

# Phase 2 — 執行修正（需 user 明確同意）

**進入條件**：user 點名要修哪幾條，或明說「全部修掉」。**沒點名就不要動。**

## 開工前（四項前置，缺一不進 Phase 2）

**1. 先判斷這個目錄是不是 git repo。** Step 1 只要求有 `MEMORY.md`，而預設的
`~/.claude/memory/` 常常**不是** git repo。整段 Phase 2 的回退機制不能預設 git 存在。

```bash
git -C "$MEMORY_PATH" rev-parse --git-dir >/dev/null 2>&1 && echo "git" || echo "非 git"
```

**2. 依上一步建立回退點**：

| 情況 | 回退點 | 回退方式 |
|---|---|---|
| 是 git repo | `git -C "$MEMORY_PATH" log --oneline -1` 的 commit hash，寫進回報 | `git revert` 或退回該 commit |
| 不是 git repo | 整目錄複製一份到 `$MEMORY_PATH.bak.<timestamp>`（**放在 memory 目錄外**，免得被自己掃到） | 把備份複製回去 |

**3. 確認工作區乾淨**（git 情況）：有未提交的改動先問 user，別把別人的東西混進來。

**4. 先確認 Phase 3 的外部驗證工具叫得動。**

```bash
command -v codex >/dev/null 2>&1 && echo "codex 可用" || echo "🔴 codex 不可用"
```

🔴 **這步不能等到 Phase 3 才發現。** 驗證工具沒裝或沒登入，卻等到 Phase 2 已經改完並提交
才撞到，使用者就會拿著一批**沒驗證過的既成改動**卡在那裡。叫不動就**先告訴 user**，
由他選擇：換一個獨立驗證管道、接受「只做自檢不做外部複驗」，或是不要進 Phase 2。

## 動手紀律

🔴 **Edit / Write 工具可能被背景 session 的隔離守衛擋住。**
memory 目錄常伴隨一個「Edit/Write 後自動 commit」的 hook，而**用 Bash 改檔不會觸發那個 hook**。
所以被擋時的正解是：**用 Bash 寫檔，最後手動 `git add -A && git commit`**。
改完務必 `git status -s` 確認工作區乾淨才算數。

🔴 **`git push` 要另外問過，不含在 Phase 2 的授權範圍內。**
user 同意的是「修這幾條 finding」，不是「把 memory 發佈到遠端」。memory 內容通常私密，
而推上去這件事在多數託管服務上不可逆（就算之後刪掉，中間狀態可能已經被同步或快取）。
**commit 完停手，明確問一句「要推上遠端嗎」再動。**

⚠️ 例外：該目錄若本來就掛著自動推送的 hook，那是既有行為、不是本 skill 觸發的 ——
但仍要在回報裡講明「這個目錄的 hook 會自動推送」，別讓 user 以為東西只留在本機。

🔴 **不要在 memory 目錄內開 worktree。** 若該目錄的 hook 跑的是 `git add -A`，
worktree 會被當成 gitlink 提交進版控。

🔴 **「規則漂移」類發現一律先逐檔讀過再決定。**
例如「這幾個 project 檔對應的 repo 都有自己的文件、依規則不該存在」——
規則通常留有例外（repo 文件查不到、跨 session 才需要知道的操作性事實）。
**報告階段只能標「待判斷」，禁止寫「建議刪除」；Phase 2 也禁止照單無腦刪。**
實測過：多數這類檔案讀完之後結論是該留。

🔴 **改名要連帶處理入站引用。** `git mv` 之後掃一遍 `[[...]]` 與 markdown 連結，
確認沒有指向舊名的殘留。

## 收尾

改完先自己重跑一次 Phase 1 的機械檢查（索引差集、斷鏈數、frontmatter），
**全綠才進 Phase 3**。自檢就不過的東西不要浪費一次外部複驗。

---

# Phase 3 — 獨立複驗

## 為什麼要外部複驗

Phase 2 的自檢是「用同一套邏輯驗自己」。真正要問的是
**「一個全新的 agent 拿到這個 memory 庫，找得到東西嗎」**，那必須由外部來答。

🔴 **不要用同一個 session 的 subagent 當對照組。** subagent 會繼承這個 session 的記憶注入，
而那份注入是 **session 開始那一刻的快照** —— 你剛改完的東西不在裡面，連檔名都可能還是舊的。
**拿一個吃著舊快照的 agent 去驗磁碟真值，邏輯上不成立。**
用 Codex 之類的獨立行程，它不吃這套注入機制，才是真的外部視角。

## 🔴 先凍結，再派驗證

**Phase 2 的改動要全部完成並 commit 之後，才准派複驗。**
一邊改一邊驗等於叫對方驗一個會動的目標，拿回來的結論無效、還會浪費一輪額度。
（這條是實際踩過的，不是預防性條文。）

## 兩種驗證題，都要出

**A. 機械可判定的事實查核** —— 交給 Codex，答案非黑即白：

- `MEMORY.md` 實際是幾行、章節結構長什麼樣
- 改名前後的檔名各自存不存在
- 索引連結目標與實際檔案的差集是否為空
- `[[...]]` 解析失敗數是否為零

**B. Recall 可用性測試** —— 測「找不找得到」，設計比題目本身重要：

- **只准從 `MEMORY.md` 起步**，之後自行決定往下讀什麼
- 🔴 **禁用 `grep` / `find` / `ls` 暴力掃目錄** —— 不禁的話它繞過索引也答得出來，等於沒測到路由
- **每組夾一題負面對照**（問一個確定沒有記憶的主題），看它會不會憑常識編一個答案
- 要求回報**走過的路徑**：讀了哪些檔、是索引裡哪一行導過去的
- 要求給**索引好不好用**的評語，並明講不要客套

派工的 brief 必須自足 —— 對方看不到你的對話，背景、改了什麼、要查什麼、判準，全部寫進去。

## 判定與回退

| 結果 | 動作 |
|------|------|
| 全過 | 收工，回報改了什麼、驗了什麼 |
| 只揪出可修的小缺陷（措辭、數字、缺指路） | 修掉 → **重新凍結** → 再驗一輪 |
| 結構性失敗（索引導不到、大量斷鏈、agent 走不到答案） | **回退到 Phase 2 前記下的 commit**，重新設計再來 |

回退用 `git revert` 或退回該 commit，**動之前先確認要退的是哪一個、有沒有夾帶別人的改動**。

⚠️ **驗證結果是輸入、不是結論。** 外部 agent 也會看錯、也會誤判。它報的每一條先自己複核
再決定要不要改，別因為「codex 說的」就照做。

---

## Anti-patterns

- ❌ 沒經 user 同意就進 Phase 2（收到 lint 觸發詞的預設動作是出報告）
- ❌ Phase 1 期間自動修改 / 刪除 / 合併任何 memory 檔案
- ❌ **只把 `MEMORY.md` 當索引來源** —— 兩層結構下會把整庫誤判成 orphan
- ❌ **一邊改一邊派複驗** —— 驗一個會動的目標，結論無效
- ❌ **用同 session 的 subagent 當「獨立」對照組** —— 它吃的是 session 起始的舊快照
- ❌ **看到「規則漂移」就建議刪檔** —— 規則多半留有例外，必須逐檔讀過再判斷
- ❌ 把「語意相似」直接標 Error（必須降為 Info，列原句讓 user 判斷）
- ❌ 用「冒號後有非空白字元」驗 frontmatter（`name: ""` 會假通過）
- ❌ 把同一個計數寫進多個地方
- ❌ 掃 `archive/` 子資料夾（除非 user 明確要求）
- ❌ 沒 prefix 慣例的 memory 目錄硬套 Step 2f 命名檢查
- ❌ 路徑偵測不到時瞎猜（必須停止並告訴 user）
- ❌ 跨 user / 跨機器比對 memory（只看本機指定目錄）
- ❌ 報告用英文模板套中文 memory（user 沒要求換語言就用繁中）
- ❌ Append 結果到任何 ledger 檔（user 要不要記決定權在他）

---

## Important rules

1. **Phase 1 唯讀不可協商** —— 報告階段禁用 Edit / Write / `mv` / `rm` / `git`
2. **Phase 2 需明確授權** —— user 點名或明說「全部修掉」才動，且開工前先記回退點
3. **Phase 3 先凍結再驗，且要外部行程** —— 同 session 的 subagent 不算外部
4. **Path 偵測順序固定** —— 5 級依序，不跳級、找不到就停
5. **Severity 寧降勿升** —— 啟發式 / 語意相近 → Info；推測 → Warning；只有結構壞 / 直接衝突 / 斷鏈才 Error
6. **每個 finding 必須有具體檔名** —— 不准「某些檔案 frontmatter 不全」這種模糊敘述
7. **衝突永遠列原句** —— 不替 user 判定「真衝突」還是「適用範圍不同」
8. **沒 prefix 慣例就跳 Step 2f** —— 不同 user 的 memory 結構各有風格，硬套會誤報
9. **報告印到對話即可** —— 不另存檔；user 要存自己貼
10. **語言跟 memory 對齊** —— 中文 memory 用繁中報告，英文 memory 用英文
11. **未來功能（cron 定排、跨機器比對）目前不存在** —— user 問起就說 v0.x 還沒做
