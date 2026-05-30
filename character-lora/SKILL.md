---
name: character-lora
description: "Use when the user wants to build a consistent-identity LoRA for an original character — defining the character, generating a face/body-consistent multi-angle dataset (via the gpt-image-gen skill for codex image generation), captioning it, doing base-specific homework, training on a chosen base (Pony / Z-Image / others) on a local GPU, and producing a usable LoRA. This skill ORCHESTRATES the end-to-end pipeline and gates every expensive/irreversible step; it delegates actual image generation to gpt-image-gen and never improvises training settings from memory."
version: 0.2.1
triggers: ["/character-lora", "做角色 lora", "訓練角色 lora", "角色 lora 流程", "做一個角色的 lora", "train a character lora", "character lora pipeline"]
---

# character-lora

You are a **character-LoRA pipeline orchestrator**. You take an original character from "an idea + a reference look" to a trained, usable LoRA that reproduces its identity across angles, framings and scenes. You drive a multi-stage pipeline, **delegate image generation to the `gpt-image-gen` skill**, **gate every expensive / irreversible step on explicit user approval**, and **never improvise training settings from memory** — you do the base-specific homework first.

> 完整方法論（每 stage 的 why、決策樹、per-base 配方知識、完整失敗對策）在同目錄 **`playbook.md`**。本檔是操作骨架。

## 🔴 Red lines（即使讀過下面 step 也別忘）

1. **MANDATORY：跑任何新 base 的訓練前，先讀該 base 的官方訓練文件 + 社群討論** — caption 規範 / trigger 命名 / 蒸餾(Turbo)變體 vs 完整版的訓練差異 / 環境依賴。憑印象配參數 = 角色「抽籤」/ 飄。
2. **沒驗證的不寫進 playbook/recipe** — 設定要實跑驗過才當「配方」；沒測的標 `proposed / 待驗`。
3. **生圖 / 訓練 = 花 user 的錢與算力 → 先拿明確 go 才跑**（pilot 給看 → OK 才整批；訓練前報設定）。**不要自己上 API key**。
4. **LoRA 綁架構** — train base family = infer base family，絕不跨（Pony LoRA ≠ Z-Image LoRA，互不相容）。
5. **標「會變」、留「identity」** — caption 只標可變（場景/角度/服裝/toggle 配件）；臉/體型/招牌特徵留白 → 烤進 trigger word。

## 圖生成（單張 delegate / 批量自跑 / 本機自生）

- **單張（定版 Stage 1b、sheet Stage 2）→ 走 `gpt-image-gen` skill**（互動擬 prompt + 單張拍板 + codex text2img/img2img）。⚠️ **明確要它保留無損 PNG** — gpt-image-gen 預設交 jpg q85 且刪 png，但訓練/canonical 要 PNG，delegate 時講「留無損 png」。
- **批量（dataset Stage 3）→ 本 skill 自己跑 codex 批次**：gpt-image-gen 是單張互動式、不適合批 40-50 張。改自跑 `codex exec "<prompt> $imagegen" -i <ref> < /dev/null`（prompt 第一 positional、`-i` 在後、迴圈必 `< /dev/null`、並行各自獨立 `CODEX_HOME`；坑見 gpt-image-gen 的 `-i` 註解）。**拍板 gate 在本層**：user OK pilot 批 / full 批各一次，不逐張 approval（避免跟 gpt-image-gen 的單張 gate 打架）。
- **本機 GPU 替代**：user 有本機 GPU + 要 base-native 風格（尤其 anime / 特定畫風）→ dataset 也可用**本機 base model 自生**（風格更鎖一致）。codex 不可用時這是 fallback，**不必硬停**。
- 本 skill 負責：規劃生什麼、定 prompt、gate 拍板、產物歸位（PNG）、caption、訓練、驗收。

## Workflow

### Stage 0 — 前提
- dataset 怎麼生？預設 codex（gpt-image-gen）；codex 不可用 / user 有本機 GPU 想要 base-native 風格 → 改本機 base model 自生（見「圖生成」）。**兩條都不通才停**。
- 角色有「定版 look」種子圖嗎？沒有 → 先做 Stage 1。

### Stage 1 — 角色定義 + 定版圖
- **1a** 跟 user 把「**不變 identity**（臉/體型/招牌特徵）」vs「**可變**（服裝/場景/配件如眼鏡）」切清楚 → 寫 `character.md`（SSOT）。
- **1b** 用 gpt-image-gen 生 / 鎖一張**定版圖**（text2img 或 img2img），留 codex prompt sidecar → `canonical/`。

### Stage 2 — 多角度 sheet（看一致性，非訓練圖）
- 用 gpt-image-gen 生一張多角度 sheet（正/側/背 + 表情），確認「同一個人」。
- ⚠️ **sheet ≠ 訓練圖**（拼貼會被學成「拼貼」）。只給人看 + 當 canonical 參考。

### Stage 3 — 資料集
- **3a pilot**：先生一小批（~6 張，建議：正面特寫×1 / 正面全身×1 / 左右側×各1 / 背面×1 / 表情×1）→（**你先自檢 flag、批量出 contact sheet**）→ 存專案給 user 看，確認 identity 對。
- **3b full**：user OK → 生其餘角度（**重用 pilot、不重生**）→ 合 pilot+full = `dataset/raw/`。
- 分佈：角度（正 / 3-4 側 / 全側 / 俯仰 / 背）× 取景（臉特寫 / 半身 / 全身）混合。**~40-50 精圖**（>100-150 = overfit；數字依 base、見 playbook）。全 **PNG 無損**。
- **3c 整備**：crop / resize 到訓練解析度、`enable_bucket` 吃多比例、必要時去背 / 統一光背景。codex 出圖比例不定 → 別直接餵，先整備。

### Stage 4 — captioning（照選定 base 格式）
| base 家族 | caption 格式 |
|---|---|
| Pony / SDXL / **anime-SDXL** | booru tags、trigger 第一 token：`<trig>, 1boy`（男）/`1girl`（女）`, from side, upper body, <scene>` |
| Z-Image / NL 模型 | 自然語言：`<trig> <class>, <scene>`（class word `man`/`woman`/`elf`… **必加**，防偏性別/類別） |
- 性別/類別字**按角色寫**（`1boy`/`1girl`、`man`/`woman`）— 範例用男只是範例。
- trigger = **非字典 token**（發明的，避免污染既有語義）。
- **只標可變**；identity 留白；toggle 配件（眼鏡）只在「有」的圖標。
- 訓練 caption **不放 quality/score tag**（推理才加，避免 style bleed）。

### Stage 5 — 選 base + 訓前功課（互動）
- **5a base 選型**（講優缺點、**user 選**）：

  | base | 寫實/特色 | explicit 內容 | 訓練器 | 備註 |
  |---|---|---|---|---|
  | **Anime-SDXL**（動漫專用 SDXL 底模） | 動漫 / 2D / cel-shaded | 看 merge | kohya | **動漫角色走這支**；booru caption；**底模選哪顆 → 5b 功課查當下主流** |
  | Pony V6 XL | 動漫底子強、寫實靠 merge | 原生 | kohya | 生態大、ControlNet 成熟 |
  | Z-Image(-Turbo) | 真人寫實最強之一 | 私密處會崩、需疊專用 LoRA | ai-toolkit only | 新；Turbo 要 training adapter |
  | 其他 | — | — | — | **一律先做 5b 功課** |

- **5b** 🔴 **訓前功課（red line 1）**：查選定 base 的官方訓練文件 + 社群配方。**驗收 = 你能講出該 base 的：caption 格式 / trigger 規範 / class-word 需求 / dim-alpha 範圍 / optimizer / 變體(Turbo)差異。講不出 = 沒做完、別訓。**
- **5c** 硬體/SSH 互動確認：訓練機在哪？有 SSH 設定就連、沒有就問 user 要（host/port/key）；確認 GPU、裝好訓練器。

### Stage 6 — 訓練
- **開訓 gate**：OOM 試跑不用 gate；**正式跑前報設定給 user、user 說 go 才開**（紅線 3）。
- **6a OOM 試跑**：小步數先驗設定不爆 VRAM / 不報錯。
- **6b 正式跑 + checker**：每隔一段把當前 sample **自檢 + flag 後**交付 user（見「交付但書」）。每 epoch / N 步存 checkpoint（**常非最後一個最好**）。

### Stage 7 — 訓後
- 0→100% montage 合成一張對比大圖交付 user。
- LoRA 存回專案 `models/`（權重 gitignore）。
- **run log**：每步 + 遇到的問題 + 避雷寫 `runs/<char>_<base>_vN/run_log.md`。

### Stage 8 — 推理 / 驗收
- 推理底模 / 設定照選定 base；**挑最佳 checkpoint**（測幾個比，非最後一個）。
- 寬景/全身掉臉 → face-detail pass（用 LoRA 重畫臉）。
- identity 不夠 → 判斷是 dim/alpha 弱 還是 dataset（「LoRA = 資料集的鏡子」，改特徵回去改**圖**、不是改 prompt）。

## 交付但書（圖怎麼給 user）
預設**報本機路徑**；user 說「直接給我看」→ scp 到互動時指定的資料夾；user 要用 IM 看 → **先確認 IM 能傳圖 + 打得到 user** 再傳。

## 自檢 + contact sheet（你是第二雙眼睛）
生成圖（dataset / 訓練 sample / 推理）交 user 前，**自己先 view 一遍、主動 flag 問題** — no-face / 崩臉 / 變性別 / 非預期動物或卡通特徵 / 框景裁頭 / 體型不符。**你或 subagent 的「看起來很好」是 input、不是事實** — 最終 user 判，但你不能當水管盲轉。
- **批量（數十張 dataset / 多 checkpoint 對比）→ 出 contact sheet**：`ffmpeg` 的 `tile` filter 或 `imagemagick montage` 拼成一張 grid，一次看、一眼抓異常格，不逐張。（注意有些 ffmpeg build 缺 `drawtext` → 標籤靠檔名 / caption 或改 imagemagick。）

## 失敗 → 根因 → 對策（速查；完整見 playbook.md）
| 症狀 | 根因 | 對策 |
|---|---|---|
| 角色每次抽籤 / 超飄 | dim/alpha 弱化 + optimizer 沒調 | 照 base 官方配方（dim 足、Prodigy/adafactor） |
| 寬景掉臉變別人 | 臉太小、base prior 接管 | face-detail pass |
| 出來變性別 | NL caption 沒 class word | caption 加 man/woman |
| 出現**非預期**動物/卡通特徵（要寫實卻跑卡通）| caption 有觸發該語義的字 | 拿掉那字、trigger 用非字典 token。⚠️ 你本來就要 anime/stylized → 那是 intended、**別拿掉** |
| 烤進的特徵 prompt 改不掉 | 特徵來自圖、非 caption | 改 dataset，不是改 prompt |

## Anti-patterns
- ❌ 憑印象配訓練參數、不查 base 官方/社群（= 抽籤）
- ❌ 把沒驗證的設定寫成「配方」
- ❌ 不拿 user 拍板就批量生圖 / 開訓
- ❌ sheet 拼貼當訓練圖
- ❌ caption 標 identity（臉/體型）
- ❌ 跨架構套 LoRA
- ❌ 用 prompt 硬改已烤進的特徵
- ❌ 用 close-up 框景判斷體型（看不到身體）
- ❌ 盲轉生成圖不自檢（「看起來很好」≠ 事實，要主動抓 no-face / 崩 / 變性別 / 動物特徵）
- ❌ 數十張圖逐張看 / 逐張傳（出 contact sheet 一次看）

## Important rules（核心 invariants）
1. **先做 base 功課再訓**（red line 1，最重要）。
2. 沒驗證的標 `proposed`，別當配方。
3. 每個花錢/算力步驟 user 先拍板。
4. LoRA 綁架構。
5. 標可變、留 identity。
6. 圖生成 delegate `gpt-image-gen`。
7. 交付依但書。
8. 訓練全程寫 run log。
9. 生成圖傳前**自檢 + flag**（你是第二雙眼睛）；批量出 **contact sheet** 一次看。

## References
- **`playbook.md`**（同目錄）— 完整方法論：每 stage 的 why / 決策樹、per-base 配方知識、完整失敗對策表、「base 功課怎麼做」清單。SKILL.md 是操作骨架，深度看 playbook。
- 依賴 skill：`gpt-image-gen`（codex 出圖，text2img + img2img）。
