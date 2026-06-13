# Notification protocol — traffic-light, channel-agnostic

The loop reports to the human over a **push channel**. The *format* (traffic-light) is channel-independent; only the *transport* differs. Decide the channel + credential source in the skill's Q7, then wire `notify.sh` (or your own helper) accordingly.

> **Artifact-neutral by default.** The protocol assumes outputs are generic candidates (text, code, structured data, files). If your loop produces **media** (images/audio/video), see the *Media artifacts (optional)* note at the bottom — that part is opt-in, not core.

## Traffic-light format（每則開頭帶燈號）

| 燈 | 意思 | 何時 | 內容 |
|---|---|---|---|
| 🟢 | 進度（看一眼、不用動） | milestone 完成 N 個 candidate / phase 開始 | 一兩句：剛做完什麼 + 接下來。結尾固定「續跑中、不用動」。 |
| 🟡 | 注意（不阻塞、loop 續跑） | 重試 / 自癒已處理 / 有 workaround | 發生什麼 + 怎麼繞 + 是否要事後關注。 |
| 🔴 | 需要你（阻塞、要人介入） | `NEEDS_INPUT` / `ESCALATE` / `REFUSE` / gate 連續紅 | 開頭 `🔴 需要你：<具體動作>` + 帶具體欄位（卡哪、需要什麼決定、暫停範圍）。`ESCALATE` 必帶 delta。 |

## Triggers（什麼事件發 — milestone 粒度、不是 per-candidate）

- **Pre-flight 測通（第 0 步、硬擋）**：開跑前送一則測試 ping；**送不出去（helper 回非零）就不准開 loop**（通知靜默失敗 = 盲跑）。可要人回任意字確認雙向通。
- **per-milestone**：每完成**一個 phase / 一批 candidates / 一個工作項的所有變體**一則 🟢。🔴 **不要 per-candidate**（洗版）。把「milestone」定義成「一批、不是一個」。
- **事故已處理**：自癒後一則 🟡（不 stop-and-ask）。
- **收工 / 階段總結**：完成清單 + 各項通過數 + 阻塞 + 待人挑。
- **（選）心跳 pulse**：長靜默每 N 分鐘一則，防無人值守久跑讓人不安 / 補 silent-death（見 watchdog）。

## Channel-agnostic transport

| Channel | Transport | Credential（由 Q7 決定來源、env/config 注入）|
|---|---|---|
| Telegram | `sendMessage` / `sendPhoto` HTTP API（curl）| `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` |
| Discord | incoming webhook（curl POST）| `DISCORD_WEBHOOK_URL` |
| Slack | incoming webhook（curl POST、text-only）| `SLACK_WEBHOOK_URL` |
| iMessage | local `osascript`（macOS only）| `IMESSAGE_TO` |
| other | 自訂 | — |

**Credential source（Q7 決定，三種常見）**：
- (a) operator 互動時直接給 → 寫進該專案的私有 env / config（**不進 repo、不寫進 dispatch 文件正文**）。
- (b) operator 指一個 **config 檔路徑** → helper `NOTIFY_CONFIG=<path>` source 它。
- (c) operator 指定一個**安全的 config 來源**讓你取 → 取用即可。
- 🔴 **token / chat_id / webhook URL / handle 一律由 env 或 config 注入，永不寫進 skill、永不進 repo、永不寫進 dispatch 文件**（dispatch 只記「來源是哪個 env var / 哪個 config」，不記 secret 本身；dispatch 若會進 repo，路徑也要 redact）。

## Watchdog（選用、補無人值守 silent-death）

無人值守 job 會**靜默失敗、沒人知道**——常見模式：deadlock 卡死、`exit 0` 但輸出全空、執行環境中途中斷。若在意，在一個**常駐的、獨立於 loop 的**輕量 session 掛心跳：每 N 分鐘檢查「loop 還活著嗎」（輸出有沒有增長 / log 有沒有更新 / state 時間戳），偵測到停滯就發 🔴。**關鍵：watchdog 要獨立**（loop 自己死了就發不出自己的告警）。

## `notify.sh` 用法

```bash
NOTIFY_CHANNEL=telegram NOTIFY_CONFIG=/path/to/private-notify.env \
  notify.sh 🟢 "phase-1 done, 4/5 candidates passing, 續跑中不用動"
notify.sh 🔴 "需要你：input 缺，NEEDS_INPUT — 暫停 item-5"
```

- `NOTIFY_CHANNEL`（telegram|discord|slack|imessage）+ 對應 credential 由執行環境或 `NOTIFY_CONFIG` 注入。
- helper **送失敗回非零** → pre-flight gate 才真的擋得住。
- ⚠️ `NOTIFY_CONFIG` 是被 **source 的 shell 檔（會執行內容）** → 只指向你自己掌控的私有檔。
- ⚠️ webhook 類的 token / URL 會出現在 **process argv**（同機其他程序可能看到）→ 跑在信任的 host。
- 需 `curl`；webhook JSON escape 需 `python3`；圖壓縮需 `magick`/`convert`（pre-flight 一併檢查）。

## Media artifacts (optional — only if your outputs are media)

若 loop 產出是圖/影音（非預設）：milestone 通知可附一張**彙整圖（review bundle）**讓人快速初篩。注意：
- 🔴 媒體檔路徑要在**執行發送的那台機器**本機絕對路徑（遠端跑就先放那台 / 傳過去）。
- 大檔先壓（`notify.sh` 對 PNG/webp 自動壓 JPEG；需 magick/convert，否則送原檔），避免上傳 timeout。
- caption 帶 milestone handle（item id / 批次 / 輪數）讓人挑完對得回 recipe。
- Slack / iMessage（本 helper）只發文字、會略過媒體並在 stderr 警告。
