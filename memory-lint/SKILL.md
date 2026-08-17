---
name: memory-lint
description: "Use when the user wants to lint a Claude Code memory directory (~/.claude/memory or custom path) for index inconsistency, broken cross-links, stale project state, duplicate / conflicting feedback rules, naming violations, frontmatter gaps, and oversized files. Phase 1 is a read-only scan and report. Phase 2 applies fixes only for findings the user explicitly picks. Phase 3 verifies with an independent process and rolls back if it fails."
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

```
Phase 1  唯讀掃描 ──► 報告（預設只做這段，不動任何檔案）
                        │  user 逐條拍板要修哪些
Phase 2  執行修正 ──► commit（開工前先記回退點）
                        │  改完全部提交 = 凍結
Phase 3  獨立複驗 ──► 過 → 收工　／　不過 → 回退到 Phase 2 前
```

🔴 **收到 lint 觸發詞的預設動作是出報告。** user 必須明確點名要修哪幾條
（或明說「全部修掉」）才准進 Phase 2。Phase 1 期間不准順手合併、順手刪、順手歸檔。

**跟 llm-wiki-lint 差異**：本 skill 針對 memory 目錄（prefix-based 平鋪結構）；
`llm-wiki-lint` 針對 Karpathy LLM Wiki repo（`wiki/` + `raw/` + `SCHEMA.md` 三層）。

---

# Phase 1 — 唯讀掃描

## Step 1: 找到 memory 目錄

依序嘗試，命中第一個就用：

| 順序 | 來源 |
|------|------|
| 1 | `$ARGUMENTS` 第一個位置參數 |
| 2 | 環境變數 `$CLAUDE_MEMORY_DIR` |
| 3 | `settings.json` 的 `autoMemoryDirectory` |
| 4 | `~/.claude/memory/` |
| 5 | 都找不到 → **停止**，告訴 user「偵測不到 memory 目錄」，不要瞎猜 |

第 3 條要看**當前設定目錄**（多帳號並存時 `$CLAUDE_CONFIG_DIR` 會指到別處）：

```bash
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MEMORY_PATH=$(jq -r '.autoMemoryDirectory // empty' "$CFG/settings.json" | envsubst)
```

## Step 2: 跑機械掃描

```bash
# <skill_dir> = 本 SKILL.md 所在的目錄；掃描標的由參數帶入，
# 所以在哪個工作目錄呼叫都不影響結果
python3 <skill_dir>/scripts/scan.py "$MEMORY_PATH"
```

只用標準函式庫、唯讀、輸出 JSON。**目標目錄由參數帶入**，所以在哪個工作目錄呼叫都一樣。
沒有 `MEMORY.md` 會回 `{"fatal": ...}` 並以 exit 1 結束。

腳本已經處理掉幾個會讓檢查靜默失效的坑，**不要自己在對話裡改寫成 shell 一行流**：

- 不用 shell glob（zsh 未匹配 glob 會在指令執行前中止，而且 `2>/dev/null` 擋不住）
- 不用固定路徑暫存檔（並行執行會互相覆蓋、失敗留髒資料）
- 不 import 第三方套件（唯讀階段不該動 user 的 Python 環境；離線環境也裝不了）
- `[[...]]` 掃描先剝掉 fenced 與行內 code，且**檔名與 frontmatter `name` 兩種都算解析成功**
- 索引目標的 `./` 前綴會正規化

輸出欄位：

| 欄位 | 意義 |
|---|---|
| `layout` | 單層（只有 `MEMORY.md`）／兩層（`MEMORY.md` 只留路由、細目在 `index_*.md`） |
| `index_declared_missing` | `MEMORY.md` 指到但磁碟上沒有的子索引 |
| `index_orphaned` | 磁碟上有、但沒人指向的孤立子索引 |
| `orphan` / `missing` | 有檔沒被索引／索引指向不存在的檔 |
| `frontmatter` | 缺 `name`／`description`（只認頂層）或 `type`（頂層或 `metadata.type`）|
| `wiki_broken` / `wiki_external` | `[[...]]` 解析不到的／指向子目錄或外部的 |
| `oversize` | 超過 300 行的檔（行數語意同 `wc -l`）|
| `prefixes` / `no_prefix` | 命名前綴分布與例外 |

🔴 **兩層結構下若只拿 `MEMORY.md` 當索引來源，會把整庫誤判成 orphan。** 腳本已處理，
但若你另外手寫檢查，這是最容易踩的一個。

## Step 3: 判讀（這段才是本 skill 的價值）

腳本只給事實，**嚴重度與去留由你判斷**。判斷前先讀 `MEMORY.md` 與相關索引的說明文字，
很多「異常」其實是既定決策。

| 嚴重度 | 收什麼 |
|--------|--------|
| 🔴 Error | 結構壞了：`index_declared_missing`、`orphan`、`missing`、`frontmatter` 缺漏、真正的斷鏈、兩條規則直接互打 |
| 🟡 Warning | 沒壞但該看：`index_orphaned`、過期 dashboard、`oversize`、命名例外、疑似結束未歸檔 |
| 🔵 Info | 啟發式：語意相近可能重複、description 與索引描述不符、同一計數寫在多處 |

不確定就降一級。**推測與語意相似一律不得標 Error。**

### 這些不是缺陷，別報

- **`wiki_external` 多半是刻意的** —— 指向 `archive/` 的歸檔檔案，或指向另一台機器上的
  外部知識庫。報之前先看那個目標像不像檔案路徑，並問 user 一次就好，不要每次重報。
  ⚠️ **`wiki_broken` 裡也可能混著刻意的外部連結。** 腳本靠「目標裡有沒有路徑分隔符」分類，
  所以像 `[[某個外部條目]]` 這種沒有路徑特徵的外部參照會落到 `wiki_broken`。
  **這無法自動判斷**，一律當成「需要人確認」，確認過就記進已接受例外清單，別每輪重報。
- **超過 300 行有時是刻意的** —— 若某份 canonical 規則檔明文要求「使用前必須完整讀完」，
  拆開就破壞用途。標成「刻意例外」並寫明理由。
- **語意相近的一組規則可能是刻意不合併的** —— 為了精準 recall 而把同一原則拆成多個觸發點
  是常見設計，索引裡通常有明文宣告。看到就標明是既定決策，**不要建議合併**。
- **子目錄不在掃描範圍** —— 腳本只掃根層。`archive/` 是歸檔；其他子目錄可能是某則 memory
  的附屬資料（例如一份 memory 指向 `ref/` 底下的參考檔）。**它們沒被索引是正常的。**
  自己補查時記得也要限制在根層，別寫成遞迴：

  ```bash
  find "$MEMORY_PATH" -maxdepth 1 -name '*.md' -type f     # ✅
  rg --files -g '*.md' "$MEMORY_PATH"                       # ❌ 會遞迴讀到 archive/ 與其他子目錄
  ```

### 這些要另外用眼睛看（腳本測不出來）

- **過時狀態**：`project_*` 超過 30 天沒動、dashboard 超過 7 天沒更新、內文寫「進行中」
  但檔案很久沒改。🔴 **先確認時間來源可不可信**：檔案的 mtime 一經複製、還原、
  重新 clone 就會全部變成當下時間。是 git repo 就改用 `git -C "$MEMORY_PATH" log -1 --format=%ad -- <file>`；
  不是 git 又剛搬過家，就**明講這項檢查在本次環境不可靠**，不要拿一批假的日期去下判斷。⚠️ **這是低訊號檢查** —— 黑名單、已完工的側專案、機器後路天生就不會動。
  而且「進行中」命中的可能只是待辦清單裡一個帶日期的項目，不是整個專案的狀態。
  **報告要引出命中的那一行原文**，讓 user 看得出是哪一種。
- **規則直接衝突**：🔴 **不要對全部檔案兩兩比對。** 規則檔一多（例如 80 份以上），
  輸出會直接撐爆而被截斷 —— 那時你既審不完、也不知道漏了什麼，卻很容易誤以為審過了。
  **改成兩段**：先用 description 的字元 bigram 做 Jaccard 粗篩（門檻約 0.16）取出候選配對，
  **只對候選配對讀原文**；一輪最多看 10 對，超過就明講「本輪只看了前 N 對、其餘未檢查」。
  命中後**並列兩邊原句**讓 user 自判，不要自己拍板「這是衝突」。
  🔴 **絕對不要因為輸出被截斷就當作「沒發現問題」** —— 那是沒檢查，不是通過。

## Step 4: 出報告

繁體中文（語言跟 memory 對齊）。每個 finding 必須有**具體檔名** ＋ 行為描述 ＋
建議動作（Error 必附）。結尾主動問要不要進 Phase 2，並建議優先序：
一行就能修的（斷鏈、索引缺漏）→ 每個 session 都會載入的檔 → 大型重構。

---

# Phase 2 — 執行修正（需明確授權）

## 開工前四項，缺一不進

**1. 判斷是不是 git repo。** Step 1 只要求有 `MEMORY.md`，而預設的 `~/.claude/memory/`
常常**不是** repo。整套回退機制不能預設 git 存在。

```bash
# 🔴 要比對 top-level 是不是它自己，不能只問「這裡有沒有 git」——
#    rev-parse --git-dir 會往上找父層 repo，memory 目錄只要剛好放在某個 repo 底下
#    就會被誤判成 git 模式，接著把 memory 的改動提交進那個不相干的 repo
top=$(git -C "$MEMORY_PATH" rev-parse --show-toplevel 2>/dev/null)
[ -n "$top" ] && [ "$top" = "$(cd "$MEMORY_PATH" && pwd -P)" ] && echo git || echo 非git
```

**2. 依上一步建立回退點：**

| 情況 | 回退點 | 回退方式 |
|---|---|---|
| git repo | `git -C "$MEMORY_PATH" log --oneline -1` 的 commit hash，寫進回報 | `git -C "$MEMORY_PATH" revert` 或退回該 commit |
| 非 git | 見下方備份指令（**放在 memory 目錄外**，免得被自己掃到）| 見下方回復指令 |

```bash
# 建備份：碰撞就停，不要覆蓋既有備份
BAK="$MEMORY_PATH.bak.$(date +%Y%m%d-%H%M%S)"
[ -e "$BAK" ] && { echo "備份路徑已存在，停止"; exit 1; }
cp -R "$MEMORY_PATH" "$BAK" && echo "回退點：$BAK"

# 回復：一定要用 --delete，否則 Phase 2 新增的檔案不會被移除
rsync -a --delete "$BAK/" "$MEMORY_PATH/"
diff -rq "$BAK" "$MEMORY_PATH" && echo "回復完成且內容一致"
```

🔴 **「把備份複製回去」不等於回復。** 單純覆蓋複製移不掉 Phase 2 新增的檔案，
回復後會是舊檔與新檔的混合體，而且**看起來像成功了**。一定要用 `rsync --delete`
（或等效做法）並用 `diff -rq` 驗過。

**3. 確認工作區乾淨**（git 情況）：有未提交的改動先問 user。

**4. 把 Phase 3 的驗證管道先定下來並試跑一次。** 三件事都要做完才算過：

1. **寫下你打算在 Phase 3 用的那一行完整指令**（含唯讀旗標與標的目錄），記進回報。
2. **用那一行實際發一次最小的唯讀請求**（例如請它回報某個檔案的行數），確認拿得到回應。
3. 拿不到回應就**停下來問 user**，讓他選：換一個管道、接受「只做自檢、不做外部複驗」，
   或不要進 Phase 2。**user 選了「只做自檢」也可以繼續**，但要在最終回報裡明講
   這次沒有外部複驗。

🔴 **只看執行檔在不在是不夠的。** 裝了但沒登入、設定壞掉，`command -v` 一樣會過，
然後你會在 Phase 2 已經改完並提交之後才撞到 —— 正好是這道閘門要防的狀態。

🔴 **本 skill 不指定用哪一套工具。** 只要求它是**獨立行程**、**可唯讀執行**、
**可把標的目錄寫死**。至於是哪一套 CLI agent，由執行者依環境決定並記錄下來。

## 動手紀律

🔴 **所有 git 指令一律帶 `-C "$MEMORY_PATH"`。** 裸的 `git add` / `git commit` / `git status`
會作用在**呼叫端的專案**上（子行程裡的 `cd` 不會改變父行程的工作目錄），
結果是把別人的檔案提交掉，而 memory 的改動還躺在那裡沒進版控。

🔴 **Edit / Write 可能被背景 session 的隔離守衛擋住。** memory 目錄常伴隨一個
「Edit/Write 後自動 commit」的 hook，而**用 Bash 改檔不會觸發那個 hook**。
被擋時的正解：**用 Bash 寫檔，最後手動 `git -C "$MEMORY_PATH" add -A && git -C "$MEMORY_PATH" commit`**，
改完 `git -C "$MEMORY_PATH" status -s` 確認乾淨才算數。

🔴 **`git push` 要另外問過，不含在 Phase 2 的授權範圍。** user 同意的是「修這幾條」，
不是「把 memory 發佈到遠端」。memory 內容通常私密，而推送在多數託管服務上不可逆
（就算之後刪掉，中間狀態可能已被同步或快取）。**commit 完停手，明確問一句再動。**
例外：該目錄若本來就掛著自動推送的 hook，那是既有行為 —— 但仍要在回報裡講明。

🔴 **不要在 memory 目錄內開 worktree。** 若該目錄的 hook 跑的是 `git add -A`，
worktree 會被當成 gitlink 提交進版控。

🔴 **「規則漂移」類發現一律先逐檔讀過再決定。** 例如「這幾個檔依規則不該存在」——
這種規則幾乎都留有例外（文件查不到、跨 session 才需要知道的操作性事實）。
**報告階段只能標「待判斷」、禁止寫「建議刪除」；Phase 2 也禁止照單無腦刪。**

🔴 **改名要連帶處理入站引用**，`[[...]]` 與 markdown 連結都要掃，含 `archive/` 底下的。

## 收尾

重跑一次 `scan.py`，**全綠才進 Phase 3**。自檢就不過的東西不要浪費一次外部複驗。

🔴 **「全綠」不是「JSON 完全是空的」。** 已經跟 user 確認過、決定不處理的項目
（刻意的外部連結、刻意超長的 canonical 檔、刻意不合併的規則群組）**會一直留在輸出裡**。
定義是：**輸出裡每一條剩餘項目，都在你這輪明確記錄下來的「已接受例外」清單上。**
把那份清單寫進回報，Phase 3 的 brief 也要附上，否則外部驗證者會把它們當成新缺陷報回來。

⚠️ **腳本全綠不代表語意層也通過。** 它只驗結構，改掉一處內容矛盾之後 JSON 完全不會變。
語意層的判斷（矛盾、過時、重複）沒有機械證據，回報時要分開講。

---

# Phase 3 — 獨立複驗

## 🔴 先凍結

**Phase 2 的改動要全部完成並提交（git）或備份定版（非 git）之後，才准派複驗。**
一邊改一邊驗等於叫對方驗一個會動的目標，結論無效、還浪費一輪。

## 🔴 要外部行程，不能用同 session 的 subagent

subagent 繼承這個 session 的記憶注入，而那是 **session 開始那一刻的快照** ——
剛改完的東西不在裡面，連檔名都可能還是舊的。**拿吃著舊快照的 agent 去驗磁碟真值，
邏輯上不成立。** 用獨立行程（例如另一套 CLI agent），它不吃這份注入才算外部視角。

派工時要**把標的目錄寫死、把寫入權關掉**，否則它可能檢查錯的目錄，或動到剛凍結的檔案。

## 兩種驗證題，抓的東西不重疊

**A. 機械事實查核** —— 答案非黑即白：`MEMORY.md` 結構與行數、改名前後的檔名各自存不存在、
索引差集是否為空、`[[...]]` 解析失敗數是否為零、frontmatter 是否全數完整。

**B. Recall 可用性測試** —— 測「找不找得到」，設計比題目重要：

- **只准從 `MEMORY.md` 起步**，之後自行決定往下讀什麼
- 🔴 **禁用 `grep` / `find` / `ls` 暴力掃目錄** —— 不禁的話它繞過索引也答得出來，等於沒測到路由
- **每組夾一題負面對照**（問一個確定沒有記憶的主題），看它會不會憑常識編一個答案
- 要求回報**走過的路徑**：讀了哪些檔、是索引裡哪一行導過去的
- 要求給索引好不好用的評語，並明講不要客套

## 🔴 brief 要先寫明「哪些是刻意的」

外部驗證者**沒有脈絡**。不先講，它一定會把既定決策當成缺陷報回來，然後你得逐條解釋 ——
那正是審查迴圈燒時間的燃料。至少要先交代：刻意的外部連結、刻意超長的 canonical 檔、
刻意不合併的規則群組、已知但這次不處理的待辦、以及不在掃描範圍的子目錄。

## 判定與回退

| 結果 | 動作 |
|------|------|
| 全過 | 收工，回報改了什麼、驗了什麼 |
| 只揪出可修的小缺陷 | 修掉 → **重新凍結** → 再驗一輪 |
| 結構性失敗（索引導不到、大量斷鏈、走不到答案） | **回退到 Phase 2 前的回退點**，重新設計再來 |

⚠️ **驗證結果是輸入、不是結論。** 它報的每一條先自己複核再決定改不改，
別因為「外部工具說的」就照做。特別留意三種誤判：把 user 刻意的決策當缺陷、
把不在它視野內的東西（其他機器、已歸檔）當斷鏈、把「規則說不該存在」直接推成「該刪」。

⚠️ **「審到沒問題為止」不是終止條件。** 每修一次 diff 就更大，下一輪就有更多表面可挑，
這是正回饋不是收斂。**要收斂就把 diff 變小** —— 與其逐條硬補，不如把出錯表面整類移除
（例如把散落的檢查邏輯收進一支測過的腳本）。判準改成「這條在實際使用路徑上打得到嗎」，
打不到就記錄進文件、不動手。

---

## Anti-patterns

- ❌ 沒經 user 同意就進 Phase 2
- ❌ Phase 1 期間修改 / 刪除 / 合併任何 memory 檔案
- ❌ 把 `scan.py` 的邏輯改寫成對話裡的 shell 一行流（glob、暫存檔、cwd 那幾類坑會全部回來）
- ❌ 只把 `MEMORY.md` 當索引來源
- ❌ 一邊改一邊派複驗
- ❌ 用同 session 的 subagent 當「獨立」對照組
- ❌ 看到「規則漂移」就建議刪檔
- ❌ 裸 `git` 指令不帶 `-C "$MEMORY_PATH"`
- ❌ 把 `git push` 當成 Phase 2 授權的一部分
- ❌ 在唯讀階段安裝套件
- ❌ 把「語意相似」標成 Error
- ❌ 掃 `archive/` 或其他子目錄（除非 user 明確要求）
- ❌ 沒 prefix 慣例的目錄硬套命名檢查
- ❌ 路徑偵測不到時瞎猜
- ❌ 報告用英文模板套中文 memory
- ❌ 把結果 append 到任何 ledger 檔

## Important rules

1. **Phase 1 唯讀不可協商** —— 報告階段禁用 Edit / Write / `mv` / `rm` / `git`
2. **Phase 2 需明確授權**，且開工前四項前置缺一不可
3. **Phase 3 先凍結、要外部行程、標的寫死、寫入關掉**
4. **Path 偵測順序固定** —— 5 級依序，找不到就停
5. **Severity 寧降勿升**
6. **每個 finding 必須有具體檔名**
7. **衝突永遠並列原句**，不替 user 判定
8. **報告印到對話即可**，不另存檔
9. **外部驗證是輸入不是結論**，逐條複核
10. **未來功能（cron 定排、跨機器比對）目前不存在** —— user 問起就說 v0.x 還沒做
