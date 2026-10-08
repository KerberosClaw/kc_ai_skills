---
name: ios-resign
description: "Use when the user wants to rebuild, re-sign and reinstall one of their own iOS apps onto their iPhone(s) — typically because a free Apple ID provisioning profile expired after 7 days and the app now crashes on launch — or wants to set a project up for that (重簽／重新簽／App 過期閃退／重裝到手機／設定重簽). Reads the project's resign.yaml (in version control) plus resign.local.yaml (this Mac's phones), builds with xcodebuild, installs and launches via devicectl, and maps every failure to a fixed exit code with a plain-language next step. Setup mode inspects the Xcode project, drafts both YAML files for the user to confirm, and walks the human-only steps (Apple ID login, trusting the computer, Developer Mode, trusting the developer). NOT for App Store / TestFlight distribution, paid-team ad-hoc signing workflows, or editing app code."
version: 0.1.0
status: mvp
triggers:
  - "/ios-resign"
  - "重簽"
  - "重新簽"
  - "App 過期"
  - "閃退了重裝"
  - "重裝到手機"
  - "設定重簽"
---

# ios-resign — 自己的 iOS App 過期了，重簽裝回手機

You are a careful release helper for one person's own iOS apps. 免費 Apple ID 簽的 App 每 7 天到期，到期後一點就閃退；你的工作是讓「重簽」變成一句話的事，而且**任何一步出錯都講得出白話的下一步**。

**Agent 決定、腳本執行**：找哪個專案、哪個版本、哪幾支手機、要不要先問使用者，是你決定的；編譯、簽章、安裝、讀設定、分類錯誤，一律交給 `scripts/` 裡的腳本。**不要自己組 `xcodebuild` 指令。**

腳本路徑以本 skill 資料夾為準，下文寫成 `<skill>/scripts/...`。

## Step 0：找專案的設定檔

依序試，找到就停：

| 情況 | 怎麼找 |
|---|---|
| 目前資料夾在某個 repo 裡 | 從目前資料夾往上找 `resign.yaml`（腳本預設就這樣找，到 git 根目錄為止） |
| 不在任何專案裡，使用者點名了 App（「重簽 wherebear」） | 照使用者環境提供的專案索引（例如全域 AGENTS.md／CLAUDE.md 指到的清單）查 repo 位置，再用 `--config <repo>/resign.yaml` |
| 都找不到 | **問使用者**專案在哪；不要自己掃整個家目錄 |

有 `resign.yaml` → **重簽模式**。沒有 → 問使用者要不要先跑**設定模式**。

## 重簽模式

### Step R1：確認要簽什麼

先看設定：

```bash
<skill>/scripts/resign.sh --list            # 在專案資料夾裡
<skill>/scripts/resign.sh --list --config <repo>/resign.yaml
```

| 使用者說 | 參數 |
|---|---|
| 只說「重簽」 | 不加：預設版本、本機設定列的全部手機 |
| 點名某支手機（「只簽 11 Pro」） | 把手機名稱或 UDID 放在最後，可列多支。對照 `--list` 的手機名稱；使用者的叫法對不上就問 |
| 要開發版／某個版本 | `--variant <版本名>` |
| 只想確認編得過、不碰手機 | `--build-only` |

提醒使用者：**要裝的 iPhone 插上傳輸線（或跟電腦連同一個 Wi-Fi）、解鎖、螢幕保持亮著。**

### Step R2：執行

```bash
<skill>/scripts/resign.sh [--config <repo>/resign.yaml] [--variant <版本>] [手機名稱 ...]
```

- 一支手機約 3～5 分鐘，**逾時至少設 15 分鐘**。
- **CRITICAL**：腳本要連 Apple 的簽章伺服器、要碰手機、要寫 `~/Library/Caches`。在有沙箱的 agent（例如 Codex）裡**要在沙箱外執行**（要求提升權限，或由使用者在規則裡放行這支腳本）；沙箱裡跑一定失敗，而且錯誤看起來像簽章問題。

### Step R3：看結果

腳本逐支手機處理，每支各印一行 `✔ [手機名] …` 或 `✖ [手機名] …`；失敗的那支會再印 `RESIGN_EXIT=<碼> DEVICE=<名稱>`，設定層的錯誤只印 `RESIGN_EXIT=<碼>`。

| 碼 | 意思 | 請使用者做什麼 |
|---|---|---|
| 0 | 全部完成 | 跟使用者說「好了，App 可以用了」。不用主動提到期日或約下次 |
| 31 | **部署成功**，要在手機上信任開發者（第一次、或 App 被刪光後重裝） | 把腳本印的設定路徑原樣告訴他，信任完直接點 App，**不用重跑**。按信任一直轉圈是手機連不到 Apple 驗證：確認有網路、關掉 VPN 再按 |
| 32 | **部署成功**，手機鎖著沒自動打開 | 解鎖後直接點 App；跳「未受信任的開發者」就照 31 |
| 13 | 手機連不到或沒配對 | 插線、解鎖；第一次接這台電腦要在手機按「信任」並輸入手機密碼 |
| 14 | 手機沒開開發者模式 | 手機「設定 › 隱私權與安全性 › 開發者模式」打開，照指示重開機 |
| 16 | 點名的手機不在設定裡 | 錯誤訊息列了可用名稱，改用正確名稱重跑；真的是新手機就走設定模式加進 `resign.local.yaml` |
| 17 | 手機上的自簽 App 已滿 3 個（免費帳號上限） | 把腳本列出的 App 念給使用者，**問他要刪哪個**，他在手機上刪掉後重跑。確定其中有付費團隊簽的才加 `--allow-over-limit` |
| 20 | 編譯或簽章失敗 | 看下方「碼 20 細分」 |
| 30 | 安裝失敗 | 解鎖、保持亮著再試一次；再失敗就問使用者能不能先刪掉手機上的這個 App（**會清掉 App 資料，刪光後重裝也要重新信任**） |
| 33 | 已安裝但打不開，原因不明 | 先請他直接點 App 看看；打不開就回報錯誤摘要 |
| 10 | 設定檔有問題 | 照錯誤訊息修 YAML（缺欄位、bundle ID 跟專案對不上、沒列手機…） |
| 11 | Xcode 沒裝好或太舊 | 見設定模式的「人要做的事」 |
| 12 | 建置前指令失敗 | 那是專案自己的前置步驟（例如編原生函式庫），看它的輸出；修不了就回報 |
| 15 | Xcode 沒登入該團隊的 Apple ID，或團隊不是免費個人團隊 | 登入要人在 Xcode 畫面做；**不要自己改 `team`**，換團隊要使用者決定 |
| 18 | 找不到 `/usr/bin/ruby` | 讀 YAML 要用 macOS 內建 Ruby；回報使用者 |

**同一支手機、同一個錯誤重試兩次還不行就停**，把錯誤碼、`✖` 那行、錯誤摘要與紀錄路徑（`~/Library/Caches/ios-resign/<repo>-<版本>/build-<手機>.log`）整理給使用者。一支成功、另一支碼 13 沒接上：先報成功的那支，再問另一支要不要現在接上。

#### 碼 20 細分（看腳本印的錯誤摘要）

- `maximum number of apps`：同碼 17，手機自簽 App 已滿
- `No Account`、`sign in`：Xcode 的 Apple ID 登出或過期 → 人在 Xcode › Settings › Accounts 重新登入
- `No profiles`：通常是手機還沒登記到描述檔；確認手機有接上、重跑一次（腳本會自動登記）
- `locked`：手機鎖著
- 其他：回報

## 設定模式

第一次替某個專案（或某台電腦）設定。**寫入任何檔案前都要使用者確認。**

### Step S1：偵察

```bash
<skill>/scripts/inspect.sh                          # 在 repo 根目錄：列 .xcodeproj、Xcode 團隊、配對過的 iPhone
<skill>/scripts/inspect.sh <路徑/App.xcodeproj>      # 再列每個會產出 App 的 scheme 與 bundle ID／團隊／configuration
```

### Step S2：人要做的事（偵察結果缺什麼就帶他做什麼）

| 缺什麼 | 誰做 | 怎麼帶 |
|---|---|---|
| Xcode 沒裝或版本低於專案最低 iOS | 人 | App Store 或 Apple Developer 下載；版本要對得上手機的 iOS |
| `xcodebuild` 跑不起來 | 人（要 sudo 密碼） | 給他兩行：`sudo xcodebuild -license accept`、`sudo xcodebuild -runFirstLaunch` |
| 「Xcode 登入的團隊」是空的 | 人（雙重認證） | Xcode › Settings › Accounts › 左下「+」› Apple ID 登入 |
| 想裝的手機不在「配對過的 iPhone」 | 人 | 插線、解鎖，手機按「信任這部電腦」並輸入手機密碼 |
| 開發者模式沒開 | 人 | 手機「設定 › 隱私權與安全性 › 開發者模式」，打開後重開機 |
| 第一次裝完打不開（碼 31） | 人 | 手機「設定 › 一般 › VPN 與裝置管理」信任開發者 |

### Step S3：起草設定，給使用者確認

照偵察結果起草兩個檔（格式見下節），**整份貼給使用者看**，問三件事：要列哪些版本、預設哪個版本、這台電腦要裝哪幾支手機。專案特有、偵察看不出來的前置步驟（例如要先編原生函式庫）要**問使用者**，不要猜。

- 列進來的版本，`scheme`、`bundle_id`、`configuration` **照偵察結果抄**，不要自己推。
- `team` 用偵察列出的**免費個人團隊**；只有付費團隊時告訴使用者這個 skill 預設只用個人團隊，他確定要用付費團隊才加 `allow_paid_team: "true"`。
- 免費帳號一支手機最多 3 個自簽 App；版本選多了（例如正式版和開發版都要）先提醒會佔名額。

### Step S4：寫入

1. 使用者確認後，寫 `resign.yaml` 與 `resign.local.yaml` 到 **repo 根目錄**（同一個資料夾）。
2. 確認 `.gitignore` 有 `resign.local.yaml`，沒有就加。
3. 跑一次 `resign.sh --list` 與 `resign.sh --build-only` 確認讀得到、編得過。
4. `resign.yaml` 照該 repo 的規則 commit；`resign.local.yaml` **不進版控**。
5. 使用者環境有專案索引（Step 0 那份清單）時，告訴使用者要補這一列，或照他環境的規則幫他補。

## 設定檔格式

所有值一律當字串讀（不會把 `1.10` 變成 `1.1`）。`resign.local.yaml` 逐層蓋過 `resign.yaml`，清單整個取代。

**`resign.yaml`（進版控，不管在哪台電腦都一樣）**

```yaml
# ios-resign 專案設定。手機寫在 resign.local.yaml（不進版控）
name: 熊熊在哪裡                         # 顯示用
project: app/MyApp/MyApp.xcodeproj       # 相對於本檔所在資料夾
team: ABCDE12345                         # 免費個人團隊 ID
default_variant: prod
prebuild: scripts/ensure-native.sh       # 選填：建置前在 repo 根目錄執行，失敗＝碼 12
variants:
  prod:
    label: 正式版                         # 選填
    scheme: MyApp
    bundle_id: com.example.myapp
    configuration: Debug                  # 選填，預設 Debug；照偵察結果填
  dev:
    label: 開發版
    scheme: MyApp-dev
    bundle_id: com.example.myapp.dev
    configuration: Debug-Dev
```

**`resign.local.yaml`（不進版控，這台電腦專屬）**

```yaml
devices:
  - name: 我的 iPhone                     # 跟 devicectl 顯示的名稱一樣，點名時用這個
    udid: 00008150-000000000000001C
# 選填：分享出去的專案，各自用自己的團隊與 bundle ID（不改專案檔，拉新版不衝突）
# team: XYZ9876543
# variants:
#   prod:
#     bundle_id: com.yourname.myapp
```

| 欄位 | 位置 | 必填 | 說明 |
|---|---|---|---|
| `project` | resign.yaml | ✅ | Xcode 專案路徑 |
| `team` | 任一 | ✅ | 簽章團隊；預設只准免費個人團隊 |
| `variants.<名>.scheme`／`bundle_id` | resign.yaml | ✅ | `bundle_id` 要跟專案實際的一致；本機設定改了才會從命令列覆蓋 |
| `variants.<名>.configuration` | resign.yaml | | 預設 `Debug` |
| `default_variant` | 任一 | 多版本時 ✅ | |
| `prebuild` | resign.yaml | | 專案自己的前置步驟 |
| `devices` | **只能**在 resign.local.yaml | 要裝手機時 ✅ | 寫在 resign.yaml 會被拒絕 |
| `allow_paid_team` | 任一 | | `"true"` 才准付費團隊 |

## Anti-patterns

- ❌ 自己組 `xcodebuild`／`devicectl` 指令取代腳本——錯誤分類與團隊防呆都會不見
- ❌ 在沙箱裡跑腳本，失敗了再當簽章問題排查
- ❌ 自己改 `team`、加 `allow_paid_team`、加 `--allow-over-limit`——這些都是使用者的決定
- ❌ 碼 31／32 當成失敗重跑——那是部署成功、只差使用者在手機上動手
- ❌ 碼 17 時自己決定刪哪個 App，或叫使用者「隨便刪一個」
- ❌ 設定模式沒給使用者看就寫檔，或把手機寫進 `resign.yaml`
- ❌ 找不到專案就掃整個家目錄
- ❌ 成功後主動約「X 月 X 日再來重簽」——閃退了再叫你就好

## Important rules

1. **編譯、簽章、安裝一律走 `scripts/resign.sh`**，判斷交給你，執行交給腳本
2. **要在沙箱外執行**（連網、碰手機、寫快取）
3. 照結束碼對照表處理；**31、32 是成功**
4. **團隊、付費團隊、App 名額上限都是使用者的決定**，不要替他改
5. 設定模式**寫檔前先給使用者確認**；手機只進 `resign.local.yaml`，它不進版控
6. 同一個錯誤重試兩次還不行就停，整理錯誤碼與紀錄路徑回報
7. 找不到專案就問，不要掃
