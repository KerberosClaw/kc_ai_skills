# ios-resign 測試紀錄

## 怎麼跑

```bash
tests/run.sh      # 離線測試：假的 xcodebuild／xcrun／defaults／security／codesign，不碰手機、不用 Apple 帳號
tests/mutate.sh   # 突變測試：逐一改壞關鍵判斷，測試要抓得到
```

## 2026-10-09 v0.1.0

### 離線與突變

- `tests/run.sh`：39 項全過
- `tests/mutate.sh`：26 個突變全抓到。第一輪漏抓「忽略 default_variant」，補了測試案例

### 實機只編譯（不裝手機）

三個專案各自的 worktree，`--build-only`：

| 專案 | 版本 | 結果 | 這輪抓到的問題 |
|---|---|---|---|
| 步數編輯器 | prod | 編過，建置前指令確認 Rust 產物最新 | — |
| 熊熊在哪裡 | prod、dev | 都編過 | dev 用 `Debug-Dev` 設定，產物卻在 `Release-iphoneos`：腳本原本假設資料夾與設定同名而找不到 `.app`，改成在專案專屬資料夾取最新的 |
| 打卡 | prod、dev | 都編過 | 兩個 repo 的 worktree 同名時共用了編譯資料夾，改成名稱加路徑雜湊 |

兩個問題都補了離線測試與突變。

### 無脈絡 LLM（照 `/doc-qa:qa` 的精神：從 SKILL.md 推出要求 → 可追溯的案例 → 執行 → 證據）

Claude 用新開的 subagent、Codex 用前景 `codex exec -s danger-full-access`，只給「使用者說了什麼」與兩條測試規則（不准裝手機、不准改專案資料夾）。
測試專案是另外 clone 的，**沒有 `resign.local.yaml`，也就沒有任何手機**。每輪結束檢查 `git status` 確認專案沒被改。

| 案例 | 對應 SKILL.md | Claude | Codex |
|---|---|---|---|
| TC1 說「重簽」但沒設定手機 | 重簽模式 R1、碼 10 | 通過：停下來提議設定模式 | **第一輪失敗**：自己改跑 `--build-only` 並回報「完成」；SKILL.md 補了明文規定後重跑通過 |
| TC2 「只確認開發版編得過」 | R1 `--build-only`、`--variant` | 通過（第一輪因測試規則寫太嚴、連快取都不准寫而停下，放寬後重跑） | 通過 |
| TC3 給碼 31 的輸出 | 碼 31 是部署成功 | 通過：不重跑、給信任路徑與網路提醒 | 通過 |
| TC4 給碼 17 的輸出 | 碼 17 問使用者刪哪個 | 通過：列出三個、問使用者，不自己加 `--allow-over-limit` | 通過 |
| TC5 全新 repo 說「設定重簽」 | 設定模式 S1～S4 | 通過：偵察、起草兩份 YAML、等確認、沒寫檔 | 通過 |

TC5 兩邊都照「先讀 repo 規則」把簽章團隊放進 `resign.local.yaml`（該 repo 規定個人團隊不進 Git），
也因此抓到人寫的 `resign.yaml` 誤把團隊寫進了版控，已改正。

### 沒驗到的

- 真的裝到手機（這輪刻意不裝）；安裝、啟動、碼 31／32 的分類只在離線測試用假的 devicectl 輸出驗過，
  輸出文字照網路上回報的實際錯誤訊息寫
- 「不在專案資料夾裡、照使用者環境的專案索引找」這條路徑：要等索引連結合併後才能驗
