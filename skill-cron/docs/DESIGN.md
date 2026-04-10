# skill-cron — 因為 `claude -p "/banini"` 會卡住

> **English summary:** Design doc for skill-cron, a launchd-based scheduler for Claude Code skills. Born from discovering that `claude -p "/skill"` hangs silently — skills only work in interactive mode. Solution: a `headless-prompt` field in SKILL.md frontmatter + a runner script. Uses macOS launchd (not crontab) because `claude -p` needs the user's login session for OAuth — crontab runs in a bare daemon context without it. Includes Telegram push via urllib and auto-rotating logs.

## 這東西為什麼存在

Claude Code 的 skill 在互動模式下很好用 — 打 `/banini` 就跑。但如果你想用排程定時跑呢？

```bash
# 你以為可以這樣
claude -p "/banini"

# 實際上會無限卡住，沒有任何輸出
# 我們在凌晨一點 debug 了 40 分鐘才搞懂為什麼
```

官方文件寫了，但埋在一段不起眼的地方：

> "User-invoked skills like `/commit` are only available in interactive mode. In `-p` mode, describe the task you want to accomplish instead."

翻譯：**`claude -p` 不支援 `/skill` 語法。** 它不會報錯，它只是卡住。靜靜地。直到你 `Ctrl+C`。

所以你得用直接描述的方式：

```bash
# 這個能跑
claude -p "Run python3 ~/.claude/skills/banini/scripts/scrape_threads.py banini31 5, then analyze..."
```

但你不可能把這種一百字的 prompt 塞進排程設定。於是 skill-cron 誕生了。

---

## 設計思路

### 職責分離

```
Skill（如 /banini）
  = 純核心功能：爬蟲 + 分析 + 輸出
  = 只管做事，不管什麼時候做

skill-cron（管理器）
  = 什麼時候做：launchd 排程
  = 做完通知誰：Telegram 推播
  = 怎麼在 -p 模式跑 skill：headless-prompt 橋接
```

一個 skill 不需要知道自己會被排程。一個排程系統不需要知道 skill 在做什麼。中間靠一個叫 `headless-prompt` 的欄位連接。

### headless-prompt：給 `-p` 模式用的翻譯層

在 SKILL.md 的 frontmatter 加一個欄位：

```yaml
---
name: banini
headless-prompt: "Run python3 ~/.claude/skills/banini/scripts/scrape_threads.py banini31 5, then analyze..."
---
```

規則是從踩坑中學來的：

- **必須用絕對路徑** — `${CLAUDE_SKILL_DIR}` 在 `-p` 模式不展開。我們試過。
- **不能用 `/skill` 語法** — 前面說了，會卡住。
- **要寫完整指令** — `-p` 模式下 Claude 看不到 SKILL.md 的內容，它只有你給的 prompt。

### 執行鏈

```
launchd（macOS 排程）
  → cron_runner.sh（我們的 wrapper）
    → 設好環境變數（PATH, USER, SHELL）
    → claude -p "{prompt}" --allowedTools "Bash,Read,Glob,Grep"
    → 拿到分析結果
    → 如有 Telegram config → urllib 推送
    → 寫 log，清理舊 log
```

`--allowedTools` 指定允許的工具，這樣 `-p` 模式下不會卡在權限確認。

---

## 為什麼用 launchd 不用 crontab

我們花了一整個早上才搞懂這個。

**`claude -p` 需要 OAuth token，而 crontab 的 daemon 環境拿不到。**

| 環境 | 有 login session | claude -p |
|------|-----------------|-----------|
| Terminal（手動） | ✅ | ✅ 正常 |
| launchd LaunchAgent | ✅ 跑在使用者 session | ✅ 正常 |
| crontab | ❌ 獨立 daemon context | ❌ `Not logged in` |

crontab 跑的進程完全沒有 GUI session — keychain 打不開、OAuth token 拿不到。`claude -p` 啟動後連上 API 的第一步就失敗，甚至不會輸出 error message（直接卡住或靜默退出）。

macOS 的 LaunchAgent（放在 `~/Library/LaunchAgents/`）跑在使用者的 login session 裡，可以存取 keychain，所以 `claude -p` 能正常認證。

### cron_manager.py 的 sync 機制

`cron_manager.py` 把 config 裡的 job 轉成 launchd plist：

1. 把 cron 表達式解析成 `StartCalendarInterval` dict 陣列
2. 生成 plist 到 `~/Library/LaunchAgents/com.skill-cron.{job_id}.plist`
3. `launchctl load` 載入排程

因為 launchd 的 `StartCalendarInterval` 不支援 cron 的 range 語法（如 `9-12`），manager 會展開成個別的 dict entry。

---

## cron_runner.sh 環境設定

雖然改用 launchd，runner script 還是要設好環境：

### PATH

launchd 的 PATH 也很精簡。你的 `claude` 裝在 `~/.local/bin`。

```bash
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
```

### USER / SHELL

claude CLI 需要這兩個來找到它的設定。

```bash
export USER="${USER:-$(whoami)}"
export SHELL="${SHELL:-/bin/bash}"
```

### Telegram 推送的引號地獄

原本用 `curl` + inline Python 構造 JSON payload，在 shell 的 heredoc 裡嵌 Python，Python 裡面有 shell 變數。三層引號互相打架。

最後放棄 curl，改用純 Python `urllib.request` 一行解決。

---

## 設定檔放哪

`~/.claude/configs/skill-cron.json`

考慮過 `~/.config/skill-cron/`（XDG 標準），但這個 skill 就是 Claude Code 生態系的一部分，放 `~/.claude/` 下更自然。而且這個檔案存了 Telegram bot token，不能被 git 追蹤 — `~/.claude/` 本來就不在任何 repo 裡。

## LaunchAgent 管理

skill-cron 在 `~/Library/LaunchAgents/` 下管理以 `com.skill-cron.` 為前綴的 plist 檔案。`sync` 時會先 unload + 刪除所有舊的，再重新建立 + load。

## 日誌

`~/.claude/logs/skill-cron/{job_id}-{timestamp}.log`

每個 job 留最近 50 筆。debug 的時候第一件事就是 `cat` 最新的 log。

## 支援 skill-cron 的 skill

| Skill | 做什麼 | 建議排程 |
|-------|--------|---------|
| [banini](../banini/) | 冥燈追蹤 | 盤中 `平日 9:07-13:07 每 30 分`、盤後 `每天 23:03` |

想讓你的 skill 也支援排程？在 SKILL.md frontmatter 加 `headless-prompt` 就好。一行。

## 限制

1. **macOS only** — 用的是 launchd LaunchAgent，Linux 需要改用 systemd timer 或其他方案
2. **Mac 要登入** — LaunchAgent 只在使用者登入時執行。關機、登出就不會跑
3. **Claude Max 訂閱** — `claude -p` 需要有效的 OAuth 登入狀態。token 過期了要重新 `claude login`
4. **Telegram 4096 字元** — 超長報告會被截斷。但說真的，你不需要在手機上看一萬字的分析報告
5. **`--allowedTools` 白名單** — 排程執行時沒有人可以按「允許」，所以用 `--allowedTools` 預先指定允許的工具
