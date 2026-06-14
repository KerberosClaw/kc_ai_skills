# PRD：辦公室智慧電燈 IoT POC

> **Fixture status**：Mode β 精簡示範（§1-§4 + §11 + §14 + §15 具體填，其他章節用 `<!-- 略 -->` 標記）。本 fixture 用於 illustrate POC PRD 該長什麼樣子，非真實專案。

**版本**：v0.1 draft
**Owner**：PRD 撰寫者（產品方），實作工程師（implementation backup）
**遵循**：org 自家 PRD 撰寫 Guideline

---

## 1. Overview & Context

辦公室公共區域（茶水間 / 會議室 / 走廊）的照明用既有手動開關控制，下班後常忘關造成電費浪費；上班時間進空房間又要找開關不方便。POC 用 ESP32 + 動作感測器 + LED 燈條做智慧照明 demo：偵測到人 → 自動開燈；無人 N 分鐘 → 自動關燈。多 mode 切換配合作息時段（上班 / 下班 / 假日）。

**Stakeholder**：辦公室總務（end user，end-of-day 巡檢省力）；行政部（PM 提需求）；硬體工程師（implementer）。

**上下游**：
- 上游：行政部提供作息時段需求 + 茶水間 / 走廊既有照明位置 layout
- 下游：POC 通過後評估 production 部署到全公司公共區域

---

## 2. Goals / Non-Goals

### Goals

- **G1**：POC 階段做出可 demo 的單一空間（茶水間）智慧照明系統
- **G2**：以人工觸發測試（手在 sensor 前揮動）+ 模擬時段切換 mode 驗證 sensor → 邏輯 → LED 端到端可跑
- **G3**：建立可被實作工程師接手的 codebase（PRD → 接 implement）

### Non-Goals

- ❌ **不做** 跨建築 / 多空間 fleet 同步 / 雲端 dashboard
- ❌ **不做** 燈光顏色 / 亮度動態調整（POC 用單一白光固定亮度）
- ❌ **不做** 人臉識別 / 個人化（POC 純動作觸發，不識別誰）
- ❌ **不做** SLO / RTO / RPO 量化指標（POC 不適用）
- ❌ **不做** 多模式自動學習（POC 純規則 based，無 ML）
- ❌ **不做** OTA 自動更新（人工 USB 燒錄）

### Constraints

- **POC 預估**：2 週（hardware 1 週 + firmware 1 週）
- **Hardware**：ESP32-S3 dev board（既有）+ PIR motion sensor HC-SR501（既有）+ WS2812B LED 燈條 1m（既有）+ 5V 電源 USB
- **預算**：使用既有 hardware，不採購
- **法規 / 授權**：辦公室公共區域照明屬內部設施，無外部合規需求

---

## 3. User Stories & Personas

### Persona

- **辦公室同仁**（end user）：進茶水間 → 燈自動亮；離開 N 分鐘 → 燈自動暗
- **總務**（操作員）：手動切 mode（上班 / 下班 / 假日 / 關閉），週末 / 連假關照明省電
- **PoC 開發者**：用按鈕模擬 sensor trigger 做 dev / debug，免實機架 sensor

### User Stories

- **US-1**：作為辦公室同仁，我走進茶水間 sensor 範圍 → LED 燈條 1 秒內亮起，產生即時照明體驗
- **US-2**：作為總務，我能在系統面板按鍵切換「上班」/「下班」/「假日」模式，不需要每天進設定
- **US-3**：作為開發者，我能用 dev board 內建按鈕模擬 sensor trigger，免架 PIR 即可驗證 firmware 行為

---

## 4. Functional Requirements

### 感測層

- **FR-001**：系統用 PIR motion sensor 持續偵測（1 Hz polling），偵測「動作」事件
- **FR-002**：偵測到動作 → 觸發「亮燈」事件（無冷卻時間）
- **FR-003**：無動作持續 N 分鐘（依 mode 不同，見 FR-020）→ 觸發「暗燈」事件

### 邏輯 / 狀態層

- **FR-010**：系統有兩個 LED 狀態：ON（白光，固定亮度 80%）/ OFF。狀態切換有 fade-in/out 200ms transition
- **FR-011**：多次動作觸發時，每次觸發**重置「無動作計時」**（保持燈亮，不疊加 timeout）

### 模式切換

- **FR-020**：系統支援 4 個 mode，影響「無動作關燈延遲」：
  - **上班 mode**（默認）：5 分鐘無動作 → 暗
  - **下班 mode**：30 秒無動作 → 暗（節電優先）
  - **假日 mode**：禁用 sensor，全天暗
  - **強制亮 mode**：不管 sensor，全天亮（清潔 / 維修用）
- **FR-021**：mode 切換用 dev board 內建按鈕循環切換（4 模式 round-robin），LED 燈條短暫閃爍 2 次表示確認切換成功
- **FR-022**：開機默認讀取 EEPROM 上次儲存的 mode（系統 reboot 不會掉 mode 設定）

### 失敗 fallback

- **FR-030**：PIR sensor 讀值異常（持續 1 分鐘無 trigger 也無 quiet）→ 系統 fallback 到「強制亮 mode」+ LED 慢閃 1 Hz 警示維修

---

## 5. Non-Functional Requirements

<!-- 略：POC 不嚴格量化 NFR；目標方向：sensor → 燈反應 < 1 秒、mode 切換立即生效、firmware 不 crash 至少 24 小時 -->

---

## 6. System Architecture

<!-- 略：single ESP32-S3 board，PIR sensor 接 GPIO，LED 燈條接 GPIO + 5V power，內建按鈕接 GPIO 中斷。Firmware Arduino IDE / PlatformIO 開發 -->

---

## 7. Data Model

<!-- 略：無 DB，EEPROM 存 1 byte mode index -->

---

## 8. API Contract

<!-- 略：無對外 API，純 firmware -->

---

## 9. Security & Privacy

<!-- 略：辦公室內部設施，無外部 attack surface；PIR 不識別個人身份，無個資 -->

---

## 10. Observability

<!-- 略：POC firmware 用 Serial.print debug，無遠端 log -->

---

## 11. Risks & Mitigations

| 風險 | 機率 | 衝擊 | 緩解措施 |
|---|---|---|---|
| **PIR sensor 誤觸發**（風吹簾子 / 螢幕保護動畫）| M | L | 加 confidence threshold（連續 2 次偵測才算 trigger）；POC 實測 calibration |
| **LED 燈條電流過高超過 ESP32 GPIO 能力** | M | H | 加 N-channel MOSFET 隔離；POC 第一週硬體階段 verify |
| **EEPROM 寫入次數限制**（mode 切換頻繁 wear 出問題）| L | M | 改用 NVS（non-volatile storage）+ 寫入頻率限制（10 秒內多次切換只寫 1 次） |
| **Firmware 跑久了 memory leak crash** | M | M | POC 階段每天 reboot 一次（cron-like 排程）規避 |
| **PIR 偵測範圍不足**（茶水間死角）| L | M | 實機 placement 階段量測 + 必要時加第 2 顆 sensor |

---

## 12. Rollout & Migration Plan

<!-- 略：POC 部署 = 把 board + sensor + LED 燈條裝茶水間，USB 供電 -->

---

## 13. Test Strategy

<!-- 略：unit test firmware state machine（mock sensor input）；integration 用按鈕模擬 sensor；E2E 茶水間實裝 24 小時觀察 -->

---

## 14. Open Questions

| # | 問題 | 答案 / 處理 | 對誰 | 何時 confirm |
|---|---|---|---|---|
| Q1 | PIR sensor 偵測範圍夠不夠涵蓋茶水間 | ⏳ POC 第一週實機量測 | 實作工程師 | POC 第一週 |
| Q2 | 「下班 mode」30 秒是否太短（同仁進去拿東西馬上熄）| ⏳ POC 第二週實測調整 | 行政部 + 總務 | POC 第二週 |
| Q3 | LED 燈條亮度 80% 夠不夠（茶水間環境光不同）| ⏳ 實機調整 | 總務 | 實機到位後 |
| Q4 | mode 切換按鈕位置（板子位置難按 vs 牆上開關位置改裝成本） | ⏳ 跟行政部對齊 | 行政部 | POC 第一週前 |
| Q5 | 假日 mode 自動觸發機制（POC 純手動 vs 之後加 RTC）| ⏳ POC scope 拍板 | PRD 撰寫者 | （已答：POC 純手動）|
| Q6 | Hardware 規格（ESP32-S3 vs ESP32-WROOM 哪個既有 stock）| ⏳ 實作工程師清點 | 實作工程師 | POC 第一週前 |

---

## 15. Appendix

### 參考文件

- ESP32-S3 datasheet
- PIR HC-SR501 datasheet
- WS2812B 燈條 wiring guide
- org 自家 PRD 撰寫 Guideline

### 對 Guideline 的偏離（Deviation）

POC 2 週 deliverable 對應 org PRD Guideline 的偏離理由：

- **§3.1 三張 C4 圖**：本 POC 是 single board firmware，無 system layer 必要，§6 用簡化 mermaid 描述硬體 wiring 即可
- **§3.4 量化 NFR**：POC 不適用 SLO 99.9% 等指標，改方向性敘述（sensor 響應 < 1 秒、24 hr 不 crash）
- **§4.1 不可變性**：POC firmware 不用 event sourcing
- **§4.5 可觀測性**：POC 純 Serial.print，不上 trace_id / metric platform
- **§7 測試覆蓋率 80%**：POC 階段不強制覆蓋率，重點在 24 小時實機 E2E 觀察
- **§9 Security 威脅模型**：辦公室內部設施 N/A，attack surface 為 0

正式 production 階段（推廣到全公司公共區域）若決定推進，須補齊 Guideline 完整章節 + ADR（mesh networking、雲端 dashboard、OTA、log 中央化等）。

### 變更管理

PRD v0.x draft 期間隨 POC 進度調整（如 Q5 假日 mode 已答）；鎖 v1.0 後若有變更走 ADR。本 POC 階段不強制要求 ADR，但若 sensor 選型 / mode 邏輯 / LED 控制方式有重大變更，建議落 ADR。
