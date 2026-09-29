# 功能名稱

> **English summary:** One-line summary of what this feature does and why.

## 六要素摘要（Task Prompt Schema）

這個區塊是結構化欄位，給 pm-sync 這類外部工具 parse 用。填得模糊就代表還沒想清楚，回去修。

- **目標（Goal）：** [一句話：這個 feature 要達成什麼]
- **範圍（Scope）：** [精確路徑清單，如 `src/api/users.ts`, `tests/users.test.ts`]
- **輸入（Inputs）：** [上游依賴：schema、API spec、前置 spec、環境變數]
- **輸出（Outputs）：** [交付物：新檔案 / 新 API endpoint / 新測試 / schema migration]
- **驗收（Acceptance）：** [指向下方 AC 列表，或直接摘要「見 AC-1〜AC-3」]
- **邊界（Boundaries）：** [指向下方「不做的事」，或直接摘要]

## 背景

為什麼需要這個功能。如果有 DESIGN.md，標註對應的章節。

## 驗收條件

- [ ] AC-1: [具體、可測試的條件]
- [ ] AC-2: [具體、可測試的條件]
- [ ] AC-3: ...

## 不做的事

- [明確排除的項目]
- [另一個排除項目]

## 依賴

- [外部服務、套件、或必須先完成的其他 spec]
