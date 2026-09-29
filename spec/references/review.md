# 審查與驗收判準

`SKILL.md` 只寫各階段的步驟；「怎樣才算過」全部寫在這裡。要改判準就改本檔，不要在 `SKILL.md` 另抄一份。

| 段落 | 哪個階段讀 |
|---|---|
| Spec Self-Review | Spec Stage 產完 `spec.md` 後 |
| Task 粒度 | Spec Stage 產 `tasks.md` 時 |
| AC 驗收 | Check Stage |
| 完成狀態 | 每個階段結束回報時 |

---

## Spec Self-Review

產完 spec.md 後，逐項檢查：

| 檢查項目 | 不通過怎麼辦 |
|---------|------------|
| 六要素都填了，沒有「待補」「TBD」？ | 回去補。模糊 = 沒想清楚 |
| 六要素之間一致？（範圍 vs 輸出、驗收 vs AC、邊界 vs 不做的事） | 對齊，有衝突就問 user |
| 每個 AC 都可測試？（不是「要好用」這種） | 改寫成可測試的條件 |
| 邊界條件有定義？（空輸入、超大檔、錯誤格式） | 補到 AC 或 Out of Scope |
| 範圍明確？（不做的事有列出來） | 補 Out of Scope |
| 外部依賴有交代？ | 補 Dependencies |
| 跟已有的 spec 衝突嗎？ | 標出衝突，問 user |

**Anti-Sycophancy（審查時禁止的行為）：**
- 不要說「這個 spec 看起來不錯」— 說具體哪裡通過、哪裡有問題
- 不要說「可以考慮加上 X」— 說「X 沒定義，這會在 Y 情況下炸掉」
- 不要自己腦補答案 — 不確定就問 user
- 如果 spec 有明顯漏洞，直接說「這個 spec 有問題」，不要包裝成建議

如果有不通過的項目，**當場問 user 釐清，不要自己猜**。

---

## Task 粒度

- 一個 task = 一個可以跟別人說「這個做完了」的交付物
- 通常對應 1-3 個檔案的改動
- 5-10 個 tasks 為一個 spec 的合理範圍
- 太細（「寫一個 function」）→ 合併
- 太粗（「完成整個模組」）→ 拆開

---

## AC 驗收

逐條對照 `spec.md` 的 Acceptance Criteria：

- 讀相關的 source code
- 如果 AC 可以用測試驗證，跑測試
- 如果 AC 是行為描述，讀 code 判斷
- 每條都要附證據（`file:line` 或測試輸出）；不用跟實作同一套邏輯反推期望值，否則驗收恆真

結果印在對話中，不另存檔：

```
## Acceptance Criteria Check

| AC | Status | Evidence |
|----|--------|----------|
| AC-1: ... | PASS | [file:line or test result] |
| AC-2: ... | FAIL | [what's missing or wrong] |
```

---

## 完成狀態

每個階段結束時，用以下狀態回報：

| 狀態 | 意思 | 後續動作 |
|------|------|---------|
| **DONE** | 全部完成，有證據 | 進入下一階段 |
| **DONE_WITH_CONCERNS** | 完成了，但有疑慮 | 列出疑慮，問 user 要不要處理 |
| **BLOCKED** | 卡住了，無法繼續 | 說明卡在哪、試過什麼、建議怎麼解 |
| **NEEDS_CONTEXT** | 缺少資訊，無法判斷 | 明確說需要什麼資訊 |
