---
name: repo-scan
description: "GitHub 開源專案安全掃描工具。輸入 GitHub repo URL，輸出專案概覽、靜態弱點分析、供應鏈風險、Issues 安全回報、維護者評估與風險總結。適用於安裝前的安全評估。"
version: 1.0.0
---

# Repo Scan — GitHub 開源專案安全掃描

## 使用方式

```
/repo-scan https://github.com/owner/repo
```

參數：
- **GitHub repo URL**（必要）— 支援含 query string 的 URL（自動清除 `?fbclid=` 等追蹤參數）

---

## 執行規則

1. **GitHub repo URL** 為必要參數。如果使用者沒有提供，直接詢問，不要猜測。
2. URL 清理：移除 `?fbclid=`、`?ref=` 等追蹤參數，保留 `https://github.com/owner/repo` 格式。
3. 前置檢查通過後才開始掃描流程。
4. 掃描完成後清理：刪除 clone 到 `/tmp/` 的 repo。

---

## 前置檢查

掃描前依序確認：

```bash
# 1. git 是否可用
git --version

# 2. gh 是否可用且已登入
gh auth status
```

- `git` 不可用 → 停止，提示安裝
- `gh` 不可用或未登入 → 警告，跳過 Phase 5（Issues 掃描），其餘照跑

---

## 掃描流程

### Phase 1：專案概覽

Clone repo 到 `/tmp/repo-scan-{repo_name}`（shallow clone 節省時間）：

```bash
git clone --depth 50 {repo_url} /tmp/repo-scan-{repo_name}
```

分析並整理：

| 項目 | 內容 |
|------|------|
| 專案名稱 | |
| 用途說明 | 一句話描述這個專案做什麼 |
| 主要語言 | |
| 關鍵檔案 | 列出核心檔案及其功能 |
| 執行方式 | 如何安裝/使用（從 README 或程式碼判斷）|
| Stars / Forks | |
| License | |
| 最後 commit | 日期 + 內容摘要 |

**重點：用最少的字讓人搞懂這個 repo 在幹嘛。**

---

### Phase 2：依賴分析

掃描以下檔案（存在才掃）：

- `package.json` / `package-lock.json`（Node.js）
- `requirements.txt` / `setup.py` / `pyproject.toml`（Python）
- `go.mod`（Go）
- `Cargo.toml`（Rust）
- `Gemfile`（Ruby）
- `pom.xml` / `build.gradle`（Java）
- `composer.json`（PHP）

檢查項目：
- [ ] 是否有已知高風險套件（如 `event-stream`、`ua-parser-js` 等曾被投毒的套件）
- [ ] 依賴數量是否合理（一個小工具拉了 200 個套件？）
- [ ] 是否有 `postinstall`、`preinstall` hook（package.json scripts）
- [ ] 是否鎖定版本（有無 lock file）
- [ ] 依賴是否仍在維護（看最後更新時間）
- [ ] 是否有 native binary 依賴（如 `sharp`、`node-gyp` 等，增加攻擊面）

---

### Phase 3：靜態弱點掃描

逐一讀取所有原始碼檔案，檢查以下類別：

#### 3.1 命令注入（Command Injection）
- `exec()`、`execSync()`、`spawn()` 使用未過濾的外部輸入
- `os.system()`、`subprocess.call()` 拼接字串
- `` `backtick` `` 或 `$()` 內含變數
- `eval()` 動態執行

#### 3.2 路徑穿越（Path Traversal）
- 使用者輸入直接拼接檔案路徑（無 `path.resolve` 或 sanitize）
- `../` 未被過濾

#### 3.3 硬編碼機密（Hardcoded Secrets）
- API key、token、password 寫死在程式碼中
- `.env` 檔案被追蹤到 git

#### 3.4 不安全的反序列化
- Python: `pickle.load()`、`yaml.load()`（無 `Loader=SafeLoader`）
- Node.js: `JSON.parse()` 後直接信任內容
- Java: `ObjectInputStream`

#### 3.5 XSS / 注入
- HTML 模板中直接插入未跳脫的變數
- `innerHTML`、`dangerouslySetInnerHTML`
- SQL 拼接字串

#### 3.6 不安全的加密
- MD5、SHA1 用於安全用途（密碼、token）
- 硬編碼 key / IV
- `Math.random()` 用於安全用途

#### 3.7 不安全的網路行為
- HTTP（非 HTTPS）連線
- 關閉 TLS 驗證（`rejectUnauthorized: false`、`verify=False`）
- CORS 設為 `*`

#### 3.8 檔案系統風險
- `/tmp/` 使用可預測的固定路徑（symlink attack）
- 寫檔無權限檢查
- 世界可讀/寫的檔案權限（`0777`、`0666`）

#### 3.9 資訊洩漏
- 錯誤訊息暴露內部路徑或 stack trace
- Debug 模式預設開啟
- 敏感資料寫入 log

---

### Phase 4：安裝腳本與供應鏈風險

重點審查以下檔案（如果存在）：

- `install.sh` / `setup.sh` / `bootstrap.sh`
- `Makefile` 的 install target
- `Dockerfile` / `docker-compose.yml`
- GitHub Actions workflow（`.github/workflows/`）
- `package.json` 的 `scripts` 欄位（`postinstall`、`preinstall`、`prepare`）

檢查項目：
- [ ] 是否有 `curl | bash` 或 `wget | sh` 模式
- [ ] 是否下載並執行外部腳本
- [ ] 是否修改系統層級設定（`/etc/`、crontab、PATH）
- [ ] 是否請求不必要的權限（sudo）
- [ ] 是否有 obfuscated code（base64 編碼的指令、壓縮過的 script）
- [ ] 是否有可疑的 outbound 網路連線（telemetry、data exfiltration）
- [ ] 安裝時是否覆蓋現有檔案而不確認

---

### Phase 5：Issues 安全回報掃描

> 需要 `gh` CLI。無法使用時跳過此階段並註明。

```bash
# 抓所有 issues（open + closed）
gh issue list -R {owner}/{repo} --state all --limit 200

# 用關鍵字篩選安全相關 issues
gh issue list -R {owner}/{repo} --state all --search "vulnerability OR security OR CVE OR injection OR XSS OR RCE OR exploit OR malicious OR unsafe OR leak OR bypass OR SSRF OR traversal"
```

對每個命中的 issue：
```bash
gh issue view {issue_number} -R {owner}/{repo}
```

分析：
- [ ] 是否有未修復的安全漏洞（open 的安全 issue）
- [ ] 已修復的漏洞嚴重程度如何
- [ ] 維護者對安全回報的回應速度（< 7 天 = 好，> 30 天 = 差）
- [ ] 是否有 SECURITY.md 或 security policy

整理成表格：

| Issue # | 標題 | 狀態 | 嚴重程度 | 回應時間 |
|---------|------|------|---------|---------|

---

### Phase 6：維護者與專案健康度

```bash
# Repo 基本資訊
gh repo view {owner}/{repo} --json stargazerCount,forkCount,createdAt,updatedAt,licenseInfo,description

# 最近 commit 活動
git log --oneline -20

# Contributors
gh api repos/{owner}/{repo}/contributors --jq '.[].login' | head -10
```

評估項目：
- [ ] 最後 commit 距今多久（> 6 個月 = 警告，> 1 年 = 高風險）
- [ ] Contributors 數量（1 人 = bus factor 風險）
- [ ] 是否有 CI/CD（`.github/workflows/`）
- [ ] 是否有測試（`test/`、`tests/`、`__tests__/`、`*_test.go`）
- [ ] 是否有 code review 文化（PR merge 還是直接 push main）
- [ ] License 是否明確

---

## 輸出格式

掃描完成後，輸出以下格式的報告：

```
## Repo Scan 報告：{repo_name}

### 專案概覽
（Phase 1 的表格）

### 依賴分析
（Phase 2 的發現，列出可疑依賴）

### 靜態弱點
（Phase 3 的發現，依嚴重程度排序）

每個弱點格式：
#### 弱點 N：{類別} — `{file}:{line}`
- **嚴重程度**：High / Medium / Low
- **說明**：具體描述問題
- **利用場景**：攻擊者如何利用
- **建議**：如何修復

### 供應鏈風險
（Phase 4 的發現）

### Issues 安全回報
（Phase 5 的表格 + 分析）
（如跳過，註明「gh CLI 不可用，已跳過」）

### 專案健康度
（Phase 6 的評估）

---

### 風險總結

| 維度 | 風險等級 | 說明 |
|------|---------|------|
| 程式碼安全 | High/Medium/Low/None | |
| 依賴風險 | High/Medium/Low/None | |
| 供應鏈風險 | High/Medium/Low/None | |
| 已知漏洞 | High/Medium/Low/None | |
| 維護狀態 | High/Medium/Low/None | |
| **整體風險** | **X** | |

### 結論

是否建議安裝/使用？（明確回答）
- 已知風險摘要（最多 3 點）
- 使用時的注意事項（如果建議使用）
```

---

## 嚴重程度定義

- **High**：可直接利用，導致 RCE、資料外洩、權限提升
- **Medium**：需特定條件才能利用，但影響範圍大
- **Low**：防禦縱深問題，或影響範圍小

---

## 注意事項

- 只報告有實際風險的發現，不報理論性問題
- 信心不足 70% 的發現不列入報告
- 每個發現都要附具體檔案和行號
- 報告以繁體中文輸出
- 掃描完成後刪除 `/tmp/` 下的 clone
- 此為靜態分析，不執行任何程式碼
