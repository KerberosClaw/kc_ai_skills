> **English summary:** Design document for the `/spec` skill — a spec-driven development workflow that guides users from fuzzy requirements to verified deliverables. One entry point, auto-detects project state, handles both small features and large multi-module projects.

# /spec Skill — 設計文件

## 解決什麼問題？

用 AI agent 寫 code 最常見的災難：

1. **需求沒想清楚就開工** → 做到一半發現方向錯，砍掉重來
2. **換一個對話就失憶** → 重新解釋一次上下文，浪費時間
3. **做完沒驗收** → 自以為做完了，其實漏了一堆邊界條件
4. **沒有紀錄** → 三個月後回來看 code，忘記當初為什麼這樣設計

這套流程用檔案把每個階段的產出持久化，讓 agent 跨對話也能接著做。

## 為什麼是一個 skill 而不是多個？

早期設計考慮過拆成 4 個 skill（spec-init / spec-review / spec-check / spec-report），但：

- User 要記多個指令，認知負擔高
- 不清楚「現在該打哪一個」
- 開源後新 user 學習成本更高

最終決定：**一個 `/spec` 入口，靠檔案狀態自動判斷階段**。User 只要記一個指令。

## 為什麼需要 Discovery Stage？

不是每個需求都適合直接產 spec。判斷標準：

| 情況 | 例子 | 處理方式 |
|------|------|---------|
| 明確的單一功能 | 「做一個 Markdown loader」 | 直接 Spec Stage |
| 模糊的大系統 | 「做一個 RAG pipeline」 | 先 Discovery → DESIGN.md → 再拆 spec |

Discovery 的產出是 `docs/DESIGN.md`，這份文件會被後續所有 spec 引用作為上下文。

## 審查機制的設計

參考了 gstack 的量化評分（資料模型 10/10、API 9/10），但認為對個人開發者來說：

- 分數本身沒有 actionable 的意義（8/10 跟 9/10 差在哪？）
- 重要的是「有沒有漏洞」，不是「打幾分」

所以改成 **checklist-based self-review**：逐項檢查，不通過就問 user 釐清，不打分。

另外從 gstack 的 office-hours skill 借鏡了 **anti-sycophancy** 原則 — 審查時禁止說「看起來不錯」「可以考慮」這種模糊話。有問題就直說，不要包裝成建議。

## Forcing Questions 的設計

Discovery Stage 的問題設計參考了 gstack `/office-hours` 的 Six Forcing Questions。核心理念：

- **逐題問**，不要一次丟一堆問題
- 每題有明確的「推到什麼程度才算過關」標準
- 每題有 **red flags**（聽到這些話就代表答案不夠具體，要追問）
- 不是每題都要問 — 根據 user 已提供的資訊跳過

差異：gstack 的 forcing questions 是為 startup 設計的（market fit、demand reality），我們的是為 **技術專案** 設計的（痛點、技術限制、最小範圍、明確排除）。

## Completion Status Protocol

參考 gstack 的 status protocol（DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT），加入我們的流程中。提供比單純 pass/fail 更細緻的狀態回報。

同時加入 **三振原則**（參考 gstack `/investigate` 的 iron law）：同一個問題試 3 次不同方法都失敗 → 停下來跟 user 說，不要硬做。

## Task 粒度的設計

太細會失焦（「寫一個 function」），太粗沒追蹤價值（「完成整個模組」）。

原則：**一個 task = 一個可驗證的交付物**，通常對應 1-3 個檔案的改動。

一個 spec 合理的 task 數量是 5-10 個。超過就該拆成兩個 spec。

## 與 Claude Code 的整合

| Claude Code 功能 | 我們怎麼用 |
|-----------------|-----------|
| Plan Mode | Implement Stage 進入 Plan Mode，用 plan.md 作為骨架 |
| Task 系統 | 對話內追蹤進度，但 tasks.md 才是 source of truth |
| Memory | 不重複 — memory 記 user 偏好，spec 記專案狀態 |

Claude Code 的 Plan / Task 是**對話內**的工具，spec 檔案是**跨對話**的持久化。兩者互補不衝突。

## 語言策略

- 與 user 互動：正體中文
- 文件內容（spec/plan/tasks/report）：正體中文（貼近使用者思考語言）
- 文件摘要：英文 English summary（方便開源、國際化、快速掃描）

## 靈感來源

- [gstack](https://github.com/garrytan/gstack)（Garry Tan, Y Combinator CEO 的開源專案）
  - `/office-hours` — Forcing Questions + anti-sycophancy 設計
  - `/plan-ceo-review` — Scope 模式（擴張/維持/縮減）
  - `/investigate` — 三振原則（失敗 3 次就停）
  - `/autoplan` — 一個入口串跑所有審查
  - Completion Status Protocol（DONE / BLOCKED / NEEDS_CONTEXT）
- Tung-hsing Hsieh 在 Facebook「Generative AI 技術交流中心」社團的分享 — 最初觸發 spec-driven 流程的構想
- 本 skill 是獨立設計的實作，借鏡 gstack 的原則但不是 fork — gstack 定位是 28 個專家角色的虛擬團隊（含 browser daemon、QA、deploy），我們定位是輕量的開發流程框架
