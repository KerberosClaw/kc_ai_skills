---
name: prep-repo
description: "Prepare an existing project for GitHub or public release with scope-appropriate checks for sensitive data, documentation, installation, tests and release artifacts. Separate release blockers from polish, preserve existing authorization, and verify the published result only when publishing is requested. Not for designing new features or publishing private operational material."
version: 2.3.1
status: stable
triggers:
  - "/prep-repo"
  - "推上 GitHub 前檢查"
  - "開源前體檢"
  - "prepare repo"
---

# Prep Repo

> **English summary:** Prepare releases with scope-appropriate checks. Technical documents default to Traditional Chinese with an English summary for GitHub; explicit language requirements are acceptance criteria, while separate bilingual READMEs retain their languages.

先判斷這次要交付什麼，再檢查它能否安全、正確地公開。真正的機敏外洩、不可執行的安裝指引、錯誤的功能宣稱需要修；未約定的格式偏好不應讓已可交付的工作無限延長；使用者明確指定的語系／摘要格式屬於驗收要求，不能降級成可略過的修飾。

## 範圍與分工

- 從使用者要求、repo 規範與實際檔案確認目標、visibility、交付物及已有授權。已講清楚的決定不重問；資訊確實不足才釐清。
- 先查 working tree、branch、remote、現行 README／安裝方式與發布流程，保留無關的 dirty changes。只修改此次授權的 repo／檔案；多 repo 任務各自核對範圍。
- 私庫與公開匯出分開處理；不要因為準備 OSS 就把私庫改 public、複製整條 private history，或把私人操作手冊當公開文件。
- 既有系統缺技術文件可用 `project-docs`；新功能設計走 `spec`，根因不明的 bug 走 `diagnose`。不要把簡單文件修正升級成整套工程流程。

## 先分類，再修正

| 結果 | 判準 | 處理 |
| --- | --- | --- |
| 阻擋發布 | 具體機敏外洩、預定交付物無法安裝／使用、必要驗證失敗、重要功能或安全宣稱失實 | 提供證據、影響和最小修法，修正並驗證後才發布 |
| 待確認／未驗證 | 疑似敏感值無法判定、缺少必要權限或環境、工具失敗／跳過 | 說明缺口；必要檢查未完成不能寫成通過 |
| 一般改善 | 無功能影響的命名、badge、措辭或排版偏好 | 按範圍和成本調整，不當作新 gate |
| 不適用 | 此交付物沒有該能力或契約 | 註明理由，不為填 checklist 新增能力 |

沿用使用者／repo 的嚴重度定義；沒有定義時不要把所有 blocker 都叫 P0。第一輪合併回報已知問題；修正後重驗受影響項與整體發布檔案邊界，不重跑沒有新理由的全部檢查，也不每輪追加無關修飾。遵守使用者指定的修正輪次與停止條件；沒有指定時，以能否提出有證據、不同於已失敗嘗試的最小修法決定是否繼續。反覆無進展就回報殘餘問題，不宣稱收斂。

## 依交付物挑檢查

| 檢查面 | 要確認的事 | 不要機械套用的要求 |
| --- | --- | --- |
| README | 用途、成熟度、必要依賴、可重現的 quick start、限制與文件入口符合現況；重要目錄樹與實際檔案相符 | 標題可以是專案名稱；趣味標題、固定位置 badge 不是必要條件 |
| 語言與導覽 | 技術文件預設正體中文（臺灣用語）；發布到 GitHub 的文件開頭放簡短英文摘要，正文用正體中文。私庫去敏匯出也沿用此規則。雙語 README 維持英文版／中文版內容同步與互連，本 repo 使用 `README.md`／`README_zh.md` 與 `正體中文`／`English` 連結 | 獨立英文 README、程式碼、指令、API／schema 識別字與授權原文保留原樣。使用者／組織明確指定其他語系才覆蓋預設；現有文件是英文不算例外。核對本次交付，不為小修翻譯未授權的歷史檔案 |
| 安全說明 | 有外部服務、憑證或私人資料的程式，要說清楚資料去向、保存方式與回報管道；可連到既有 SECURITY／privacy 文件 | 靜態首頁不需要虛構 runtime 安全章節；不得宣稱完美去敏 |
| 授權與追蹤檔 | 檢查 LICENSE、依賴／素材授權、實際 tracked／staged／打包內容；缺授權選擇不可擅自選 MIT。ignore 規則涵蓋此專案產物與私人 runtime | `.gitignore` 不會移除已 tracked 檔案，也不能取代掃描 |
| 結構與 metadata | 保留有用途的入口／設定；檢查 manifest、skill frontmatter、references 和實際被使用的 scripts。若 lock 檔影響語言統計，可用 `.gitattributes` 標記 generated | 根目錄 AGENTS、CONTRIBUTING、SECURITY、CHANGELOG 都可能合理；純 Mermaid 不需建立空 images 目錄 |
| 安裝與測試 | 對程式發布驗證實際安裝／建置入口和相關測試；用隔離環境。現有必要 checks 應通過；既有失敗與本次回歸分清楚，不隱藏或略過 required checks | 文件／profile 更新以連結與渲染為主，不硬加無關程式測試；離線成功不代表 live 整合成功 |
| CI | 核對現有 workflow 是否真的測試預定 artifact／平台；需要持續驗證的程式發布可補 CI | 靜態文件不一定需要新 workflow；存在 YAML 不代表跑過 |
| Docker | 專案提供或宣稱支援 Docker 時，才驗 build、compose 與必要 health check；測試不得占用正式服務或憑證 | 原生平台依賴不是 Docker-ready；無容器交付就不補 Dockerfile／badge |
| 命名與 commit | 沿用 repo／user 的命名和 commit 慣例；檢查 metadata 是否含私人資訊 | 普通作者署名、`Co-Authored-By` 不等於洩漏；不得為統一樣式刪署名或重寫歷史 |

## 文件與圖表要實際驗

- 逐頁確認本次交付的正文語系及英文摘要符合約定，摘要準確反映正文；不可只把標題翻成中文就視為完成。翻譯後重驗 anchors，程式範例與識別字不可因翻譯改變。
- 驗證 Markdown 的相對路徑、fragment anchors、大小寫、圖片／附件與重要外連。尊重合法的跨 repo／Wiki 導覽；依發布位置判斷是否能解析，不能只檢查本機「檔案存在」。外連抽查即可，遇認證／網路錯誤要區分未驗證與真壞鏈。
- 用 parser 或實際 renderer 判斷效果。`---` 可是 frontmatter 或分隔線，`===` 可以是 Setext 標題；不能單憑出現就刪除。檢查 fence 是否正確閉合、範例是否誤吞正文。
- 有 Mermaid 等圖表時，用可用的相容 renderer 實際渲染受影響圖表，檢查語法及可讀性；例如本機 `mmdc`，或已配置的預覽／CI。不要為了「通過」默默刪掉圖。
- 無 renderer 時記錄「未渲染」，說明已做的靜態檢查。若圖是關鍵交付／使用者要求渲染，先解決環境或回報阻擋；非關鍵且已揭露的限制可保留，不把靜態檢查叫渲染通過。
- 不必為一次性檢查引入新依賴、常駐 CI 或持久化腳本；已有工具足夠時直接使用。

## 去敏：兩層掃描與有根據的判讀

先列出預計發布的 source tree、包／圖片等 artifacts，以及會推送的 Git refs。掃描目前工作內容和完整可達歷史；shallow clone／未取得的 refs 要補齊或揭露。對 ignored runtime／build cache 與實際要發的檔案分清楚；需要乾淨匯出掃描時，核對匯出清單，不能藉此漏掉待發布檔案。測試產物與掃描報告預設放 repo 外。

**Layer A：憑證特徵。** 用 gitleaks 或同等工具。以下為已安裝 gitleaks 的例子；命令可用性以本機 `--help` 為準：

```bash
# 工作內容，包含尚未 commit 的候選檔案
gitleaks dir . --no-banner --redact

# 已有 commits 時，掃完整可達歷史
gitleaks git . --log-opts="--all" --no-banner --redact
```

確認 tool exit status、report 與跳過範圍；有 finding 不等於已坐實洩漏，執行失敗也不等於 clean。缺工具時先用可用環境補足，或明列未驗證，不能只跑 grep 就宣稱兩層通過。

**Layer B：專案情境。** 依已知邊界找真人／客戶識別、內部位址、帳號與頻道 ID、主機／home 路徑、私庫名稱、部署設定、私人內容及 commit metadata。這些可能沒有通用 secret 特徵；用 `rg` 或小型 scanner 補足。先輸出檔名／位置，再局部檢視；不要把含敏感值的整行 `git log -p` 或搜尋結果倒進對話。實際 denylist 與含私域資料的報告留在受限的 repo 外位置，不能跟著 OSS。

**結果判讀：**

- 有來源可證明的虛構 ID、公開範例、hash 片段、刻意公開的署名／連結，可由 agent 分類並簡述理由，不必每筆重問人。拿不準的疑似機敏保留待確認，不自動放行。
- 只在同一工具持續重報、且確定需要 suppression 時，記錄單筆 finding 的精確 fingerprint。不要為一次已解釋的誤報加永久忽略，不用廣泛 regex 關掉整類偵測。
- 報告提供分類、經適當去敏的檔案／行號／commit、影響與修法；必要值用遮罩，**不再印出秘密本體**。附件或工具報告也先去敏。
- 未提交的真實秘密：從發布候選移出或改成安全配置入口，再重掃；不毀損使用者原有 runtime。已進歷史的真實秘密：暫停受影響的 commit／push／發布，釐清可行的清除與憑證撤銷／輪替方案。既有 clone／fork 不會因改歷史消失。
- 歷史改寫、force-push 或憑證撤銷／輪替須有涵蓋該具體動作的授權及復原安排；普通發布授權不包含這些破壞性操作。若已明確授權，不重複問。不能把所有「grep 命中」都送去 history-rewrite gate。

## 執行階段與交付

### 1. Commit 前

完成適用檢查與必要修正，核對實際 staging／package 清單，不把測試 residue、私人報告或無關改動帶入。使用者或適用流程要求獨立審查時，依指定範圍、嚴重度與輪次執行；通過證據綁定那批檔案／diff，之後有改動就重驗受影響範圍。一般小修改不自動增加 subagent gate。

新 repo 還沒有 commit 時，記錄「history 尚不存在」，先檢查候選 tree／artifacts。不要為了跑 history scan 先提交未審核檔案。

### 2. Commit 後、push／發布前

**只有在授權範圍內才 stage／commit／push／合併／發布；單獨叫 prep-repo 不代表要求執行這些動作。** 已有授權就照 repo 的 PR／release 流程繼續，不另加重複確認。使用符合改動與 repo 慣例的 commit message，不套固定文案。

對實際將推送的 refs／artifacts 做最後去敏檢查，包含新 repo 的首批已審核 commits 與 commit metadata。確認必要 CI／checks 對應預定 revision；已審查的檔案、測試的 revision、要發布的 artifact 必須能對得起來。CI 修正或打包產物有新內容時，補驗其影響，不把先前的通過無限沿用。

### 3. 發布後（只在已授權並實際發布時）

核對目標 repo／visibility、main／tag／release revision、README／文件連結及 CI 結果。Description／topics／badges 依專案用途補足，不虛構平台支援或成熟度。遠端已收到預期內容後，才依 user／repo 慣例清掉本次擁有的暫存 clone、worktree 和測試產物；不得移除仍被安裝器或服務引用的路徑。

### 4. 回報

簡述實際完成的修改、檢查證據、未驗證／不適用項與殘餘 blocker。只有掃描通過就說「整備完成」，不是「已發布」；已發布則提供可核對的 repo／PR／release 連結。遇無法收斂的阻擋問題，保留可檢視結果、說明所需資訊／授權，不擅自 commit 或推送受影響內容。
