# 動態測試工作流程規範

> 從實戰中反覆糾正後歸納的流程。每一條都是踩過坑才加上的。
>
> 本檔的「安全邊界」與「提方案前的 checklist」是唯一版本，`SKILL.md` 只指過來、不另抄一份。要改清單就改這裡。

---

## 測試前環境清理（每次必做）

在每次動態測試前，必須完成以下步驟：

```powershell
# 1. 殺殘留進程
taskkill /F /IM target.exe

# 2. 確認無殘留 TCP 連線（TIME_WAIT 可忽略）
netstat -an | findstr <PORT>

# 3. 清除配置檔（如有）
del /f C:\path\to\config.ini
```

三項全部完成才能告訴使用者「環境已清理，可以開程式」。

---

## Frida Attach 時機

```
正確流程：
1. 使用者開程式
2. 登入視窗出現
3. 使用者不按登入
4. 使用者說「開了」
5. tasklist 找 PID
6. frida -p <PID> -l script.js
7. 使用者操作（按登入等）

錯誤流程（會被 VMP 偵測）：
- 認證過程中 attach Frida
- 程式啟動前就 spawn（某些 VMP 版本偵測）
- 自動輪詢 attach（等使用者說才動手）
```

**找 PID 用 `tasklist`，不用 `EnumWindows`。** 管理員權限的程式視窗在一般權限下 EnumWindows 看不到。

---

## 腳本設計原則

### 輸出方式

```python
# ✅ 正確：腳本內部用 Python open() 寫檔
with open("output.txt", "w") as f:
    f.write(result)

# ❌ 錯誤：依賴 shell redirect
# python script.py > output.txt  ← 背景模式可能覆蓋或丟失

# ❌ 錯誤：依賴 && cat
# python script.py && cat output.txt  ← 多餘
```

### Frida 腳本輸出

```javascript
// ✅ 正確：用 Frida 的 File API 直接寫檔
var f = new File("C:\\CTF\\trace.log", "w");
f.write(data);
f.flush();

// ❌ 錯誤：用 send() 傳大量資料回 Python
// send(hugeBuffer);  ← 資料量大時會丟失或超時
```

### 錯誤處理

```javascript
// ✅ 正確：失敗的 region 跳過，不 crash 整個流程
Process.enumerateRanges('rw-').forEach(function(range) {
    try {
        // ... 操作
    } catch(e) {
        // 跳過這個 range，繼續下一個
    }
});

// ❌ 錯誤：一個 exception 炸掉整個腳本
```

---

## 執行方式

```bash
# 標準執行
python script.py <PID>
# timeout 設 180 秒（認證流程可能要等 server 回應）

# 跑完後讀取結果
# 用 Read 工具讀 output.txt，不要 cat
```

---

## 安全邊界

### 只在 VM 裡做的事

- Debugger attach（x32dbg、自製 debugger）
- 記憶體注入（WriteProcessMemory、VirtualAllocEx）
- 任何可能觸發反除錯的操作（VMP 或其他保護殼）
- 未知行為的程式首次執行
- Raw socket capture

### 可以在 Host 上做的事

- Frida attach（小心時機）
- `netstat` 觀察連線
- `tasklist` 找 PID
- 讀取配置檔
- 靜態分析（Python PE parser、strings）

### 絕對不做的事

- 在 host 上做 raw socket capture（曾導致系統 hang → 系統還原）
- 認證過程中 attach 工具（VMP 偵測）
- 顯示程式的隱藏視窗（VMP 退出機制）
- 自動輪詢 attach（等使用者指示）

---

## 靜態分析優先

在跑任何動態測試之前：

1. 用 Ghidra / Python 靜態分析完所有 CALL 鏈
2. 不要每發現一個函數就停下來跑測試
3. 一次看完所有需要分析的部分
4. 規劃好所有要驗證的假設
5. 一次 attach 驗證多個假設

**為什麼：** 每次動態測試需要使用者配合（開程式、attach、操作 UI），來回一次 10-15 分鐘。如果靜態能確認的事情就不要浪費動態測試的機會。

---

## 提方案前的 checklist

```
□ 讀過 failed_methods 了嗎？新方案跟已失敗方法有無相似？
□ 方案的先決條件都滿足嗎？（不需要真 key？不需要 server 在線？）
□ 方案達成了目標嗎？（bypass ≠ 用真 key 登入）
□ 不確定的部分有查過資料嗎？
□ 明確區分了「已驗證事實」和「未驗證假設」嗎？
□ 有具體的驗證步驟嗎？（不是「試試看」）
```
