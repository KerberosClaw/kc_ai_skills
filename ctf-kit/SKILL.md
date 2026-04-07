---
name: ctf-kit
description: "CTF 逆向工程解題工具箱 — 聚焦 Windows 應用程式驗證繞過。從開題偵察到 bypass 驗證的完整流程引導，內建實戰踩坑經驗。"
version: 0.3.0
triggers: ["ctf", "reverse", "bypass", "crack", "逆向", "繞過驗證", "破解"]
license: MIT
compatibility: "Requires filesystem-based agent (Claude Code or similar) with bash, Python 3. Windows dynamic analysis environment (physical or VM) recommended."
allowed-tools: Bash Read Write Edit Glob Grep Task WebFetch WebSearch Skill
metadata:
  user-invocable: "true"
  argument-hint: "[challenge-file] [phase]"
---

# /ctf-kit — CTF Reverse Engineering Toolkit

Windows 應用程式驗證繞過的實戰 playbook。
適用於各種保護殼（VMP、Themida、自製殼等）和驗證方式（網路驗證、本地驗證、混合驗證）。

## 適用範圍

本 skill 適用於：
- Windows PE 執行檔的授權/認證繞過
- 各種保護殼（VMProtect、Themida、UPX、自製殼）
- 網路驗證、本地驗證、時間驗證
- 紅隊演練中的軟體授權 bypass

**不適用時的導向：**

本 skill 聚焦 Windows 驗證繞過。超出範圍的題目，建議使用 [ljagiello/ctf-skills](https://github.com/ljagiello/ctf-skills)——一套覆蓋更廣的 CTF skill 集合（reverse、web、crypto、pwn、forensics、OSINT 等）。

| 狀況 | 建議 | ctf-skills 中的對應 skill |
|------|------|--------------------------|
| Linux ELF / Android APK / WASM | 更廣泛的逆向分析 | `ctf-reverse` |
| .NET 程式 | dnSpy 反編譯為主 | `ctf-reverse` |
| 純 flag checker（無網路、無殼）| angr / symbolic execution | `ctf-reverse` |
| Web 應用 | XSS、SQLi、SSTI 等 | `ctf-web` |
| 不確定分類 | 先做 triage 再分流 | `solve-challenge` |
| Crypto / Pwn / Forensics | 本 skill 不覆蓋 | `ctf-crypto` / `ctf-pwn` / `ctf-forensics` |

如果你的環境已安裝 ctf-skills，可以直接用 `/ctf-reverse`、`/solve-challenge` 等指令。
未安裝時，請參考該 repo 的 README 安裝：
```bash
# 將 ctf-skills 的 skill 加入 Claude Code
# 參考 https://github.com/ljagiello/ctf-skills 的安裝說明
```

## 使用方式

```
/ctf-kit challenge.exe        # 開題：從 Phase 0 開始
/ctf-kit                      # 繼續上次進度
/ctf-kit recon                # 跳到偵察階段
/ctf-kit bypass               # 跳到繞過階段
```

---

## 第一部分：處理準則

> 這些準則適用於所有 Windows 驗證繞過場景，不限於特定保護殼。
> 技術會因目標不同而變，但思維方式不會。

### 準則 1：對齊目標，反覆確認

拿到題目後第一件事不是分析 binary，而是**搞清楚目標是什麼**。

```
□ 目標是什麼？（找 flag？bypass 認證進主畫面？取得特定資料？）
□ 目標「不是」什麼？（不要搜 flag 如果目標是 bypass；不要提議用真 key 如果目標是繞過驗證）
□ 有時效性限制嗎？（server 在線時間、key 有效期）
```

每提出一個方案前，問自己：「這個方案達成了目標嗎？」

### 準則 2：先驗證再行動，不猜測

**不要說「可能是」「也許因為」然後就開始動手。**

```
錯誤流程：觀察現象 → 猜測原因 → 嘗試修復 → 失敗 → 猜另一個原因
正確流程：觀察現象 → 設計最小驗證實驗 → 取得資料 → 基於資料決策
```

- 假設不確定時，先**上網搜尋**有沒有相關文獻或已知案例
- 用最小代價驗證（讀 dump、一行 trace、查文檔），不要寫 200 行腳本去驗證一個假設
- 對使用者說話時明確區分「已驗證事實」和「未驗證假設」
- 工具用法不確定時**先查文檔**，不要亂試

### 準則 3：不重複已失敗的方法

**每次提出方案前，必須先檢查失敗記錄。**

如果專案有 `failed_methods` 記錄，提方案前必須讀取並對照。如果新方案跟任何已失敗方法有相似邏輯，必須明確指出差異在哪裡，為什麼這次會不同。

參見 [docs/failure-patterns.md](docs/failure-patterns.md) 了解常見失敗模式。

### 準則 4：靜態分析做到底，動態測試要批量

```
錯誤流程：靜態看一點 → 跑動態 → 發現不夠 → 回靜態 → 再跑動態（反覆 10 次）
正確流程：靜態分析做到沒東西可挖 → 一次規劃所有動態實驗 → 批量執行
```

動態測試消耗資源（時間、key、server 額度、使用者操作），靜態分析不消耗。每次動態測試都需要使用者配合，來回一次 10-15 分鐘。

### 準則 5：追蹤完整呼叫鏈，不只看一層

分析函數依賴時，**必須遞迴追蹤每個呼叫目標的完整呼叫鏈**。一個函數看起來「參數齊全可 stub」，但它內部可能回呼其他受保護的函數。

### 準則 6：保護環境，高風險操作在 VM 做

```
⚠️ 不在 host 上做的事：
- Raw socket capture（可能 hang 整個系統）
- 認證過程中 attach debugger
- 任何可能觸發反除錯的操作
- 未知行為的程式首次執行

✅ 只在 VM 裡做的事：
- Debugger attach、記憶體注入
- 可能觸發反調試的操作
```

### 準則 7：卡關時的決策流程

```
卡住了？
│
├─ 1. 停下來，不要繼續同方向硬撞（一個方法最多試 3 個變體）
│
├─ 2. 查 failure-patterns.md — 是不是踩了已知的坑？
│
├─ 3. 上網搜尋 — 有沒有類似保護殼/驗證系統的公開破解案例？
│     └─ "[殼名稱] bypass/crack/keygen"
│     └─ 中文論壇：吾爱破解、看雪、52pojie
│     └─ GitHub：殼名稱 + "unpack/devirtualize"
│
├─ 4. 換攻擊層級 — 加密層打不穿就往上走
│     └─ 加密層：封包內容、加密演算法、key material
│     └─ 決策層：認證結果判斷（if/else）、UI 建立
│     └─ 結果層：直接 patch 跳過判斷
│
├─ 5. 換工具 — 工具不是目的，解題才是
│
└─ 6. 15 分鐘沒進展就停 — 回到步驟 2
```

### 準則 8：提方案前的 checklist

```
□ 讀過失敗記錄了嗎？新方案跟已失敗方法有無相似？
□ 方案的先決條件都滿足嗎？（不需要真 key？不需要 server 在線？）
□ 方案達成了目標嗎？
□ 不確定的部分有查過資料嗎？
□ 有具體的驗證步驟嗎？（不是「試試看」）
```

---

## 第二部分：執行流程

### Phase 0：環境確認

```
□ 目標 binary 在哪裡？目標是什麼？
□ 靜態分析和動態測試是同一台機器嗎？
□ 動態環境：Windows？管理員權限？VM 還是 host？
□ 有 Python？有 Frida？
□ 題目有提示嗎？有時效性資源嗎？
□ 有沒有已經做過的分析？
□ 專案目錄有 CLAUDE.md 嗎？（沒有就建立，見下方）
```

**專案初始化：CLAUDE.md**

進入專案時，如果專案目錄沒有 `CLAUDE.md`，**必須立即建立**，內容至少包含：

```markdown
## 記憶管理

專案記憶存放在本專案資料夾的 ./memory/ 中，請從該資料夾讀寫記憶，不要使用預設的 ~/.claude/projects/ 路徑。

## 工作目錄

所有操作產出（script、測試、工具、文件等）一律放在 `./workspace/` 資料夾中。包含但不限於：.py, .txt, .bin, .sh, .c, .exe, .md 等。

**例外**：
- `CLAUDE.md` — 放專案根目錄
- `memory/` — 放專案根目錄
```

同時建立 `memory/` 和 `workspace/` 資料夾。如果已有 `CLAUDE.md`，檢查是否包含上述兩條規則，缺少就補上。

---

### Phase 1：開題偵察（靜態）

> 目標：不執行程式，盡可能了解一切。

**1.1 基本資訊**

用 [scripts/pe_info.py](scripts/pe_info.py) 解析（不依賴外部套件）：
```bash
python pe_info.py target.exe                     # 基本分析
python pe_info.py target.exe --strings           # 加字串搜尋（IP、URL、配置檔等）
python pe_info.py target.exe --gbk "任意中文"     # 搜尋 GBK 編碼的中文字串
python pe_info.py target.exe --json              # JSON 輸出（給其他腳本接力）
```

輸出包含：Architecture、ImageBase、Entry Point、ASLR/DEP、Manifest、
Section 列表 + entropy + 保護殼判斷、Import 分析 + 攻擊面提示。

`--gbk` 用來搜尋簡體中文程式裡的任意關鍵字（驗證訊息、錯誤提示、功能名稱等），
幫助定位認證邏輯在 binary 中的位置。

**1.2 Section 分析**

列出所有 section：名稱、VA、大小、entropy。

| 特徵 | 判斷 |
|------|------|
| `.vmp` `.svmp` + entropy ~8.0 | VMProtect → 見 [docs/vmp-guide.md](docs/vmp-guide.md) |
| `.upx0` `.upx1` | UPX → `upx -d` 脫殼 → 重新分析 |
| `.themida` | Themida/WinLicense |
| `.text` RawSize = 0 | 殼搬移了程式碼 |
| Entry Point 不在 .text | 殼的 loader 先跑 |
| .rdata 裡有 MZ header | 內嵌 payload |

**1.3 Import 分析**

| Import | 意義 | 攻擊面 |
|--------|------|--------|
| WS2_32.dll (send/recv/connect) | 網路驗證 | hook connect 找 server |
| lstrcmpA / CompareStringA | 本地字串比對 | hook 看比較內容 |
| GetProcAddress | 動態解析 | 需要 runtime hook |
| CryptDecrypt / BCrypt* | 加密 | hook 看明文 |
| MessageBoxA/W | 錯誤訊息 | hook backtrace 找決策點 |
| CreateWindowExA/W | 建立視窗 | **最重要** — 主視窗建立 = bypass 成功 |

**1.4 字串搜尋**

搜尋：驗證結果字串、IP/domain/URL、配置檔路徑、Window class/title、保護殼特徵。

中文程式依 locale 可能用 GBK（簡體）或 Big5（繁體）編碼：
```bash
python pe_info.py target.exe --gbk "关键字"     # 簡體
python pe_info.py target.exe --big5 "關鍵字"    # 繁體
```
不確定編碼時三種都搜（見速查表）。

**1.5 識別保護殼和驗證框架 → 立刻上網搜尋**

```
搜尋策略：
1. "[殼名稱] bypass/crack" — 找已知繞過方法
2. "[殼名稱] [版本] unpack" — 找脫殼工具
3. 中文論壇（吾爱破解、看雪、52pojie）— 中文程式的殼通常中文社群有解
4. GitHub "[殼名稱]" — 找自動化工具
5. 商業驗證框架 — 搜尋已知弱點和超級密碼
```

**1.6 路線判斷**

```
保護殼？
├─ UPX → upx -d → 重新分析
├─ VMProtect → 不脫殼，API 邊界攻擊 → 載入 docs/vmp-guide.md
├─ Themida → 搜尋版本對應的脫殼工具，或 API 邊界攻擊
├─ 自製殼 → 分析 loader 邏輯
├─ 無殼 → Ghidra 反編譯
└─ 不確定 → 上網搜尋 section 名稱

驗證類型？
├─ 網路驗證（有 WS2_32）→ 優先攻擊決策層，不攻擊加密層
├─ 本地驗證（有 strcmp 等）→ hook 比較函數
├─ 時間驗證（GetSystemTime / GetLocalTime）→ hook 時間 API
└─ 混合 → 先確認哪個是主驗證

開發框架？
├─ 易語言 (EPL) → MFC 底層，UI 用 Win32 API
├─ .NET → dnSpy，本 skill 不太適用
├─ Delphi → IDR + x32dbg
└─ 標準 C/C++ → Ghidra
```

**產出：** 靜態分析報告 + 判斷路線。跨機器時打包交接包。

---

### Phase 2：動態偵察

> 原則：先輕量觀察，再精準 hook，不要一上來就全面注入。

**2.1 輕量觀察（零工具）**

直接跑一次：看 UI、`netstat -an` 看連線、看配置檔、記錄錯誤訊息。

**2.2 Frida 被動偵察**

```bash
frida -l scripts/recon.js -f challenge.exe          # spawn
frida -l scripts/recon.js -p <PID>                  # attach
frida -l scripts/recon.js -f challenge.exe --no-pause  # spawn + 自動 resume
```

[scripts/recon.js](scripts/recon.js) 預設啟用：Network、CreateWindowEx、MessageBox、Strcmp。
其他模組（Crypto、File、Registry、Time、MemScan）透過腳本開頭的 ENABLE 開關控制。

Hook 目標：
- `connect` → IP:port
- `send`/`recv` → 封包大小、輪數、RetAddr（**不修改內容**）
- `CreateWindowExA/W` → 視窗建立 + **完整 backtrace**（最重要）
- `MessageBoxA/W` → 錯誤訊息 + backtrace
- `lstrcmpA` / `CompareStringA` → 比較內容（本地驗證時）

**Differential trace（跑兩次做 diff）：**
1. 有效輸入 → 記錄 API call 序列
2. 無效輸入 → 記錄 API call 序列
3. diff 兩份結果 → 分歧點就是決策位置

**2.3 如果 Frida 被偵測**

| 順序 | 方法 | 原理 |
|------|------|------|
| 1 | Frida Gadget mode | DLL sideload，繞過 frida-server 偵測 |
| 2 | TitanHide kernel driver | kernel 層隱藏 debug 資訊 |
| 3 | Hook 偵測函數 | 攔截 strstr("frida")、NtQueryInformationProcess |
| 4 | x32dbg + ScyllaHide | 傳統 debugger |
| 5 | 自製 C debugger | 最低調，hardware breakpoint |

**監看數值時優先用 Stalker 而非 INT3 斷點。** Stalker 用 dynamic binary instrumentation（動態改寫 code 到 slab），不插入 0xCC、不設 debug register，比 INT3 更不容易搞掛目標進程。詳見 [docs/tools-quickref.md](docs/tools-quickref.md)。

遇到特定保護殼的反調試問題，見對應指南（如 [docs/vmp-guide.md](docs/vmp-guide.md)）。

---

### Phase 3：繞過

> 原則：從決策層開始，不要從加密層開始。

**路線選擇：**

```
有 CreateWindowExA 的 backtrace？ → 路線 A（最高成功率）
有錯誤訊息的 backtrace？ → 路線 B
有字串比較（strcmp）的 hook 結果？ → 路線 C-local
都沒有？ → 路線 C（搜尋字串交叉引用）
```

**路線 A：從 CreateWindowExA backtrace 找決策點（首選）**

1. 讀取 backtrace return address 附近 ±64 bytes
2. 找條件跳轉（JE/JNE = `74`/`75`/`0F 84`/`0F 85`）
3. `Memory.patchCode` → NOP 或反轉
4. 主視窗出現 = 成功

**路線 B：從錯誤訊息往回追**

1. MessageBox backtrace → 定位錯誤分支
2. 往上找條件跳轉 → 反轉

**路線 C-local：本地驗證 — hook 比較函數**

1. hook lstrcmpA/CompareStringA 看到比較的兩個字串
2. 其中一個是使用者輸入，另一個就是正確密碼
3. 或者直接 patch 比較結果

**路線 C：搜尋字串交叉引用**

1. 記憶體搜尋驗證結果字串（成功/失敗的 GBK bytes）
2. 找誰引用了這個地址 → 認證 handler
3. 在 handler 裡找條件跳轉

**路線 D：網路驗證的協議層攻擊**

⚠️ **只有在加密可破時才值得嘗試。Session-bound 加密直接放棄這條路。**

**路線 E：Binary patch（runtime patch 驗證成功後）**

1. Frida runtime patch 確認可行 → 計算 file offset → Python 修改 binary → 驗證

---

### Phase 4：驗證和記錄

1. 不掛工具跑 patched binary → 確認獨立運作
2. 不同假輸入 → 確認不依賴特定輸入
3. 記錄：改了什麼、為什麼、哪些方法失敗了

---

## 第三部分：速查表

### 條件跳轉 Patch

| 原始 | Patch 後 | 效果 |
|------|---------|------|
| `75 XX` (JNE short) | `74 XX` / `EB XX` / `90 90` | 反轉 / 無條件跳 / 移除 |
| `74 XX` (JE short) | `75 XX` / `EB XX` / `90 90` | 反轉 / 無條件跳 / 移除 |
| `0F 85 XX XX XX XX` (JNE near) | `0F 84` / `E9 XX XX XX XX 90` / `90x6` | 反轉 / 無條件跳 / 移除 |
| `0F 84 XX XX XX XX` (JE near) | `0F 85` / `E9 XX XX XX XX 90` / `90x6` | 反轉 / 無條件跳 / 移除 |

### 函數返回值

| 目的 | Patch |
|------|-------|
| 永遠返回 0 | `33 C0 C3` (xor eax,eax; ret) |
| 永遠返回 1 | `33 C0 40 C3` (xor eax,eax; inc eax; ret) |
| 跳過函數 | `C3` (ret) |

### 檔案偏移計算

```
file_offset = RVA - section_VA + section_file_offset
RVA = runtime_VA - ImageBase
```

### 中文 Hex 轉換

中文程式在 binary 裡的字串編碼取決於開發環境的 locale：
- **GBK**：簡體中文（大陸）
- **Big5**：繁體中文（台灣、香港）
- **UTF-8**：較新的程式或跨平台框架

用 `pe_info.py --gbk` 或 `--big5` 搜尋，或手動轉換：

```python
# Python one-liner：任意中文轉指定編碼的 hex
python3 -c "print(' '.join(f'{b:02X}' for b in '你要搜的字'.encode('gbk')))"
python3 -c "print(' '.join(f'{b:02X}' for b in '你要搜的字'.encode('big5')))"
python3 -c "print(' '.join(f'{b:02X}' for b in '你要搜的字'.encode('utf-8')))"
```

如何判斷目標用哪種編碼：
- 看 PE 的 locale / code page（Ghidra 的 PE header 或 resource section）
- 簡體字（如「验证」「错误」）→ 大概率 GBK
- 繁體字（如「驗證」「錯誤」）→ 大概率 Big5
- 不確定 → 三種都搜一遍，看哪個有 hit

---

## 第四部分：工具清單

### 必備

| 工具 | 用途 | 安裝 |
|------|------|------|
| Frida | 動態 hook、API 攔截、記憶體 patch | `pip install frida-tools` |
| Python 3 | 腳本、PE 分析、binary patch | 內建或下載 |

### 建議

| 工具 | 用途 | 何時需要 |
|------|------|---------|
| Ghidra | 靜態反編譯 | 無殼或脫殼後的深度分析 |
| x32dbg/x64dbg | 傳統 debugger | Frida 被擋時 |
| LIEF | PE 結構修改 | 需要改 PE 結構時 |
| ScyllaHide | x64dbg 反反調試 | 保護殼偵測 debugger 時 |
| TitanHide | Kernel 層反反調試 | 保護殼用 direct syscall 時 |
| dnSpy | .NET 反編譯 | .NET 程式 |
| tshark | 命令行抓包 | 網路驗證協議分析 |

---

## 參考資料

- [docs/failure-patterns.md](docs/failure-patterns.md) — 失敗模式資料庫（泛用 + 保護殼專區）
- [docs/bypass-auth.md](docs/bypass-auth.md) — Frida 腳本範本 + Binary patch 詳細流程
- [docs/vmp-guide.md](docs/vmp-guide.md) — VMProtect 專區（反調試、VMP 特有的陷阱和對策）
- [docs/tools-quickref.md](docs/tools-quickref.md) — Capstone / Unicorn / Frida Stalker 使用速查
- [docs/workflow-rules.md](docs/workflow-rules.md) — 動態測試工作流程規範
- [scripts/recon.js](scripts/recon.js) — Frida 被動偵察腳本（模組化，開關控制）
- [scripts/pe_info.py](scripts/pe_info.py) — PE 靜態分析腳本（純 stdlib，零依賴）

---

## Challenge

$ARGUMENTS
