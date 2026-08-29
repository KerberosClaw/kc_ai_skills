---
name: wrap-up
description: "Use ONLY when the user's latest message explicitly contains the `/wrap-up` command. Harvests everything a long session produced into the project following that project's own rules — moves stray media in, wires two-way refs, updates indexes, merges drafts into SSOT — then dispatches a context-free sub-agent to blind-test the docs from the project's entry file. NEVER load on inferred intent. Explicitly NOT for: save / checkpoint / persona-continuity requests, memory or journal updates, compact lifecycle hooks (PreCompact, PostCompact, SessionStart(source=compact)), automatic or manual compaction, or any guess that the session is ending — those all mean 'save state and keep going', while this skill has heavy side effects (moves files, rewrites indexes, edits SSOT, spawns sub-agents). If the user seems to want the full flow, ask them to type `/wrap-up` instead of assuming. NOT a documentation linter (that is llm-wiki-lint / memory-lint) and NOT for tidying a project you did not just work on."
version: 0.2.0
status: experimental
triggers:
  - "/wrap-up"
argument-hint: "[repo path]"
---

# wrap-up — 把這次 session 的產出收進專案，然後盲測驗收

## 🔴 Entry gate：沒有明確的 `/wrap-up` 就不准動

**只有使用者最新一則訊息裡明確出現 `/wrap-up` 指令時才能往下執行。** 語意相近的說法、你自己推論出來的意圖，都不算數。

以下訊號**一律不是**啟動條件。它們的意思都是「保存狀態後繼續」，不是「session 要結束了」：

- 存檔、保存、記住、落盤、落檔、收工、收尾、整理一下專案文件
- checkpoint、persona checkpoint、寫 journal、更新 continuity
- `PreCompact` / `PostCompact` / `SessionStart(source=compact)` 這類 compact 生命週期 hook
- 自動或手動 compact、compact 前保存未落盤的狀態、compact 後重載人格基線
- 使用者說「等一下還要繼續」，或你自己推測他大概要離開了

**沒看到指令就 fail closed**：不讀檔、不盤點、不搬檔、不改檔、不派 sub-agent，直接回去做使用者原本要求的事。判斷他可能真的想要完整流程時，請他自己輸入 `/wrap-up`，不要代他決定。

> **為什麼正文還要再擋一次**：路由器是看 frontmatter 的 `description` 與 `triggers` 決定載入哪顆 skill，收窄那兩個欄位只能降低被錯選的機率，不能歸零。而這顆 skill 一跑就會盤點整個 repo、搬檔、改索引、動 SSOT、派 agent，副作用重到不該由「存個 checkpoint」這種弱訊號啟動，所以正文必須能自己把它擋下來。

You are a session harvester. 一次長對話會產出散在各處的東西：改到一半的檔、只活在對話裡的判定、丟在桌面的媒體、寫了沒併回 SSOT 的草稿。**你的工作是把它們收進專案，接好互相引用，然後證明下一個人接得住。**

判準不是「文件看起來整齊」，是**行為性的**：派一個全新、沒有脈絡的 sub-agent 從專案入口檔開始讀，它答得出情境題才算完成。

**CRITICAL — 這個 skill 的存在理由**：使用者花好幾個小時得到的結論，如果只活在對話裡或散在 repo 外，下一個 session 會從零重推一次，甚至因為找不到檔案而讓產出白費。

## 🔴 停止句與分級授權（P17）

**這個 skill 是分級的，不是兩段式的。** 使用者喊它的時機正是他要離開，全部停下來等點頭等於逼他留下。

| 動作類型 | 授權 |
|---|---|
| 搬檔進 repo、接 ref、更新索引、補 log、修斷連結、建缺漏的目錄 | ✅ **直接做**（可逆，且照專案既有規則） |
| 🔴 **刪除任何東西** | ❌ **必須先問** |
| 🔴 **改寫既有敘述的語意**（不只是補註記） | ❌ **必須先問** |
| 🔴 **判斷不明、兩種做法都說得通** | ❌ **必須先問** |
| 🔴 **在沒有入口檔的 repo 建入口檔** | ⚠️ 見 Step 4a（建了要復原） |

**不阻塞條款**：背景／無人值守場景（使用者本來就不在）→ 需要問的項目**一律跳過不做**，列進最終報告的「等你決定」欄。**不要自行代決。**

## Step 1: 定位與盤點

### 1a. 找專案

參數有路徑就用它，否則用當前 repo 根目錄。

### 1b. 讀專案自己的規矩 —— **MANDATORY，不可跳過**

🔴 **這個 skill 不帶自己的目錄規範。** 一律照專案的：

> **這條的一般化版本：要寫任何東西進一個 repo 之前，先找那個 repo 對「這類東西」的既有寫法。**
> 檔案放哪、索引怎麼加、摘要放頂還是放底、commit 訊息什麼語言 —— 這些都有既定答案，
> 而「憑常理推論」得到的通常跟它不一樣。**推論出來的格式看起來合理，但它跟旁邊的東西不一致，
> 就是下一個人困惑的來源。** 查一次的成本遠低於改一次。


```bash
for f in CLAUDE.md AGENTS.md README.md SCHEMA.md index.md CONTRIBUTING.md; do
  [ -f "$f" ] && echo "=== $f ===" && head -60 "$f"
done
```

要從中抽出：**檔案放哪裡、索引在哪、log 慣例、commit 規則、有沒有 keeper／成品的存放約定。**

⚠️ **`CLAUDE.md` 與 `AGENTS.md` 都存在時**：兩份都讀，**比對描述有沒有互相矛盾**。矛盾就是本次要順手修的項目之一（記進報告，修法照「改寫既有敘述要先問」的分級）。
同理適用雙語 README（`README.md` / `README_zh.md`）不同步。

### 1c. 盤點這次 session 產出了什麼

三個來源，由便宜到貴：

```bash
git status --short                    # 未 commit 的
git log --oneline "@{u}..HEAD"        # 已 commit 未推的
find . -newermt "12 hours ago" -type f -not -path "./.git/*" | head -40
```

加上**你自己的記憶**：這次對話裡使用者拍板了什麼、你查證出什麼結論、哪些還只活在對話裡。

🔴 **repo 外的媒體也要找**（最常被漏掉的一類）：對話中出現過的 `~/Desktop`、`/tmp`、`~/Downloads` 路徑，逐一確認還在不在、該不該進 repo。

⚠️ **已經被 compact 過、記憶不完整時**：對話紀錄檔在
`~/.claude/projects/<cwd 轉義>/<session-id>.jsonl`，可回頭抽。**但它很大（可達數百 MB），只在必要時讀，且要過濾**，不要整檔載入。

## Step 2: 落檔

### 2a. 搬媒體

照 Step 1b 讀到的專案規則決定去處。**不要自己發明目錄。**

🔴 **一律用 `cp -p` 或 `rsync -a` 保留 mtime。**

> 檔案時間戳本身就是證據。當一串中間產物沒有任何文字紀錄時，mtime 可能是唯一能重建順序的線索 ——
> 用普通 `cp` 複製會把它抹掉。

### 2b. 🔴 草稿併進 SSOT —— **沒併就等於沒寫**

掃出 `*draft*`／`*_wip*`／`findings_*`／`TODO` 裡「待審」「待併」的項目，逐條確認**是否已進正式文件**。

> 這條是真的翻過車：一批查證結論寫進草稿就沒下文，過些日子同一個人把其中一條重新踩了一次 ——
> **寫下那條規則的人，就是後來違反它的人。**

### 2c. 判定寫進配方

使用者拍板的判斷（「這張可以」「那個不行」「用 A 不用 B」）要寫進**對應成品的說明檔**，不能只留在對話或 log。下一個 session 讀得到的是檔案，不是對話。

## Step 3: 接 ref 與結構檢查

### 3a. 雙向 ref

**單向連結等於沒連。** A 提到 B，B 也要指得回 A。

### 3b. 更新索引

專案的 `index.md`／`INDEX.md`／README 表格 —— 照它既有格式加，不要另立新格式。

### 3c. 結構檢查

檢查項目（借用 `llm-wiki-lint` 的清單，但**本 skill 自己做、不呼叫它** —— 它是報告型、有自己的核准閘門，且判準是結構性的，照它做完仍可能過不了 Step 4 的盲測）：

- 斷連結：markdown 連結指向不存在的檔
- 孤兒：沒有被任何文件連到的文件（⚠️ 以**目錄**被連到的不算孤兒）
- 過時敘述：提到已刪除／已搬走的路徑
- 索引與現實不符

完整檢查腳本見 [`references/lint_checks.md`](references/lint_checks.md)。

⚠️ **已知的維護伏筆**：那支腳本的斷連結掃描，與 `llm-wiki-lint` 的掃描邏輯概念重複
（範圍不同：這支掃全 repo、那支只掃 `wiki/`）。**其中一份修了 bug，另一份不會跟著修。**
之後若要共用，共用的應該是「掃描邏輯」，不是「決定要不要修」那段 —— 後者的契約兩邊本來就不同。

## Step 4: 🔴 盲測 —— 這一步才是驗收

### 4a. 決定起點

優先序：`CLAUDE.md` → `AGENTS.md` → `README.md`。

**三個都沒有** → 建一份**最小 `AGENTS.md`**（跨工具慣例，Codex／Cursor 都吃），`CLAUDE.md` 只寫一行指過去。

🔴 **建完必須確認要不要留**：

```bash
git check-ignore -v AGENTS.md CLAUDE.md   # 有輸出 = 被 ignore
```

**被 gitignore、或該專案本來就刻意沒有** → **測完必須復原（刪掉）**，並把草稿全文附在最終報告裡讓使用者自己決定收不收。**不要在沒邀請你的 repo 留下痕跡。**

### 4b. 判專案形態並出題

四型與各自的出題骨架見 [`references/project_types.md`](references/project_types.md)。

🔴 **形態偵測不能只看資料夾結構** —— 韌體、前端、非 Python 的程式專案光看目錄認不出來。**一律用「資料夾結構 ＋ 入口檔內容」二次判斷**，兩者矛盾時以入口檔為準。認不出來就**問使用者**。

題目來源混合：

| 來源 | 佔比 | 內容 |
|---|---|---|
| **這次 session 的決定** | 主要 | 使用者拍板了什麼、查證出什麼結論 —— 這正是下次不該重推的東西 |
| **專案入口檔的路由** | 次要 | 從 `CLAUDE.md` 的路由表／`index.md` 抽主題 |
| **題庫迴歸題** | 有就加 | `.claude/wrapup_quiz.md`（見 [`references/quiz_bank.md`](references/quiz_bank.md)）|

**每次 3–6 題**，其中**固定必考一題**：

> 「只讀這些，你**知不知道自己還缺什麼**？」

> 這題最能抓出假的 self-contained。曾經有一份文件開頭寫著「照這份走就夠了」，
> 盲測 agent 照它做完之後直接指出那句是假的，並列出它其實還缺的東西。
> 補上誠實的邊界說明之後，同一份文件就過了 ——
> **內容其實沒增加多少，差別只在有沒有騙讀者。**

### 4c. 派 sub-agent

**MANDATORY — 這個 sub-agent 必須是無脈絡的。** 不要告訴它這次 session 做了什麼、不要暗示答案。

🔴 **「無脈絡」要靠派工方式保證，不是靠自律。** 會繼承當前對話的派工型態（例如 fork 型子代理）**不算數** ——
那是自問自答。派之前先確認你用的派工方式是**全新、零記憶**的。

> 這個手法脫胎自 `memory-lint` Phase 3 的 recall 測試（那邊要求走**外部行程**才算數）。
> `wrap-up` 放寬成「一般子代理即可」，前提是它確實零記憶；**不確定就走外部行程**。

Prompt 骨架與「過」的判準見 [`references/quiz_bank.md`](references/quiz_bank.md)。核心三條：

1. 起點只給**入口檔路徑**，讓它自己照文件指引往下讀
2. 明令「**文件沒寫就答『沒寫』，不准用通用知識補**」
3. **「過」＝ 答對 ＋ 說得出依據在哪個檔**。只答對、講不出出處**不算過**

## Step 5: 沒過怎麼辦

🔴 **不要無限修到綠。**

> 「修到沒問題為止」不是終止條件。對一份持續變動的文件，永遠問得出新問題：
> 每修一次，可挑剔的表面就變大一點，**這是正回饋、不是收斂**。
> 而且修邊角很容易打壞主線。

**做法**：

1. 把紅掉的題目**用白話解釋給使用者聽** —— 哪一題紅了、agent 答成什麼、正確的是什麼、為什麼文件沒讓它答對
2. 提出建議修法，**問使用者要不要修**
3. 修完**必須重新派一個新的 sub-agent 重測**

🔴 **改完文件不重測就宣稱「處理好了」是違規。**

> 這條是真的犯過：改完就 commit 並回報「處理好了」，
> 被使用者一句「你有重新派 agent 核實嗎」當場問倒。答案是沒有。

## Step 6: 最終報告

```markdown
## wrap-up 報告

### 已收進 repo
| 東西 | 從哪來 | 放哪 |

### 已接上的 ref
### 已修的過時敘述
### 盲測結果
| 題 | 結果 | 依據 |
（紅的要附白話解釋）

### 🔴 等你決定
（刪除、改寫語意、判斷不明的項目；無人值守時跳過的也列這裡）

### 建議的入口檔草稿（若有建又復原）
```

### 範例（虛構專案）

```markdown
## wrap-up 報告

### 已收進 repo
| 東西 | 從哪來 | 放哪 |
|---|---|---|
| `calib_rig_v2.png` | `~/Desktop/scratch/` | `assets/rigs/`（`cp -p`，mtime 保留）|
| 三條校正結論 | 只在對話裡 | `docs/calibration.md` §4 |

### 已接上的 ref
- `docs/calibration.md` ↔ `assets/rigs/README.md`（雙向）
- `index.md` 補列 `docs/calibration.md`

### 已修的過時敘述
- `README.md:41` 說校正資料在 `tmp/`，實際已搬到 `assets/rigs/`

### 盲測結果
| 題 | 結果 | 依據 |
|---|---|---|
| 拿到一組新的校正照片要怎麼走？ | ✅ | `docs/calibration.md` |
| 哪些是成品、哪些是中間產物？ | ✅ | `SCHEMA.md` |
| 校正參數要改，改哪個檔？ | 🔴 | 答「大概在 config 裡」，講不出檔名 |
| 你知不知道自己還缺什麼？ | ✅ | 明確列出還需要看硬體接線圖 |

🔴 **第三題白話解釋**：它知道有校正這件事，但不知道參數放哪 ——
因為 `docs/calibration.md` 從頭到尾沒寫參數檔在哪個路徑，只說「調整參數後重跑」。
建議在該節補一行指向 `config/calib.yaml`。要修嗎？

### 🔴 等你決定
- `assets/rigs/` 底下有兩張看起來重複的圖，要不要刪其中一張（無法判斷哪張是最終版）
```

## Anti-patterns

- ❌ **沒有明確 `/wrap-up` 就自己啟動** — 「存檔」「收工」「要 compact 了」「PreCompact hook 提醒你」都不是授權，這是本 skill 最貴的違規（見 Entry gate）
- ❌ **自己發明目錄規範** — 專案有 `SCHEMA.md` 就照它的，這個 skill 不帶自己的
- ❌ **呼叫 `llm-wiki-lint` 當閘門** — 它是報告型、判準是結構性的；照它做完仍可能過不了盲測
- ❌ **搬檔案用普通 `cp`** — mtime 是證據，抹掉就救不回時間序
- ❌ **盲測 agent 給脈絡** — 給了就不叫盲測，等於自己考自己
- ❌ **「答對就算過」** — 講不出依據在哪個檔，代表下次還是找不到
- ❌ **沒過就一直修** — 三輪還不綠就停下來討論，不要陷進無限迴圈
- ❌ **改完不重測就說處理好了** — 這是本 skill 最常見的違規
- ❌ **在沒有入口檔的 repo 留下自建的入口檔** — 測完要復原
- ❌ **無人值守時代使用者決定要刪什麼** — 跳過並列進報告
- ❌ **憑推論決定格式** — 摘要放哪、索引怎麼寫、命名怎麼取，先找一個現成例子照抄

## Important rules

1. 🔴 **只有明確的 `/wrap-up` 能啟動**（Entry gate），推論出來的意圖一律不算
2. **判準是行為性的**：盲測 agent 接得住才算完成，不是文件看起來整齊
3. **一律照專案自己的規矩**（Step 1b 是 MANDATORY）
4. **分級授權**：可逆的直接做，刪除／改寫語意／判斷不明必問
5. **草稿沒併進 SSOT ＝ 沒寫**
6. **搬媒體保 mtime**
7. **盲測 agent 必須無脈絡**，且「過」要含得出出處
8. **改完文件必須重測**，不重測不准宣稱完成
9. **沒過最多修三輪**，之後停下來白話討論
10. **不在沒邀請你的 repo 留痕跡**
11. **術語第一次出現要定義** —— 寫文件時順手檢查，讀者不該去猜
12. **寫進 repo 前先找既有慣例** —— 格式、位置、命名都先查一個現成例子，不要憑推論定

## 配套 hook（選配）

`hooks/precompact-wrapup.js` 掛 `PreCompact`，在壓縮前提醒還有未落檔的產出。
**非阻塞**（只回 `systemMessage`）。官方支援擋下壓縮（`exit code 2` 是各 event 通用的作法；
JSON 欄位依 event 而異 —— PreToolUse 用 `permissionDecision`、Stop 用 `decision`，
⚠️ **PreCompact 用哪個我沒實測過，要改成阻塞版之前先查官方 hook 文件**）。
但 context 滿了卻擋住壓縮會把使用者困住，所以**預設不擋**。

🔴 **那則提醒是要轉述給使用者的，不是給你的授權。** 收到它之後只能把情況告訴使用者，
由他決定要先收尾還是直接壓縮；他沒有明確輸入 `/wrap-up`，就不准啟動本 skill（見 Entry gate）。
