---
name: job-radar
description: "kc_job_radar 求職雷達遙控指令。觸發詞：寫信、整理雷達、搜尋職缺、評估雷達、刷新追蹤。"
version: 1.1.0
---

# Job Radar — 求職雷達遙控台

## 重要：你不需要直接存取 Google Sheet

所有 Google Sheet 操作都在 Docker 容器內執行（容器掛載了 credentials.json）。你只需要跑 Docker 指令，容器內的 Python 會處理 Sheet 讀寫。**不要嘗試自己操作 Google Sheet API。**

## 專案路徑

- 專案目錄：`~/Developer/kc_job_radar/`
- Docker 執行檔：`~/.orbstack/bin/docker`
- 設定檔：`~/Developer/kc_job_radar/config.yaml`

---

## 指令清單

### 1. 寫信

**觸發詞：** 「寫信」「寫求職信」

**執行流程：**

1. 檢查 `~/Developer/kc_job_radar/data/context/` 是否有 `.md` 檔案。沒有就回覆「沒有待處理的求職信」並結束
2. 逐一讀取每個 `.md` 檔案，**照檔案裡的指令寫求職信**（檔案內有完整的規則、履歷、JD）
3. 每封信存到檔案中指定的 output 路徑（`data/output/*.txt`）
4. 全部寫完後打包：

```bash
cd ~/Developer/kc_job_radar/data/output && zip -j cover_letters.zip *.txt
```

5. 讀 `~/Developer/kc_job_radar/config.yaml` 取得 `telegram.bot_token` 和 `telegram.chat_id`，傳送 zip：

```bash
BOT_TOKEN="從 config.yaml 讀取"
CHAT_ID="從 config.yaml 讀取"
curl -F "document=@/Users/otakubar/Developer/kc_job_radar/data/output/cover_letters.zip" \
     -F "chat_id=$CHAT_ID" \
     "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
```

6. 刷新 Sheet（Docker 容器處理，不是你）：

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm refresh
```

7. 清理：刪除 `data/context/*.md` 和 `data/output/cover_letters.zip`

---

### 2. 整理雷達

**觸發詞：** 「整理雷達」「跑 process」

**做什麼：** 封存「沒興趣」的職缺 + 搬移「想投遞」到追蹤中 + 產生求職信 context

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm process 2>&1 | grep -E '^[⚡🗑️📤✉️🔄✅📝]|筆|完成|封存|搬移'
```

指令已用 grep 過濾只留摘要行。

---

### 3. 搜尋職缺

**觸發詞：** 「搜尋職缺」「跑 radar」

**做什麼：** 搜尋 104 新職缺 + 篩選 + 去重 + 寫入雷達 tab

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm radar 2>&1 | grep -E '^[📊📋✅🗑️🔍📈]|筆|完成|封存'
```

耗時較長，先回覆「搜尋中，請稍候...」。指令已用 grep 過濾只留摘要行，不要用不帶 grep 的版本（output 太長會吃爆 token）。

---

### 4. 評估雷達

**觸發詞：** 「評估雷達」「跑 scout」

**做什麼：** 評估雷達 tab 中未評分的新職缺

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm scout
```

執行完畢後只回傳摘要行（含 📊📋✅🗑️📤🔄📝 等 emoji 開頭的行）。

---

### 5. 刷新追蹤

**觸發詞：** 「刷新追蹤」「refresh」「刷新」

**做什麼：** 掃 Gmail 104 通知信更新狀態 + 重算天數 + 排序 + 超時封存

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm gmail-watch && ~/.orbstack/bin/docker compose run --rm refresh
```

執行完畢後只回傳摘要行（含 📊📋✅🗑️📤🔄📝 等 emoji 開頭的行）。

---

## 通用規則

- Docker 指令一律用 `~/.orbstack/bin/docker`
- **所有 Google Sheet 操作都透過 Docker 容器，不要自己操作 Sheet**
- 指令執行失敗時回傳 stderr，不要自行重試
- Docker daemon 未啟動時提醒使用者開啟 OrbStack
- 回覆語言：繁體中文
