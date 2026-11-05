# 無人值守派工的交接紀律（最小底線）

> **English summary:** The full dispatch standard now lives in the [owl plugin](https://github.com/KerberosClaw/kc_ai_plugins/tree/main/plugins/owl): `owl:brief` writes the dispatch, `owl:run` is the execution discipline, `owl:accept` checks the result. Use it when it is installed. This page keeps only the minimum a dispatch must cover when owl is not available.

## 有裝 owl 就用 owl

需求談妥、要交給無人值守的 agent 時：

| 階段 | 用 |
|---|---|
| 寫工單 | `owl:brief`：讀 repo 的 `owl.md`、列測試與正式環境的差異、把真人問法題組放進驗收、依風險定審查輪數 |
| 執行 | `owl:run`：狀態檔與紀錄、中途改指示、鎖、通知、續跑 |
| 驗收 | `owl:accept`：對實際環境核對、跑題組、補 `owl.md` 的缺口 |

維運查修這類不寫工單的輕量工作不套 owl，也不套本頁。

## 沒裝 owl 時的最小底線

需求已談妥後，由 main 直接把既有決定寫成可執行工單，不為派工補完整 PRD，也不重問已定決策。工單至少要交代：

| 資訊 | 要交代到能執行的程度 |
|---|---|
| 目標與版本 | 唯一需求來源、當次版本或 base、做與不做的範圍、必須保留的既有行為 |
| 執行環境 | repo、分支、工作目錄、必要工具與服務；不能要求新 session 猜隱含脈絡 |
| 測試與正式環境的差異 | 逐項列出設定、資料量、外部服務、帳號權限的差異；正式環境要開的東西測試環境先開，補不齊的寫明理由並改成上線後驗 |
| 驗收 | 每項交付怎麼觀察、指令或門檻、證據位置；題目要有一般人實際的問法，不能只由寫程式的 agent 自己出。人工或實機驗收另列，未做不能算通過 |
| 授權 | 可改的檔案、環境、資料與操作；需決策或越權時停哪一部分。既有明確授權持續有效 |
| 停止與恢復 | 時間或次數上限、缺決策或無進展的出口；外部操作結果未知時先查是否已發生，不盲目重送 |
| 回報 | 沿用既有結果管道；需要推播時依 [通知協定](notify-protocol.md)，確認送達，排隊中不算測通；不放 credential |

密碼、token、金鑰與 webhook 一律引用安全設定來源，不寫正文。審查呼叫 `review-gate`；缺 review-gate 或雙 agent 能力時回報能力缺口，不能把自審當獨立審查。

## 執行時的三種停法

- `NEEDS_INPUT`：缺必要資訊或決策。
- `ESCALATE`：已達上限，或連兩輪沒有實質進展；回報試過什麼與差異。
- `REFUSE`：下一步超出授權。

三種都只停受影響的範圍，保留可以安全繼續的獨立工作與證據。收尾時分清實作、驗收、QA、文件與整體完成；報告產出或通知成功都不代表交付成功。
