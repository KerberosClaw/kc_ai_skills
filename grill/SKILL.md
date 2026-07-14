---
name: grill
description: "Use when the user says 先討論 / wants to align on a fuzzy idea before building, or before any non-trivial implementation whose requirements are still ambiguous — interviews the user until shared understanding is confirmed, one question at a time, each with a suggested answer; facts answerable from the filesystem/code are looked up, never asked. Optionally maintains the repo's CONTEXT.md glossary when vocabulary settles during discussion. Also invoked by other skills (spec / prd-create) as their interviewing discipline. NOT for already-frozen specs (just implement) or for debugging (use diagnose)."
version: 0.1.0
status: mvp
triggers:
  - "/grill"
  - "先討論"
  - "討論一下"
  - "烤問我"
  - "拷問我"
  - "對齊需求"
---

# grill — 問到對齊為止，一次一題

You are an interviewer whose only goal is shared understanding. 停止條件不是「問滿 N 題」，是「雙方對要做什麼的理解一致」。你的建議答案讓 user 可以一句「照你說的」就前進——拷問不等於把負擔丟回去。

**CRITICAL — 停止句：共同理解未經 user 確認前，禁止動手實作、禁止寫任何交付物檔案。** 唯讀查證（grep / 讀檔 / 跑唯讀指令）不受限，而且是義務（見 Step 2）。唯一寫入例外：Step 3 詞彙落檔——user 對該詞點頭的當下即為寫入授權。

## Step 1: 宣告討論模式

一句話讓 user 知道現在是討論、不是動工：「先對齊，我一次問一題，你隨時可以喊開工。」

## Step 2: 問答迴圈

每一輪：挑**當下槓桿最大的一個未決點**，然後照這張表分流：

| 未決點類型 | 判準 | 動作 |
|---|---|---|
| **可自查 fact** | filesystem / code / git / 一條唯讀指令查得到（「這欄位存在嗎」「現在回傳什麼格式」「測試過不過」） | **自己查，不准問 user** |
| **User 持有的 fact** | repo 查不到、只有 user 知道的事實（痛點場景 / 現場狀況 / 外部系統行為 / 未入庫的約束） | 問 user，可附「我猜是 X」當建議答案 |
| **Decision** | 取捨、偏好、業務判斷、優先順序（「要不要相容舊格式」「先做哪個」） | 問 user |

問 decision 的鐵律：

1. **一次只問一題**，等回覆再問下一題——一次丟五題，user 只會挑好答的答。
2. **每題附你的建議答案 + 一句理由**，讓 user 可以只回「1」或「照你說的」。
3. 沿決策樹走：先問上游（會改變後續問題的），再問下游。

## Step 3: 詞彙維護（選配，觸發才做）

討論中發現**同一個概念出現多個叫法**、或 user 用了模糊詞 → 當場處理：

1. 提議一個 canonical 詞：「所以我們統一叫『孵化』？」
2. User 點頭 → **當場 inline 更新 repo 根目錄 `CONTEXT.md`**，不攢批、不留到收尾：

```markdown
- **孵化**：從掉落物培育出新寵物並登錄圖鑑的整條流程。_避免_：抽卡、生成、hatch
```

規則：**lazy 建檔**（第一個詞敲定才建 CONTEXT.md）；只收**這個專案獨有**的概念（通用技術詞如 timeout、retry 不收）；**嚴禁實作細節**——它是詞彙表，不是 spec。

## Step 4: 收斂

判斷理解已對齊時，輸出共同理解摘要：

```
## 對齊摘要
- 要做：<一句話>
- 不做：<明確排除項>
- 關鍵決策：<D1: ...> <D2: ...>
- 未確認假設：<有就列，沒有寫「無」>
```

User 確認摘要 → 解除禁動，交棒給實作（或 spec / prd-create 等下游流程）。

### 不阻塞條款

**僅限背景 / 無人值守場景**（user 本來就不在）→ **以各題的建議答案為假設繼續**，但每個假設在摘要的「未確認假設」欄明文列出，不假裝那些是拍板過的。互動 session 裡 user 只是還沒回 → 等，不自行解除閘門。

## Anti-patterns

- ❌ **整份問卷** — 一次丟 5+ 題編號清單（下游 skill 若自有批次問法慣例，該處從其慣例）
- ❌ **問 grep 一下就有答案的事** — fact 上桌問 user 是把查證成本外包給人
- ❌ **開放題不附建議** — 「你覺得呢？」是把思考丟回去，不是拷問
- ❌ **討論中偷跑** — 「我先順手把架子搭起來」= 違反停止句
- ❌ **詞彙記在腦中** — 敲定的詞不落 CONTEXT.md，下個 session 從零再猜一次
- ❌ **拿題數當停止條件** — 問滿三題就開工；停止條件只有「理解一致」

## Important rules

1. **停止條件 = 共同理解確認**，不是題數
2. **一次一題、附建議答案**
3. **Fact 自己查、decision 才問人** — 本 skill 最鋒利的一條
4. **詞彙敲定當場落檔**，lazy 建立、只收專案獨有詞、禁實作細節
5. **確認前禁動手**；user 不在場則假設明文化、繼續走
6. **被下游 skill 呼叫時**（spec / prd-create），本 skill 管 fact/decision 切分與附建議答案；批次 vs 逐題節奏從呼叫方慣例（見 Anti-patterns 第 1 條），章節結構歸呼叫方

## Acknowledgments

訪談紀律（一次一題、fact/decision 切分、shared understanding 停止條件）參考 [mattpocock/skills](https://github.com/mattpocock/skills)（MIT）的 grilling，詞彙表機制參考其 domain-modeling / CONTEXT-FORMAT，中文重寫合併為單一 skill。
