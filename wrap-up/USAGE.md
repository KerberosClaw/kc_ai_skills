# wrap-up 使用說明

> **English summary:** Explicitly invoked only: it runs on `/wrap-up` and never on inferred intent such as a save/checkpoint request or a compact lifecycle hook. Harvests a long working session's output into the repository before you close or compact — moving stray media in under the project's own conventions, wiring two-way references, merging drafts into the source of truth — then dispatches a context-free sub-agent to blind-test the result from the project's entry file. The bar is behavioural, not structural: not "the links resolve" but "a stranger can pick this up", and an answer only counts if the agent can name the file it came from.

## 為什麼有這個 skill

你跟 AI 工作了六個小時，查清楚三件卡很久的事，拍板了五個判斷，產出散在十幾個檔案裡。

然後你 compact 了，或關掉 session。

隔天新開一個 session，它什麼都不知道。你花二十分鐘把昨天的脈絡重講一遍，它讀完文件，然後問你「那個底圖在哪」—— 而那張圖還躺在桌面，沒進 repo。再過幾天你清桌面，那張圖就消失了。昨天那六個小時，正式作廢。

這不是假設，是我們自己的踩坑實錄。這個 skill 的每一條規則都對應一次真的發生過的浪費：

- 一批查證結論寫進了草稿檔，**沒併回正式文件**。過些日子，同一條坑被重新踩了一次 —— 踩的人就是當初寫下它的人
- 一整條工作鏈的中間產物只在桌面，**時間戳是唯一能重建順序的線索**。差一點就用普通 `cp` 把那份證據抹掉了
- 一份文件開頭寫著「照這份走就夠了」。實際上不夠，但沒人發現 —— 因為從來沒有人真的拿它去測過
- 改完文件就宣布「處理好了」，**完全沒有重新驗證**。被使用者一句「你有重新派 agent 核實嗎」當場問倒。答案是沒有

`wrap-up` 就是把「收尾」這件每次都想做、每次都因為想睡覺而跳過的事，變成一個指令。

## 它做什麼

```
盤點 → 落檔 → 接 ref → 盲測 → 沒過就找你討論
```

**盤點**：`git status`、未推的 commit、最近改動的檔，加上 AI 自己的記憶 —— 這次拍板了什麼、查證出什麼。**還會去翻桌面跟 `/tmp`**，那是最常漏掉的地方。

**落檔**：照**你這個專案自己的規矩**搬（讀 `CLAUDE.md`／`AGENTS.md`／`SCHEMA.md`），不帶自己的目錄規範。搬媒體一律 `cp -p` 保留時間戳。

**接 ref**：單向連結等於沒連 —— A 提到 B，B 也要指得回 A。順便更新索引、把草稿併進正式文件。

**盲測**：這步才是驗收。派一個**全新、沒有脈絡**的 sub-agent，從專案入口檔開始讀，然後考它情境題。

**判準是行為性的，不是結構性的**：不是「連結都通了」，而是「下一個人接得住」。

## 怎麼用

**只認明確指令，沒有自然語觸發**：

```
/wrap-up
```

指定專案（省略就用當前目錄）：

```
/wrap-up ~/dev/my-project
```

> **為什麼不能講「收工」就啟動？** 早期版本吃「收尾／落檔／要 compact 了」這類說法，結果 AI 把
> 「幫我存個檔，等下繼續」跟「我要結束了，順便整理整個專案」混為一談：使用者只是想做一次
> checkpoint，它卻跑掉整套流程，搬檔、改索引、動正式文件、派 agent 全來一遍。這顆 skill 副作用太重，
> 不適合靠猜的，所以現在改成只認指令。你想要，就自己打。

## 它會問你什麼、不會問你什麼

這個 skill **刻意不用兩段式審核**（先報告、等你點頭才動手）。理由很簡單：你喊它的時機正是你要走了，全部停下來等點頭等於逼你留下。

所以它是**分級**的：

| 動作 | 會不會問你 |
|---|---|
| 搬檔進 repo、接 ref、更新索引、補 log、修斷連結 | ❌ 直接做（可逆，且照你專案的規則）|
| **刪除任何東西** | ✅ **一定問** |
| **改寫既有敘述的語意**（不只是補註記）| ✅ **一定問** |
| **判斷不明、兩種做法都說得通** | ✅ **一定問** |

背景執行（你本來就不在）時，需要問的**一律跳過**，列進報告的「等你決定」欄。**不會替你決定。**

## 盲測長什麼樣

每次 3–6 題，加一題固定必考。題目來自三處：這次 session 的決定（主要）、專案入口檔的路由、以及專案累積的題庫。

**「過」的判準比你想的嚴**：

| | |
|---|---|
| ✅ 過 | 答對 **而且** 說得出依據在哪個檔 |
| 🔴 不過 | 答對但講不出出處 —— 下次還是找不到，等於沒落檔 |
| 🔴 不過 | 用通用知識補（答得完整卻沒有出處）|

固定必考的那一題是：

> **「只讀這些，你知不知道自己還缺什麼？」**

這題最能抓出假的完整性。實測過一份寫著「照這份走就夠了」的文件 —— 盲測 agent 照它做完之後直接指出那句是假的，並列出它其實還缺的東西。補上誠實的邊界說明之後，同一份文件就過了。**內容其實沒增加多少，差別只在有沒有騙讀者。**

## 沒過怎麼辦

**不會硬修到綠。**

「修到沒問題為止」不是終止條件 —— 對一份持續變動的文件，永遠問得出新問題。所以：

1. 用**白話**告訴你哪一題紅了、agent 答成什麼、正確的是什麼、為什麼文件沒讓它答對
2. 提建議修法，問你要不要修
3. 修完**一定重新派新的 agent 重測**
4. **最多三輪**，還不綠就停下來討論

## 配套 hook（選配）

`hooks/precompact-wrapup.js` 掛在 `PreCompact` 事件上，壓縮前檢查有沒有未落檔的跡象（未 commit、未推、桌面近期改動），有就提醒一句。

**非阻塞** —— 官方支援擋下壓縮，但 context 滿了卻擋住會把你困住，所以預設只提醒。（要改成阻塞版，欄位名依 event 而異，先查官方 hook 文件。）

裝法（`~/.claude/settings.json`）：

```json
{
  "hooks": {
    "PreCompact": [
      { "hooks": [{ "type": "command", "command": "node ~/dev/kc_ai_skills/hooks/precompact-wrapup.js" }] }
    ]
  }
}
```

## 它不做什麼

- ❌ **不是文件 linter**。純檢查文件結構走 `llm-wiki-lint`（wiki 型）或 `memory-lint`（AI 記憶）
- ❌ **不整理你沒剛工作過的專案**。它的原料是「這次 session 產出了什麼」
- ❌ **不在沒有入口檔的 repo 留下痕跡**。測試需要時會建一份，測完復原，草稿附在報告裡讓你決定
- ❌ **不呼叫 `llm-wiki-lint` 當閘門**。那是報告型的、判準是結構性的，照它做完仍可能過不了盲測
