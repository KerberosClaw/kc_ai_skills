# HANDOFF — kc_ai_skills 維護接手

> 給接手繼續整理這個 repo 的 agent。讀這份就知道現況＋下一步（lint sweep）＋紅線。
> 建立：2026-07-15。

## 現況
- 22 顆 skill、public、MIT、雙語 README（`README.md` + `README_zh.md`）。
- 剛併入 #21：README 加了「規劃類 skill 選哪顆」決策框、prd-create 補 vs-spec 路由（版號 0.3.1）。
- adr / diagnose / grill 三顆從 mattpocock/skills 內化重寫，是這批的 canonical 範本。

## 任務：lint sweep（frontmatter 一致性 + pattern 檢核）

lint 依據＝`docs/skill_writing_patterns.md`（15 patterns + checklist）。把 22 顆逐一對照。

### 已驗證的 frontmatter 不一致（全 22 顆掃過、非抽樣外推）
- 🔴 **`status:` 欄大量缺**：只有 adr / diagnose / grill / prd-create ＝ mvp、prd-breakdown ＝ stable，其餘約 17 顆**沒有 status 欄**。先跟 user 定「status 是否必填、值域（mvp / stable / …）」，再補齊。
- 🟠 **triggers 格式混用**：有的 YAML list（`- "x"`）、有的 inline array（`["x","y"]`）。挑一種當 canonical、統一。
- 🟠 **version 語意未定義**：0.1.0～2.0.0 都有，有 mvp 卻掛 1.0.0、也有 0.x。定清楚「status（mvp/stable）↔ version 號」的對應規則。

### 從深讀 prd-create / spec / adr 看到的較深缺口（其餘 19 顆待同樣檢查）
- **description 深度不一**：prd-create 的 description 很長、帶 NOT-for 路由；spec 只有一行。統一「description 要不要帶 trigger／路由資訊」。
- **「跟其他 skill 的關係」段落有的有、有的沒**：prd-create 有完整 relations 段、spec 幾乎沒有。有了 #21 決策框後，易混的 skill 應在自己 SKILL.md 補一行「vs X 見 routing guide」（agent 只 load SKILL.md 時看不到 README 表）。
- **grill canonical 引用**：prd-create / spec 都正確指「訪談問法紀律同 grill」。掃其他做訪談的 skill 是否一致指 grill、而非各自重寫。

## 已經好的（別動壞）
- #21 的決策框、mattpocock 出處標註（Acknowledgments／README 工程紀律段的 attribution）——別砍。
- adr / diagnose / grill 是範本，其他對齊它們、不是反過來。

## 紅線
- 🔴 **public repo**：範例／fixtures 一律抽象、虛構——**禁真公司／客戶／內部 ticket／真人**（見 memory `feedback_public_skill_examples`）。寫前寫後各 grep 一次禁用詞。
- 🔴 **PR-driven**：branch + PR、不直接 push main（此 repo commit 尾帶 `(#N)`）。
- 🔴 **雙語同步**：改 `README.md` 必同步 `README_zh.md`。
- 改任何 SKILL.md 內容 → bump version。

## 待 user 拍板（別自己猜）
1. status 欄必填嗎？值域？
2. triggers 用 list 還是 inline array？
3. version／status 語意規則？

> 這三題定了 lint 才有一致目標；沒定前先別大改 frontmatter。

## Scope 誠實
- 上一手只深讀 prd-create / spec / adr 三顆；frontmatter 掃描涵蓋全 22。
- 「對照 `skill_writing_patterns.md` 全 checklist 逐顆過」**尚未做**——那是接手者的主工。
