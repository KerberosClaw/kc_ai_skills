# character-lora — playbook（方法論深度）

> SKILL.md 是操作骨架；本檔是「**為什麼 + 怎麼判斷 + per-base 配方知識**」。跑流程看 SKILL.md，卡住 / 要決策時翻這裡。

## 心智模型（3 條，橫貫全程）

1. **LoRA = 資料集的鏡子。** 烤進去的特徵（招牌特徵 / 體型 / 髮型 / 配件）來自**圖**、不是 caption。要改它們 → 回去改**資料集**，不是改 prompt（prompt override 已烤進的特徵只能部分、不可靠）。
2. **LoRA 綁架構。** train base family = infer base family。不同架構（如 SDXL-family vs 新世代 NL 模型）的 LoRA 互不相容。**資料集(照片)兩邊通用、是可重用資產**；只有 caption 格式不同、要分別標。
3. **標可變、留 identity。** caption 標的 = 模型認為「可以變」的；留白的 = 烤進 trigger 成為「這角色是誰」。所以場景 / 角度 / 服裝標，臉 / 體型不標。

## 為什麼要先做 base 功課（red line 1 的理由）

不同 base 的訓練「方言」差很多，憑印象套通用 config 會踩：
- **caption 風格**（booru tag vs 自然語言）不同 → 用錯模型不認。
- **蒸餾 / Turbo 變體**常需特殊 training adapter + 不同 sample 設定，不知道 → 「訓壞了」的假象。
- **trigger 命名 / 要不要 class word / 要不要 quality tag**，各 base 規範不同。
- **環境 / 依賴**（哪個訓練器支援、量化、VRAM 配方）不同。

**功課清單**：① 官方 model card / 訓練文件 ② 社群實戰文（dim/alpha/optimizer/步數的實測值）③ 該 base 的「變體差異」（base vs distilled/Turbo）④ 訓練器支援度 + VRAM 配方。**查完再動手。**

## Stage 深度

### 1-2 角色定義 / 定版
- 「不變 vs 可變」這刀切錯，後面全歪。招牌特徵（永遠這臉/這體型）→ 不變、烤進去；可換的（服裝/配件/髮色）→ 可變、當維度。
- **toggle 維度**（如眼鏡）要可控 → dataset 必須**同時有「有」和「沒有」兩種圖**，caption 只在「有」的標。只收一種 = 烤死、toggle 不了。
- 招牌特徵想**鎖死** → 完全不標（全圖都有、留白 → 焊進 identity）；想當**可變維度** → 每張標真實狀態（前提：dataset 真有變化）。
- ⚠️ **跟 base prior 衝突的特徵**（如人類底模上的精靈耳、非寫實比例）：留白可能訓不穩 → 該特徵的圖要**夠多 / 夠一致**，必要時輕標一個 token 拉它。
- **服裝 / costume**：想換裝 → 當可變維度、每張標；屬角色「制服」想固定 → 不標。介於兩者（如「ranger 皮甲」）→ 看你要不要換，由你決定哪邊。
- reg / class images：單一具名角色多半**不用**；風格污染嚴重才考慮。

### 3 資料集
- 多角度是**訓練型 LoRA** 的需求（不是 embedding/IPAdapter，那種偏好乾淨正面）。
- 角度 × 取景都要分佈：全正 → 生不出別角度；全特寫 → 拒生全身。
- **品質 >> 數量**：~40-50 精圖即可，>100-150 = overfit、不是更像；垃圾/重複圖**有害**。AI 生成的一致性 dataset 比多來源混搭穩（避免風格污染）。
- **pilot 重用**：pilot 圖花算力/usage，生 full 時只補沒生過的角度、合併、不重生。

### 4 captioning（per-base）
- **booru-native（Pony/SDXL）**：comma tags、trigger 第一 token、30-60 tags、`keep_tokens=1`（trigger 固定、其餘 shuffle）。訓練**不放 quality/score tag**（style bleed）、推理才加。
- **自然語言（新世代 NL 模型）**：句子、`<trigger> <class word>` 開頭。**禁止會觸發既有語義的字**（如把某類別名寫進去 → 模型照字面渲染）。class word（man/woman…）防 baseline 偏某性別。
- trigger 一律**非字典 token**（發明的、可加前綴）避免污染既有概念。

### 5 base 選型 + 配方知識（generic 起點，仍要查當下版本）
**SDXL-family（如 Pony）配方共識**：
- dim/alpha：角色 16/8 起；**複雜角色（多細節）32/16**；`alpha = dim 一半`（切壞訓練），alpha 絕不 > dim。
- optimizer：低圖數 → 8bit-Adam + 純 cosine；高圖數 → adafactor + cosine_with_restarts；Prodigy 自適應穩（**配純 cosine — cosine_with_restarts 只配 adafactor**）。
- steps：低圖數 ~1000-1500、**高 epoch(15-20) + 低 repeat** → 每 epoch 存、挑最佳（14+ 常 overbake）。
- 其餘：1024 + bucket、min_snr_gamma 5、noise_offset 0.0357（XL 訓練值）、bf16、flip_aug 通常 off（臉不對稱）。

**蒸餾 / Turbo 變體配方**：
- Turbo 訓 LoRA **必疊 training adapter**（否則 de-distill drift，推理要 20-30 步而非快速步數）；完整版訓法不同（通常無 adapter）。
- sample / 推理用 Turbo 設定：少步數 / 低或零 CFG / 對應 scheduler / 無 negative。
- 對應訓練器（如 ai-toolkit）；小 VRAM → fp8 量化 + 低 VRAM 模式。
- lr 不要超（一超就 drift）。

> ⚠️ 以上是**社群共識起點**，跑前仍要查當下版本 + 你的 base 確切文件（red line 1）。

### 6-8 訓練 / 驗收
- **OOM 試跑先**（別整批跑才發現爆 VRAM）。
- **checkpoint 常非最後一個最好** → 存多個、肉眼挑（過甜蜜點 overbake：背景掉質、訓練資料 artifact 跑出來）。
- **寬景掉臉**是 SDXL-LoRA 通病（臉太小、base prior 接管）→ face-detail pass（crop 臉用 LoRA 重畫）。
- diagnose：identity 不穩先分「dim/alpha 容量不足」vs「dataset 問題」，別亂改 prompt。

## 完整 失敗 → 根因 → 對策

| 症狀 | 根因 | 對策 |
|---|---|---|
| 角色每次「抽籤」/ 超飄 | dim/alpha 雙重弱化 + optimizer 沒調 | 照 base 官方配方（dim 足、Prodigy/adafactor、alpha=半dim） |
| 寬景 / 全身掉臉變別人 | 臉太小、base prior 接管 | face-detail pass（用 LoRA 重畫臉） |
| 出來變性別 | NL caption 沒 class word | caption 加 man/woman |
| 出現非預期動物 / 卡通特徵 | caption 有觸發該語義的字 | 拿掉那字、trigger 用非字典 token |
| 烤進的特徵 prompt 改不掉 | 特徵來自圖、非 caption | 改 dataset，不是改 prompt |
| 「訓壞了」但其實是 sample 設定錯 | 蒸餾變體用了 base 的 sample 設定 | 用該變體正確的 sample 設定再看 |
| 表情 / 細節被 face-detail 中和 | detailer denoise 太低 | 拉高 detailer denoise + prompt 補表情 token |
| 多角色互動空間崩（飄浮 / 接錯） | 文字無法指定空間、雙人資料稀疏 | ControlNet（pose/depth）/ 從參考 img2img / 分區 inpaint |

## 自檢 / contact sheet（品質把關）

- **你是第二雙眼睛。** 生成圖傳 user 前自己先 view、主動 flag：沒臉 / 崩臉 / 變性別 / 非預期動物或卡通 / 框景裁頭 / 體型不符。「看起來很好」（你的或 subagent 的）是 input、不是事實 — 最終 user 判，但別盲轉。
- **批量出 contact sheet。** 數十張 dataset 或多 checkpoint → `ffmpeg`（`tile` filter）或 `imagemagick montage` 拼 grid 一張看，效率 + 一眼抓異常。某些 ffmpeg build 缺 `drawtext`（加不了文字標籤）→ 標籤靠檔名 / caption 或用 imagemagick。

## skill 映射（哪裡自動、哪裡人工 gate）
- 自動：codex 出圖（delegate gpt-image-gen）、訓練啟動、進度 checker、montage 合成。
- **人工 gate（不自動跳）**：base 選型、pilot 驗收、訓練設定確認、production 拍板。
- 紅線（功課 / 驗證 / 拍板）= 人工把關。
