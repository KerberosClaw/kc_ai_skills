---
name: job-radar
description: "kc_job_radar 專案遙控指令。透過 Telegram 觸發求職雷達的各項功能：寫求職信、跑爬蟲、跑評估、刷新 Sheet。"
version: 1.0.0
---

# Job Radar — 求職雷達遙控台

## 專案路徑

- 專案目錄：`~/Developer/kc_job_radar/`
- Docker 執行檔：`~/.orbstack/bin/docker`
- 設定檔：`~/Developer/kc_job_radar/config.yaml`（含 `telegram.bot_token` 和 `telegram.chat_id`）

---

## 指令清單

以下指令由使用者在 Telegram 中發送訊息觸發。比對時忽略大小寫與前後空白。

---

### 1. 寫求職信

**觸發詞：** 訊息包含「寫求職信」

**執行流程：**

1. 讀取 `~/Developer/kc_job_radar/data/context/` 下所有 `.md` 檔案
2. 每個 `.md` 檔案內含該封求職信的指示（目標公司、職位、特殊要求等），依照檔案中的指示撰寫求職信
3. 讀取 `~/Developer/kc_job_radar/data/resume.md` 作為個人背景參考
4. 每封求職信存為 `.txt`，檔名格式：`{公司名稱}_{職位}.txt`，存放於 `~/Developer/kc_job_radar/data/output/`
5. 將 `data/output/` 下所有 `.txt` 打包成 zip：

```bash
cd ~/Developer/kc_job_radar/data/output && zip -j cover_letters.zip *.txt
```

6. 讀取 `~/Developer/kc_job_radar/config.yaml` 取得 `telegram.bot_token` 和 `telegram.chat_id`，透過 Telegram Bot API 發送 zip 檔：

```bash
curl -F "document=@/Users/otakubear/Developer/kc_job_radar/data/output/cover_letters.zip" \
     -F "chat_id=CHAT_ID" \
     "https://api.telegram.org/botBOT_TOKEN/sendDocument"
```

7. 刷新 Google Sheet（Docker 容器內有 credentials.json，可直接存取 Sheet API）：

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm refresh
```

8. 清理：刪除 `data/context/` 下已處理的 `.md` 檔案，刪除 `data/output/cover_letters.zip`

**注意事項：**
- 如果 `data/context/` 為空，回覆使用者「沒有待處理的求職信指示」，不執行後續步驟
- 求職信語氣專業但不制式，展現個人特色
- 每封信要針對該公司/職位客製化，不要用萬用模板

---

### 2. 跑 process

**觸發詞：** 訊息包含「跑 process」

**執行：**

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm process
```

執行完畢後將 stdout 最後 30 行回傳給使用者。

---

### 3. 跑 scout

**觸發詞：** 訊息包含「跑 scout」

**執行：**

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm scout
```

執行完畢後將 stdout 最後 30 行回傳給使用者。

---

### 4. refresh

**觸發詞：** 訊息包含「refresh」或「刷新」

**執行：**

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm refresh
```

執行完畢後將 stdout 最後 30 行回傳給使用者。

---

### 5. 跑 radar

**觸發詞：** 訊息包含「跑 radar」

**執行：**

```bash
cd ~/Developer/kc_job_radar && ~/.orbstack/bin/docker compose run --rm radar
```

這個指令耗時較長（爬蟲 + 篩選），執行前先回覆「雷達啟動中，請稍候...」。執行完畢後將 stdout 最後 50 行回傳給使用者。

---

## 通用規則

- 所有 Docker 指令必須使用 `~/.orbstack/bin/docker`，不要用系統預設的 docker
- 指令執行失敗時，將 stderr 回傳給使用者，不要自行重試
- 如果 Docker daemon 未啟動（OrbStack 未開），提醒使用者先開啟 OrbStack
- 回覆語言：繁體中文
