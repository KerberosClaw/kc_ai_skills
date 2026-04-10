---
name: skill-cron
description: "排程推播管理器 — 註冊/管理需定時執行並推送 Telegram 通知的 skill。Use when user says '/skill-cron', '排程', '定時執行', 'crontab', 'telegram 通知' or similar."
version: 0.2.0
---

# skill-cron

統一管理需要定時執行 + Telegram 推播的 skill。

## Trigger

```
/skill-cron
```

不帶參數時顯示主選單。也可帶子命令快速操作（如 `/skill-cron list`）。

---

## 主選單

收到 `/skill-cron` 時，顯示以下選單（使用 AskUserQuestion 詢問）：

```
┌─ skill-cron 排程管理器 ─────────────┐
│                                      │
│  1. 列出排程與狀態                    │
│  2. 新增排程                         │
│  3. 移除/啟停排程                    │
│  4. Telegram 設定                    │
│  5. 手動執行一次                     │
│                                      │
└──────────────────────────────────────┘
```

詢問：「輸入編號 [1-5]」

使用者只能輸入 1-5。輸入其他內容時重新顯示選單。

---

## 選項 1：列出排程與狀態

執行：

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py list
```

將輸出整理成表格呈現。

---

## 選項 2：新增排程

### Step 2-1：選擇 skill

掃描 `~/.claude/skills/` 下所有包含 `headless-prompt` 的 SKILL.md，列出可排程的 skill：

```
可排程的 skills：
  a. banini — 巴逆逆反指標追蹤器
  b. xxx — ...

沒有找到？skill 需要在 SKILL.md frontmatter 加入 headless-prompt 欄位。
```

詢問：「選擇 skill [a/b/...]」

如果只有一個，直接選定並確認。

### Step 2-2：排程時間（自然語言 → cron）

詢問：「排程時間（用自然語言描述，如『平日 9:00 18:00，假日不執行』）」

**你（Claude）負責將自然語言轉換為 cron 表達式。** 轉換規則：

#### 時間詞彙對應

| 自然語言 | 對應 |
|---------|------|
| 平日/工作日 | 週一~五（1-5） |
| 假日/週末 | 週六日（0,6） |
| 每天 | 所有天（*） |
| 週一/Monday | 1 |
| 週二~週日 | 2~0 |
| 不執行 | 該天不產生 cron entry |

#### 衝突偵測（重要）

當使用者的描述中出現重疊時，**必須詢問**而非自行決定。

衝突範例：

```
使用者：平日 9:00, 18:00 假日不執行 週一 9:30

⚠ 偵測到衝突：
  「平日 9:00」已涵蓋週一，但又指定「週一 9:30」
  週一要怎麼處理？
    a. 9:00, 18:00（跟其他平日一樣，忽略 9:30）
    b. 9:30, 18:00（週一用 9:30 取代 9:00）
    c. 9:00, 9:30, 18:00（三個都要）
```

衝突判定規則：
- 「平日」和具體「週X」重疊 → 衝突
- 「每天」和「假日不執行」→ 衝突
- 「週六 10:00」和「假日不執行」→ 衝突
- 同一天同一時間重複出現 → 去重，不算衝突

#### 解析結果確認

轉換完成後，顯示解析結果表格讓使用者確認：

```
解析結果：
┌──────────────────────────────────────┐
│  週一     09:30, 18:00               │
│  週二~五  09:00, 18:00               │
│  週六~日  不執行                      │
├──────────────────────────────────────┤
│  共 9 次/週                          │
│  cron entries:                       │
│    30 9 * * 1                        │
│    0 9 * * 2-5                       │
│    0 18 * * 1-5                      │
└──────────────────────────────────────┘

確認？ [Y/重新輸入]
```

使用者確認後才進入下一步。

### Step 2-3：標籤

詢問：「給這組排程一個標籤（如『盤中追蹤』『每日報告』）」

### Step 2-4：寫入

對每一條 cron entry 呼叫：

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py add <skill> "<cron_expr>" "<label>"
```

如果一組自然語言產生多條 cron entries，每條各自建立一個 job（用 label + 序號區分）。

---

## 選項 3：移除/啟停排程

先跑 `list` 顯示現有 jobs，然後：

```
要做什麼？
  a. 移除排程
  b. 啟用排程
  c. 停用排程
  d. 返回主選單
```

選擇後，讓使用者指定 job ID。

對應指令：
```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py remove <job_id>
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py enable <job_id>
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py disable <job_id>
```

---

## 選項 4：Telegram 設定

顯示目前狀態後：

```
Telegram 狀態：未設定 / 已設定（token: 123...ABC → channel: -100xxx）

  a. 設定 Bot Token + Channel ID
  b. 發送測試訊息
  c. 移除設定
  d. 返回主選單
```

### 4-a：設定

依序詢問：

1. 「貼上 Bot Token（從 Telegram @BotFather 取得）：」
2. 「貼上 Channel ID（頻道或群組 ID，通常以 -100 開頭）：」

拿到後：

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py telegram-set <bot_token> <channel_id>
```

儲存後詢問：「要發送測試訊息嗎？ [Y/n]」

### 4-b：測試

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py telegram-test
```

### 4-c：移除

確認後：

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py telegram-remove
```

---

## 選項 5：手動執行一次

先跑 `list` 顯示現有 jobs，讓使用者選擇要執行哪一個。

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/cron_manager.py run <job_id>
```

顯示執行結果。如有 Telegram 設定，會自動推送。

---

## 設定檔

位置：`~/.claude/configs/skill-cron.json`

```json
{
  "telegram": {
    "bot_token": "123:ABC...",
    "channel_id": "-100..."
  },
  "jobs": [
    {
      "id": "banini-盤中-1",
      "skill": "banini",
      "cron": "30 9 * * 1",
      "label": "盤中",
      "enabled": true
    }
  ]
}
```

## Skill 整合規範

要讓一個 skill 支援 skill-cron 排程，需在其 SKILL.md frontmatter 中加入 `headless-prompt`：

```yaml
---
name: banini
headless-prompt: "Run python3 ~/.claude/skills/banini/scripts/scrape_threads.py banini31 5, then analyze..."
---
```

規則：
- 必須使用絕對路徑（`~` 可以）
- 不能使用 `/skill` 語法（`-p` 模式不支援）
- 要包含完整的指令描述（Claude 需要知道要做什麼）

## 日誌

排程執行的日誌存放在：`~/.claude/logs/skill-cron/`

每個 job 保留最近 50 筆 log，自動清理舊的。

## 互動規則

- **所有輸入都用選項或固定格式** — 不接受開放式自然語言（排程時間除外）
- **排程時間是唯一例外** — 允許自然語言，但必須解析後確認才寫入
- **偵測到衝突必須問** — 不能自行決定衝突的解法
- **每個破壞性操作（移除、覆蓋）都要確認** — 不能直接執行
- **不認識的輸入重新顯示選單** — 不要嘗試理解使用者在說什麼

## 注意事項

- 排程使用 macOS launchd（LaunchAgent），不使用 crontab（crontab 缺乏 OAuth 所需的 user session）
- plist 檔案由 cron_manager.py sync 自動管理，存在 `~/Library/LaunchAgents/com.skill-cron.*.plist`
- Telegram bot token 存在本地 config 中，不會被 git 追蹤
- `claude -p` 需要有效的 Claude 訂閱
- 排程執行時 Claude 會使用與互動模式相同的模型
