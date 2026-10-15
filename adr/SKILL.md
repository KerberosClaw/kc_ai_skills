---
name: adr
description: "Use when a durable technical decision was just made in conversation and should be recorded, or when user asks to write/record an ADR (開 ADR / 記個決策 / 這要不要 ADR). Runs a three-gate check FIRST and actively talks the user out of writing one when the decision doesn't qualify — then writes a lightweight (title + 1-3 sentences) ADR following the repo's own ADR conventions if any exist. Repo conventions always override this skill's defaults. NOT for requirement specs (spec / prd-create) or rewriting historical decisions; preserve their text, allow evidence-backed current-state notes, and record changed decisions in a new ADR."
version: 0.3.1
status: mvp
triggers:
  - "/adr"
  - "開 ADR"
  - "寫 ADR"
  - "記個決策"
  - "這要不要 ADR"
  - "記錄這個決策"
---

# adr — 三重閘決策記錄

You are a decision recorder with a strong bias against writing documents. 你的第一要務不是把 ADR 寫漂亮，而是**判斷這個決策值不值得一份 ADR**——多數不值得。ADR 的價值在「記下做了決策、為什麼」，不在填滿模板。

## Step 1: 三重閘（先判斷、再動筆）

**先看規約再跑閘**：先確認 repo 規約（CLAUDE.md / PRD / 開發規約）有無「某類變更必須走 ADR」條款——有且命中 → 跳過三重閘直接進 Step 2；規約永遠壓過本 skill 的判斷。

**MANDATORY**: 其外的決策動筆前先過三重閘，**三條全真才寫**：

| 閘 | 問題 | 判準 |
|---|---|---|
| 難回頭 | 改變這個決策的成本高嗎？ | 換掉要大改架構 / 遷資料 / 重訓模型 = 真；改個 config 就能回頭 = 假 |
| 沒脈絡會困惑 | 半年後的人看 code 會問「為什麼這樣做」嗎？ | 做法偏離顯然路徑、或看起來「怪」= 真；做法本身自明 = 假 |
| 真實取捨 | 有被認真考慮過又放棄的替代方案嗎？ | 有輸家方案 + 放棄理由 = 真；根本沒得選 = 假 |

**沒過閘 → 勸退**，直接告訴 user：「這不用 ADR，`log.md` 補一行 / commit message 寫清楚就夠」，並說明是哪一閘沒過。**勸退是本 skill 的正常輸出，不是失敗。**

### 別漏掉的兩型（仍走三重閘，但幾乎必過——點名是提醒別漏）

- **刻意偏離顯然路徑**的決策——不記下來，下一個工程師會把它當 bug「修好」。
- **明確的 no**——被認真評估後否決的方案，記下來防半年後同一提案再來一輪。

## Step 2: 偵測 repo 慣例

```bash
ls -d adr decisions doc/adr docs/adr doc/adrs docs/adrs doc/decisions docs/decisions 2>/dev/null
```

命中的目錄先開來確認**長得像決策紀錄**（編號檔名 / 索引 / ADR 字樣）——同名但不是 ADR 庫（例如某個叫 `adr` 的工具目錄）就略過。

| 情況 | 動作 |
|---|---|
| 目錄存在且有 README / 格式說明 | 讀它，**照它的編號、命名、格式、狀態欄寫**——repo 慣例永遠壓過本 skill 預設 |
| 目錄存在但無格式說明 | 讀最近 1-2 篇現有 ADR，仿其格式 |
| 目錄不存在 | **Lazy 建立**：`docs/adr/`，用本 skill 預設輕量體。不預建 README、不鋪模板 |

編號 = 掃現有檔名最大號 + 1；空 repo 預設檔名 `docs/adr/NNN-kebab-slug.md`（NNN 三位補零，從 001 起）。**檔名一經建立不改名**（別的文件會連過來）。

## Step 3: 寫 ADR（預設輕量體）

預設格式——**標題 + 1 到 3 句**，就這樣：

```markdown
# ADR-NNN：<決策一句話>

<做了什麼決策>。<為什麼——關鍵理由或放棄了什麼>。<（選配）代價或後續影響一句>。
```

- 日期、狀態、Considered Options、Consequences 全是**選配**——有實質內容才加欄位，沒有就省。
- **禁塞實作細節**：ADR 記「決策與理由」，不記 API 規格、欄位定義、步驟——那些歸 spec / 文件。
- 重格式例外：repo 規約要求完整結構（如 ADR 兼作規格修訂紀錄）→ 照 repo 的來。

## Step 4: 收尾

- Repo 有 ADR 索引表 / log.md 維護慣例 → 照做（補索引行、補 log 條目）。
- 被新 ADR 取代的舊 ADR：在新 ADR 註明「取代 ADR-NNN」、索引更新狀態；舊檔保留原決策與理由，頂部加「已被 ADR-NNN 取代」標記。
- **允許歷史現況註記，不改歷史結論。** align 或本流程查到現況衝突時，可在頂部或衝突處鄰近新增清楚區隔的註記，標查核日期、目前差異及可追溯證據；保留原文、當時狀態與檔名。有已存在的後續 ADR 就連過去。註記不批准新決策；若決策真的變了，仍須另寫新 ADR，未定案則標待確認。
- 提交與否照 caller 當下的工作流程走，本 skill 不擅自 commit。

## 從其他流程接入與返回

`spec` 的設計／實作、debug 或無人值守執行中形成重要技術決策時，可直接接入本 skill，先依 Step 1 判斷，不把 ADR 當成每個專案固定的一關。只記錄已由 user 確認或原授權內已確定的決策；未決方案不能靠寫 ADR 自動變成已批准。

先找現有 ADR，已記錄且決策未變就引用，不重開一篇。需要新 ADR 才寫，並讓當前 `DESIGN.md`／`plan.md`／`tasks.md` 或既有交接紀錄引用它；不符合判準則留在原計畫或任務紀錄。接著返回原流程的下一步，不因寫完 ADR 自行開始實作、改需求、部署或結案。

無人值守沿用相同規則：原授權內的決策可記錄後續跑；若需要改凍結規格、變更架構邊界或 user 尚未決定，就保留疑點、交還原流程的 stop-and-ask。ADR 不能取代需求／AC／任務計畫，也不是「有沒有分工給人類工程師」的替代流程。

## Anti-patterns

- ❌ **為記錄而記錄** — 三重閘沒過還硬寫。文件膨脹的起點就是「反正記一下也沒差」
- ❌ **填滿模板** — 沒有替代方案就不要編一個出來湊 Considered Options
- ❌ **ADR 當 spec 寫** — 塞 API 定義、資料模型、實作步驟進去
- ❌ **覆寫歷史 ADR 的決策或理由** — 決策變了開新 ADR；現況註記依 Step 4 保留原文並區隔
- ❌ **無視 repo 既有格式** — 自帶「標準 ADR 模板」蓋過人家用了十篇的慣例
- ❌ **改檔名 / 重編號** — 編號與檔名是永久位址

## Important rules

1. **勸退優先** — 三重閘沒全過就建議寫 log / commit message，這是正常輸出
2. **Repo 慣例 > skill 預設** — 永遠先偵測、先讀、再寫
3. **輕量體是預設** — 標題 + 1-3 句；欄位有內容才加
4. **兩型必記** — 刻意偏離顯然路徑、明確的 no
5. **Lazy 建立** — 第一篇 ADR 需要時才建目錄，不預鋪結構
6. **歷史原文保留** — 取代用新 ADR；現況註記依 Step 4，不覆寫舊決策
7. **不記實作細節** — 決策與理由 only

## 跟其他 skill 的關係

- **`spec` / `prd-create`**：那兩顆產「要做什麼、怎麼做」的需求規格；本 skill 只記「為什麼選了這條路」的單一決策。feature lifecycle 用 `spec`、stakeholder PRD 用 `prd-create`，別把整份規格塞進 ADR。
- **`diagnose`**：debug 過程若催出一個難回頭的決策（換架構 / 換依賴），驗完可用本 skill 把「為什麼這樣修」記成 ADR；但 debug 本身走 `diagnose`。
- 選哪顆規劃類 skill 有疑問 → 見 README 的規劃類決策框或 `workflow-router`。

## Acknowledgments

三重閘與輕量體機制參考 [mattpocock/skills](https://github.com/mattpocock/skills)（MIT）的 domain-modeling / ADR-FORMAT 紀律，中文重寫並調整成本 repo 慣例。
