---
name: llm-benchmark
description: "本地 LLM Benchmark 工具。當使用者想測試、比較或選擇本地 Ollama 模型時觸發。流程：檢查 Ollama 安裝 → 依 VRAM 推薦模型大小 → 下載模型 → 跑 benchmark → 與現有模型比較 → 輸出 markdown 報告。"
version: 1.0.0
triggers: ["/llm-benchmark", "測本地模型", "模型 benchmark", "比較 ollama 模型"]
---

# LLM Benchmark Skill

你是本地 LLM 效能評測專家。執行以下完整流程：

## Step 0：環境檢查

```bash
# 確認 Ollama 是否安裝並運行
curl -s http://localhost:11434/api/version 2>/dev/null || echo "NOT_RUNNING"
which ollama 2>/dev/null || echo "NOT_INSTALLED"
```

- 若 **未安裝**：執行 `curl -fsSL https://ollama.com/install.sh | sh`，再啟動服務
- 若 **未運行**：執行 `ollama serve &` 或 `systemctl start ollama`
- 確認成功後繼續

## Step 0.5：VRAM 清空（benchmark 前必做）

### 1. 停止其他吃 GPU / RAM 的本地 LLM 服務（若有且正在運行）

```bash
# 檢查是否有 LLM gateway 類容器正在運行（例：OpenClaw、LM 代理服務）
LLM_GATEWAY="your-llm-gateway"   # 換成你的服務名，例：openclaw
docker ps --format '{{.Names}}' | grep -i "$LLM_GATEWAY"
```

- 若有相關容器正在運行 → 停止它：
  ```bash
  LLM_STACK_DIR="$HOME/your-llm-stack"   # 換成你的 compose 目錄
  GATEWAY_SERVICE="gateway"              # 換成你的服務名
  cd "$LLM_STACK_DIR" && docker compose stop "$GATEWAY_SERVICE"
  ```
- 若無相關容器，或容器已停止 → 跳過此步驟

記錄該服務是否原本是啟動的，**benchmark 完成後需還原狀態**。

### 2. 重啟 Ollama 清除 VRAM（必做）

```bash
sudo systemctl restart ollama
sleep 5
```

### 3. 確認 VRAM 已釋放

```bash
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits
```

確認 `memory.used` 降到 ~1500 MB 以下再繼續。若仍偏高，再等 5 秒重確認。

### 4. Benchmark 完成後還原服務

若步驟 1 有停止服務，benchmark 全部完成後執行：
```bash
cd "$LLM_STACK_DIR" && docker compose start "$GATEWAY_SERVICE"
```

---

## Step 1：取得 GPU/VRAM 資訊

```bash
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits 2>/dev/null \
  || rocm-smi --showmeminfo vram 2>/dev/null \
  || echo "NO_GPU"
```

依據 **可用 VRAM** 推薦模型最大參數量（以 Q4 量化為基準）：

| 可用 VRAM | 推薦最大 B |
|-----------|-----------|
| < 4 GB    | 3B        |
| 4–6 GB    | 7B        |
| 6–8 GB    | 8B        |
| 8–10 GB   | 12–14B    |
| 10–14 GB  | 14B       |
| 14–16 GB  | 14–20B    |
| > 16 GB   | 30B+      |

**向使用者說明推薦理由**，列出推薦模型清單（附 Ollama model tag）。

## Step 2：確認要測試的模型

詢問使用者確認測試清單（若使用者已在指令中指定則略過）。

同時列出機器上 **現有模型**：
```bash
curl -s http://localhost:11434/api/tags | python3 -c "
import sys,json
data=json.load(sys.stdin)
for m in data.get('models',[]):
    print(m['name'], round(m['size']/1024/1024), 'MB')
"
```

## Step 3：檢查既有 Benchmark 記錄

檢查 `~/benchmark_results.json` 是否存在：

```bash
python3 -c "
import json, os
path = os.path.expanduser('~/benchmark_results.json')
if not os.path.exists(path):
    print('NO_BENCHMARK_FILE')
else:
    data = json.load(open(path))
    benchmarked = [e['model'] for e in data]
    print('BENCHMARKED:', benchmarked)
"
```

- 若某模型**已有 benchmark 記錄** → 直接沿用，不重跑
- 若機器上有模型**但無 benchmark 記錄** → 詢問使用者是否要補跑
- 若是**新模型**（需先 pull）→ 自動 pull 後跑 benchmark

## Step 4：Pull 新模型

```bash
ollama pull <model_tag>
```

pull 完成後確認：`ollama list | grep <model_name>`

## Step 5：執行 Benchmark

將 `skills/llm-benchmark/scripts/benchmark.py` 複製到目標機器並執行：

```bash
# 複製到 PC（若透過 SSH）
scp scripts/benchmark.py USER@PC_IP:/tmp/benchmark.py

# 在 PC 上執行（需先 pip install requests）
python3 /tmp/benchmark.py <model1> <model2> ...
```

> benchmark.py 的完整原始碼在 `scripts/benchmark.py`。

## Step 6：生成 Markdown 報告

benchmark 完成後，讀取 `~/benchmark_results.json`，生成 `~/model_benchmark.md`。

報告結構（參考 `~/model_benchmark.md`）：
1. **執行環境**（CPU / GPU / RAM / OS）
2. **測試模型列表**（參數量、最大 ctx、檔案大小）
3. **Token/s 速度總覽表格**（模型 × context size）
   - 若某個 ctx size 的 `cpu_offload_detected` 為 true，在表格該格標示「⚠️ 中止」，並加註說明：
     > 此 context size 的 KV cache 超過 GPU VRAM 容量，Ollama 自動將計算 offload 至 CPU，導致 GPU 使用率驟降、CPU 全速運轉，推理速度大幅劣化。測試已提前終止，此 ctx 不列入甜蜜點評估。
4. **GPU 資源使用**（VRAM、GPU 利用率）
5. **回答品質評估**（每題正確性分析 + 摘要）
6. **Context Window 甜蜜點分析**（僅含未觸發 cpu_offload 的 ctx）
7. **瓶頸分析**（Compute Bound vs Memory Bandwidth Bound）
8. **排名**（邏輯推理 / 程式設計 / Token/s）
9. **結論與建議**（依使用情境推薦）

## Step 7：結論說明

向使用者口頭總結：
- 各模型 token/s 排名
- 回答品質排名（重點標注邏輯題正確性）
- VRAM 使用量
- **最終推薦**：哪個模型適合什麼情境

## 注意事項

- 全程使用**繁體中文**
- 每個推理超時設 120 秒，避免卡住
- 若模型 pull 失敗，記錄原因後繼續測其他模型
- 生成報告前先確認 `~/benchmark_results.json` 完整性
- 報告最後更新時間戳記
