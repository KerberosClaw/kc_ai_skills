# 實作守則

Implement Stage 的每個 task 都要遵守。`SKILL.md` 只寫步驟，守則以本檔為準。

參考 [Karpathy 對 LLM coding pitfalls 的觀察](https://github.com/forrestchang/andrej-karpathy-skills)：

**1. Surgical Changes — 只動必要的**
- 不「順便改善」鄰近 code、comment、formatting
- 不重構沒壞的東西
- 保持現有 style，即使你覺得寫法可以更好
- 發現無關的 dead code → 提一下，**不要自己刪**
- 檢驗：每一行 diff 都要能追回到當前 task 的需求

**2. Simplicity First — 最少的 code 解決問題**
- 不加超出需求的功能
- 不為「未來可能」做抽象
- 不做 user 沒要求的錯誤處理
- 200 行能做完的事不要寫 500 行

**3. Orphan Cleanup — 只清自己造成的孤兒**
- 你的改動讓某個 import / variable / function 用不到 → 你清掉
- **不要順手清「預先存在」的 dead code**，除非 user 明確要求

**4. 如果實作中發現 spec 有問題**
- 停下來，不要自己解讀
- 回到 Spec Stage 跟 user 確認，或至少在 tasks.md 的 Notes 記下歧異

**5. 三振原則**
- 同一個問題試了 3 次不同方法都失敗 → 停下來，跟 user 說清楚狀況，不要繼續猜
