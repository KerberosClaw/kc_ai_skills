# Unattended-run protocol — the discipline any agent-run spec inherits

**內容無關(content-agnostic)的執行紀律正典。** 一份規格要交給 agent **無人值守 blind 跑**時,不管它是 `goal-engineer` 的 generate-and-select dispatch、還是 `prd-create` 的 build-to-spec PRD(其 §13 Test Strategy 的 agent-run 變體),都套這同一層。

> 這份只講「**agent 怎麼無人值守跑 + 怎麼回報 + 何時停**」,**不講要 build/generate 什麼**(那是各內容 skill 的事)。通知格式細節在 `notify-protocol.md`,本檔不重述,只引用。
>
> **適用前提**:有人不在場、靠推播看進度。**人跑的規格不套本檔**(人跑不需要紅綠燈 / 3 出口 / 防空轉)。

---

## 1. Pre-flight gate（fail-fast,最前面跑、硬擋）

開跑前先驗、任一條沒過就**不准進 loop**:

0. **通知測得通**:送一則測試 ping;helper 回非零 → 不開跑(通知靜默失敗 = 盲跑)。見 `notify-protocol.md`。
1. runtime / 服務 / 依賴在(`/api/health` 之類、必要工具 `curl`/`python3`/… 在)。
2. 輸入備齊。
3. **smoke 一個工作項端到端**跑通,再開整批 / 全 matrix。

## 2. 機器可檢核（machine-checkable）

每條驗收標準都要**機器能判真假** —— 不靠人肉眼。沒有客觀檢核的標準 = 不能無人值守。

- build-to-spec:每條 AC 展成測試,**gate 全綠才算該項完成**(lint / type / unit / integration / e2e / build)。
- generate-and-select:每個候選過 rubric;能量化就加客觀指標兜底。
- 🔴 任何 **silent cap**(top-N / 不重試 / 抽樣 / 截斷)要**明講、別藏**(藏起來會讓人以為「全做了」)。

## 3. 兩層閘（floor + ceiling）

- **扣分閘(floor)**:硬缺陷自動退 —— 輸出損壞 / build 壞 / lint fail / schema 不合。
- **達標閘(ceiling)**:真的**命中目標**了嗎 —— 「沒缺陷」**≠**「命中目標」。
- **判官**:獨立 skeptic subagent(預設找碴)/ 測試套件 / 客觀指標。寫的人自己打分太寬鬆,要另一個 agent 挑刺。

## 4. 原因碼迭代（reason-coded）

沒過閘 → 記**原因碼**、照該碼的預設動作調整,讓迭代**針對性、不亂猜**。

| code | 意思 | 預設動作 |
|---|---|---|
| `<R1>` | `<什麼失敗>` | `<下輪怎麼調>` |

## 5. 停止條件：3 出口 + 防空轉

- **per-item**:湊滿 ≥K 過閘,或迭代 ≤N 輪,或 **loop-until-dry**(連 M 輪沒新東西)—— 先到先停。
- **3 出口**:
  - `NEEDS_INPUT` — 缺料 / 缺決策 → 暫停該範圍、發 🔴。
  - `ESCALATE` — 連 2 輪沒實質進展 → 發 🔴(必帶 delta)。
  - `REFUSE` — 要求越過授權邊界 / 紅線 → 拒做、發 🔴。
- **防空轉(anti-spin)**:第 2 輪起每輪必報 **delta**(跟上輪差在哪);講不出有意義 delta → 停、發 `ESCALATE`。

## 6. 授權邊界 + stop-and-ask

**方法鬆、驗收緊**:對「怎麼做」有自主權(自己查資料、換方法迭代);gate / AC 是成功定義、不可協商。明列兩欄:

- **已授權(loop 內可自主)**:`<哪些 repo / 機器 / 服務 / 操作,agent 可全權>`
- **stop-and-ask(遇到即停、發 🔴 待人)**:授權外的設定 / 既有資料的修改刪除 / spec 未定義的衝突 / 白名單外的新依賴 / 規格外的刪資料。
- 🔴 **必含**:不准自己拍板最終選定 / 不自做品味判斷 —— 人是 ground truth。

## 7. 可重現（鐵律:只有結果、沒配方 = 白跑）

- 每個產出帶 **recipe sidecar**(參數 / 種子 / 輸入 / 版本)。
- 每輪一筆 **run log**:參數 + 判定 + 原因碼 + delta。
- milestone 通知帶足夠 handle(item id / 批次 / 輪數),讓人挑完對得回 recipe。

## 8. 通知

紅綠燈 🟢🟡🔴、channel-agnostic、milestone 粒度(不 per-candidate)、pre-flight 測通才開跑 —— **格式與 triggers 全部見 `notify-protocol.md`,本檔不重述**。

## 9. 人工 checkpoint（選用、長跑建議）

每個工作天 / 階段收尾:人工 review 當日 diff + gate 報告;偏航在下一輪開始前修正。

---

## 套用 checklist（規格要交 agent 無人值守跑時）

```
[ ] pre-flight gate 在最前(通知測通 + 服務 + 輸入 + smoke 一項)
[ ] 每條驗收標準機器可檢核;silent cap 明講
[ ] 兩層閘(floor + ceiling),判官獨立
[ ] 原因碼表(讓迭代針對性)
[ ] 停止條件含 3 出口 + delta 防空轉
[ ] 授權邊界兩欄 + stop-and-ask;含「不自己拍板最終選定」
[ ] 可重現:每產出 recipe sidecar + 每輪 run log
[ ] 通知對齊 notify-protocol.md(紅綠燈 / milestone 粒度 / pre-flight)
```
