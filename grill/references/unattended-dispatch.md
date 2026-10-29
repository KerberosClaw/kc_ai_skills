# 無人值守派工的交接紀律

> **English summary:** A compact handoff checklist for work whose requirements are already agreed. The main agent writes the dispatch, reviews it with review-gate, and preserves authorization and evidence boundaries. This is reference material, not another skill or runtime.

需求已談妥後，由 main 直接把既有決定寫成可執行工單。沿用專案現有格式與來源，不為派工補完整 PRD、不重問已定決策，也不要求每次填滿模板。以下只補實際缺少的執行資訊。

## 交出去前

| 資訊 | 要交代到能執行的程度 |
|---|---|
| 目標與版本 | 唯一需求來源、當次版本／base、做與不做的範圍、必須保留的既有行為 |
| 執行環境 | repo／分支／工作目錄、必要工具／服務、可用的 skill 與位置；不能要求新 session 猜隱含脈絡 |
| 驗收 | 每項交付如何觀察、指令／門檻與證據位置。可自動驗證就自動驗；人工／實機驗收另列，未做不能算通過 |
| 授權 | 可改的檔案、環境、資料與操作；需決策或越權時停哪一部分。既有明確授權持續有效，不每個階段重問 |
| 停止與恢復 | 任務的時間／次數上限、缺決策／缺依賴／無進展的出口、進度與未知外部操作如何核對後續跑 |
| 回報 | 使用既有結果管道；需要推播時沿用明確指定的來源與路由，記錄設定來源，不放 credential |

私有工單必要的操作位置可保留；公開／分享版本才另做去敏。密碼、token、金鑰與 webhook 一律引用安全設定來源，不寫正文。

## 執行時

- 開跑先查輸入、依賴與必要環境，再做適合本任務的最小 smoke；有已授權推播時依 [通知協定](notify-protocol.md) 確認送達，不能把 queued 當測通。不要因這份 checklist 擅自啟動服務、安裝依賴或發通知。
- 按交付逐項執行、驗證與記錄。分清「沒有硬缺陷」和「已達成目標」，不能只靠 agent 自評。
- 修正／重試記下原因、結果與下一步；第二輪起說明 delta。連兩輪無實質進展就停止該迭代，回報 `ESCALATE`，不要改到 reviewer 無話可說。
- `NEEDS_INPUT`：缺必要資訊或決策；`ESCALATE`：已達上限或無進展；`REFUSE`：下一步超出授權。停受影響範圍，保留可安全繼續的獨立工作與證據。
- 恢復前核對版本、檔案／程序狀態、已完成與失敗項目。外部操作結果未知時先查是否已發生，不盲目重送。
- 審查呼叫 `review-gate`，測試、AC 與適用 UI QA 各自驗證。完整開發任務依原授權接 `doc-qa:qa`、`align` 與收尾；缺能力或未實跑保留缺口，不能靠修文件取得通過。
- 候選擇優工作才保留參數／種子／配方與人工最終挑選；一般 build 不硬套「由人挑候選」的規則。

## 收尾

回報版本與 diff、各項成果、測試／AC 證據、適用 QA 與文件結果、未完成／待決事項。分清任務實作、驗收、QA、文件與整體完成；報告產出或通知成功都不代表交付成功。

主機與 runtime 才能提供程序監控、鎖、排程或 timeout。這份文件不會自行啟動另一個 agent。執行、合併、部署與發佈都沿本次實際授權。
