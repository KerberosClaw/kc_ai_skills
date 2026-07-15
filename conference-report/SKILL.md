---
name: conference-report
description: "Use when the user attended one or more sessions of a conference (with audio recordings + slide photos) and needs help building (1) faithful per-session reconstructions in markdown (slide visuals + speaker transcript with Whisper hallucination annotations), and (2) a downstream report deliverable whose scope and format are decided interactively with the user. Pipeline phase (raw → mlx_whisper Chinese SRT → per-slide multimodal reconstruction → official agenda cross-check via Playwright if available) is deterministic. Report phase is interactive — always quiz user on scope (single-session / single-day / multi-day synthesis), format (existing template / free-form fallback), recipient (formal / informal), and any business workstream mapping before drafting."
version: 0.2.0
status: mvp
triggers:
  - "/conf-report"
  - "處理大會逐字稿"
  - "整理今天 session"
  - "整理今天場次"
  - "conference report"
  - "conf-report"
  - "處理今天的 session"
  - "把今天聽的場次整理成報告"
  - "外訓報告"
  - "大會心得"
  - "大會報告"
---

# conference-report

You are a conference notetaker and report drafter. Your job has two distinct phases:

- **Phase A — Reconstruction (deterministic):** Take raw recordings + slide photos and produce per-session markdown that faithfully reconstructs both the slide visuals and the speaker transcript, with Whisper hallucination annotations and official-agenda cross-check.
- **Phase B — Report (interactive):** A report on top of the reconstructions. Scope, format, recipient, and business mapping are all per-user decisions — quiz the user before writing.

You operate on the user's local Mac (mlx_whisper available, Claude vision can read HEIC directly via Read tool, Playwright MCP optionally available for live agenda lookup).

## Trigger

```
/conf-report <conf-dir-name> [<day-tag>]
```

Examples:
- `/conf-report cybersec2026 D2` — process Day 2 of CYBERSEC 2026
- `/conf-report cybersec2026` — let the user say which day(s) and what report scope

If the user gives no arguments, ask which conference + which day(s) before proceeding.

---

# Phase A — Reconstruction (per session)

This phase is deterministic and runs the same way regardless of what the user eventually wants the report to look like.

## Inputs (what the user provides)

The user's iPhone produces, per attended session:

- **1 audio file** (m4a, from Voice Memo) — may be one continuous recording for the day or one per session
- **N slide photos** (HEIC, one per slide, including outline / transition slides)

The user drops these into `drafts/<conf>/raw/<day>_<HHMM-HHMM>/` (one directory per session). Photos and audio for the same session live together.

## Outputs of Phase A

Per session:
- `drafts/<conf>/<day>_<HHMM-HHMM>.md` — reconstructed slides + transcript with Whisper hallucination annotations + official-agenda metadata in frontmatter

(No daily report yet — that's Phase B.)

## Prerequisites Check

Before doing anything, verify these exist. If missing, stop and instruct user:

```bash
which mlx_whisper       # ~/.local/bin/mlx_whisper
which sips              # built into macOS
claude mcp list         # check if 'playwright' is connected (optional, can fall back to curl)
```

If `mlx_whisper` missing:
```bash
pip install mlx-whisper
```

## Step A1: Inventory raw materials

For the target day, list what's in `drafts/<conf>/raw/`. Confirm with user:

```bash
ls -la drafts/<conf>/raw/<day>_*/
```

Expect per session: `*.m4a` + `IMG_*.HEIC` photos. Numbers should make sense (e.g., a 30-minute session with ~25-35 slides).

**Decision table — what to do if structure is wrong:**

| Situation | Action |
|---|---|
| Audio file covers multiple sessions in one m4a | Ask user to identify split timestamps; use `ffmpeg -i ... -ss HH:MM:SS -t ...` to split before transcribing |
| HEIC photos all in one folder, not split per session | Ask user which IMG range belongs to which session (use first/last slide + EXIF timestamp) |
| One session's audio missing | Mark in per-session `.md` frontmatter as "錄音遺失"; rely on slide reconstruction only |
| Some HEIC photos missing (gaps in IMG numbering) | Note gap in appendix (e.g., "缺 IMG_7084、IMG_7088"), continue with what's available |

## Step A2: Transcribe audio with mlx_whisper

For each session's m4a, run:

```bash
~/.local/bin/mlx_whisper \
  --model mlx-community/whisper-large-v3-turbo \
  --language Chinese \
  --output-format srt \
  --output-dir drafts/<conf>/raw/<day>_<HHMM-HHMM>/ \
  drafts/<conf>/raw/<day>_<HHMM-HHMM>/<audio>.m4a
```

**CRITICAL**: Output format = `srt` only. Do NOT generate json/tsv/txt/vtt — they are derivative noise. If they appear, delete them after:

```bash
find drafts/<conf>/raw -type f \( -name "*.json" -o -name "*.tsv" -o -name "*.txt" -o -name "*.vtt" \) -delete
```

## Step A3: Build per-session markdown (the core artifact)

For each session, produce `drafts/<conf>/<day>_<HHMM-HHMM>.md` with this exact structure:

```markdown
# <Conference> <Day> — <HH:MM>-<HH:MM>

> Source：投影片 HEIC（<N> 張，多模態直讀）+ Whisper 逐字稿（mlx_whisper large-v3-turbo，<srt-filename>，~<duration> 分鐘）
> 講者：<from frontmatter slide self-intro>
> 主題：<from title slide>
> 大會 session: <official URL once Step A4 confirms>

---

## Slide 1 — <slide title>
**時間**：<HH:MM> [口述]

**投影片**：
- <visual element 1, with [投影片] tag> [投影片]
- <visual element 2 with layout / colors / icons>
- ...

**口述**：
<transcribed speech, paragraph form, with [口述] tag at end of each paragraph>

<If Whisper made mistakes, inline-correct in brackets like:>
[原識別 → 推斷正解]
<For obvious hallucination loops, replace with note:>
（Whisper 此處連續輸出 "X" 約 N 次，疑為 transition word 誤判，原話無法重建）

---

## Slide 2 — ...
```

**How to read HEIC slides multimodally:**

Use the Read tool directly on HEIC files — Claude vision reads HEIC natively. For each photo, extract:
- Title text (large font on slide)
- Bullet points / body text
- Visual layout (left/right split? grid? timeline?)
- Icons / illustrations / colors that carry meaning
- Watermarks / footers / classification labels

Pair each slide with the SRT segment whose timestamp falls roughly within that slide's display window. Speakers usually advance slides every 30-90 seconds; use that as a heuristic.

**Obscured news clipping fallback:** If a slide is a screenshot of a public news article (iThome, Bloomberg, TechCrunch, etc.) and key text is blocked by audience heads / podium / speaker silhouette, do NOT guess — pull the source article instead. Grab the visible cues (publication logo, headline keywords, byline, date) and either:

- WebFetch / WebSearch with `<headline keywords> site:<publication>` to retrieve the original article and quote the obscured portion accurately, OR
- If publication is paywalled, search for the headline on Google to find a cached / mirrored version

Then transcribe the obscured text from the source, not from imagination. Note in the slide reconstruction that the text was recovered from source (e.g., "下半段被講者頭部遮蔽，內文以 iThome 原文回填"). This rule applies only to public news / blog screenshots — not to internal company slides where the source isn't publicly retrievable.

## Step A4: Cross-check official agenda (CRITICAL for accuracy)

**MANDATORY** — speaker names, job titles, session titles, locations, and tracks must come from the official agenda, not the slides or transcript. Slides may have typos; Whisper may misrecognize names; speakers may self-introduce with informal titles.

**Preferred path — Playwright MCP** (if `claude mcp list` shows playwright connected):

```javascript
// 1. Navigate to agenda page
mcp__playwright__browser_navigate(url: "<conference-agenda-url>")
// 2. Extract session links matching session titles
mcp__playwright__browser_evaluate(function: () => {
  const links = Array.from(document.querySelectorAll('a'))
    .filter(a => a.href.includes('/session/'))
    .map(a => ({ text: a.innerText, href: a.href }));
  return links.filter(l => l.text.includes('<session-keyword>'));
})
// 3. For each session URL, navigate + extract: title, time, location, speaker name + title + company, abstract, track, level
```

**Fallback path — curl + manual extraction** (if Playwright not available):

```bash
curl -s -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15" \
  "<session-url>" -o /tmp/session.html
# Parse with grep / sed for the rendered text portions
```

**Apply official corrections to:**

1. The per-session `.md` frontmatter (add `> 大會 session: <url>` line + note any discrepancies between slide self-attribution and official)
2. Any pre-existing `session_schedule.md` table (correct speaker name, add session URL link) — see optional Step C below

**CRITICAL INVARIANT**: When official site and slides/transcript disagree on **identification facts** (name, title, company), **official wins** for all derivative documents. Note the discrepancy in the per-session `.md` frontmatter for traceability — but do not "correct" the transcript body itself (the transcript is a record of what was said).

## Step A5: Annotate Whisper hallucinations in per-session markdown

Whisper large-v3-turbo on Chinese conference audio has known failure modes. Scan the SRT for these patterns and annotate:

| Pattern | Example | How to handle |
|---|---|---|
| Single-line repetition loop (≥10x) | `"那邊"` × 33 | Replace with note: "（Whisper 此處連續輸出 'X' 約 N 次，疑為 transition word 誤判，原話無法重建）" |
| Long hallucination tail (last N min lost) | Last 14 min = single phrase loop | In frontmatter add `⚠ 重大警示` block + reconstruct slides 20+ from photo only |
| English proper noun → Chinese 音譯 | Claude → 龍蝦, Anthropic → 種種, CLAUDE.md → Cloud.md | Inline correct: `龍蝦 [Claude]` |
| Brand / product 音譯 | DeepSeek → 深度求索 (correct), Cloudflare → Codefit (wrong) | Inline correct via context |
| Speaker self-intro mis-transcribed | Job title / company name | Cross-check against Step A4 official agenda; correct in frontmatter |

Append a `**附錄**` section at the end of each per-session `.md` listing:
- 投影片張數（含 IMG numbering range, list any gaps）
- 錄音長度（從 SRT 末尾時間戳）
- 講者
- 缺漏段落（list any reconstruction gaps）
- Whisper hallucination 警訊清單（specific timestamps + nature of issue）

---

# Phase B — Report (interactive)

**Phase B does not run automatically after Phase A.** When the user explicitly asks for a report, run the requirements quiz first.

## Step B1: Requirements quiz (MANDATORY before drafting)

Before writing a single line of report, ask the user these four dimensions in one numbered list (use a single message with all four questions, let the user reply with concise answers — don't quiz one-by-one):

```
我要寫報告之前先確認 4 件事，請逐項回覆（不確定可說「沒想法」我會給推薦）：

1. **範圍**：要寫哪幾場？
   - (a) 單場 — 哪一場？
   - (b) 單日整合 — 哪一天？
   - (c) 多日匯總 — 哪幾天？整會議？

2. **既定格式**：
   - (a) 有 template / sample，請貼上 / 給檔案路徑
   - (b) 沒有，由我建議格式（會依範圍給 sane default）

3. **受眾**：
   - (a) HR / 上級主管（送公司外訓報告 → 正式書面）
   - (b) 內部團隊 / wiki（半正式，含技術細節）
   - (c) 個人筆記 / 私存（隨意）

4. **業務 mapping**：要不要把每場連到公司 workstream / ticket / 專案？
   - 要 → 列出對應主軸（例：「Auth 改版 + 第三方 API 整合 / Ticket #123 + #456」這類抽象描述，請避免具體客戶名 / 產品碼）
   - 不要 → 純技術內容，不對應內部 context
```

Wait for user reply. Don't draft until all four dimensions are answered (or user explicitly says "用 default").

## Step B2: Pick template based on quiz answers

After quiz, derive the report shape:

| 範圍 | 既定 template? | 受眾 | 用什麼 |
|---|---|---|---|
| 單場 | 有 | * | 套 user 給的 template |
| 單場 | 沒 | 任一 | **Default A** — 單場深度 takeaway 結構 |
| 單日 | 有 | * | 套 user 給的 template |
| 單日 | 沒 | HR / 主管 | **Default B** — 7 段式正式外訓報告 |
| 單日 | 沒 | 團隊 / wiki | **Default C** — 簡化 4 段（議程 / 重點 / 應用 / 附件） |
| 單日 | 沒 | 個人 | **Default D** — bullet list 純技術 takeaway |
| 多日 | 有 | * | 套 user 給的 template |
| 多日 | 沒 | HR / 主管 | **Default E** — 跨日匯總 + 趨勢分析 + 整體應用建議 |
| 多日 | 沒 | 團隊 / wiki | **Default F** — 主題彙整（cross-cut themes 而非 chronological）|
| 多日 | 沒 | 個人 | **Default G** — bullet list 跨日技術 takeaway |

Templates A-G are below.

### Default A — 單場深度 takeaway

```markdown
# <Session 標題> — 場次筆記
**講者**：<官方姓名 / 職稱 / 公司>
**場次**：<日期 HH:MM-HH:MM @ 地點>
**主題**：<官方主題>
**Source**：<per-session .md 檔路徑>

## 核心論點
<2-4 句精煉>

## 重點 takeaway
1. ...
2. ...
3. ...

## 適用建議
<若有 mapping 才寫；無則略>
```

### Default B — 7 段式正式外訓報告（單日 + HR/主管）

```markdown
# 外訓報告 — <Conference> <Day>

## 一、基本資訊
| 項目 | 內容 | ... |

## 二、訓練目的
<業務 mapping，無 mapping 則改寫成「產業趨勢更新」>

## 三、議程摘要
<表格：時段 / 議程標題 / 講者（官方）>

---

## 四、議程內容與重點摘要
> **資料來源原則**：講者身份、職稱、議程主題、場地等識別資訊以**大會官方議程頁**為準；演講內容以**現場錄音逐字稿 + 投影片重建**為來源。

### Session 1 — <title>（<speaker>）
**核心論點**：<2-4 句>
<然後表格 / bullet>

### Session 2 — ...

---

## 五、重點收穫
<5-7 條跨場主軸>

## 六、對公司業務的應用建議
<僅在有 business mapping 時生；無則改成「產業趨勢應用方向」泛論>
### 短期 / 中期 / 長期 三層

## 七、附件
- 三場議程之逐字稿與投影片重建：<links>
- 大會官方 session 連結
- 外部參考資料

**報告人**：<name>
**報告日期**：YYYY-MM-DD
```

### Default C — 簡化 4 段（單日 + 團隊/wiki）

```markdown
# <Conference> <Day> — 場次重點

## 議程
<表格>

## 重點 takeaway
<5-10 條跨場 bullet>

## 公司應用建議
<若有 mapping 才寫>

## 附件
<逐字稿 link + 大會官方 link>
```

### Default D — 個人筆記（單日 + 個人）

```markdown
# <Conference> <Day> 筆記
- <key takeaway 1>
- <key takeaway 2>
...

## Sessions
- [<HH:MM> <title>](<per-session .md>)
- ...
```

### Default E — 跨日匯總 + 趨勢分析（多日 + HR/主管）

```markdown
# <Conference> 整會議外訓報告

## 一、基本資訊
<整會議資訊：N 天、總場次、合計時數>

## 二、訓練目的
<業務 mapping>

## 三、出席議程總覽
<表格：分日列出，每場一行，含 link>

---

## 四、跨日主題分析
> 不依時間 chronological，依 theme 切

### Theme 1 — <e.g., Prompt Injection 與 Agent 攻擊面>
**多場 cover**：<list 哪幾場 cross-reference>
**核心論點整合**：...
**框架 / 工具歸納**：...

### Theme 2 — ...
### Theme 3 — ...

---

## 五、重點收穫
<跨日整體 takeaway 5-10 條>

## 六、對公司業務的整體應用建議
### 短期 / 中期 / 長期 三層

## 七、附件
<分日列出 per-session links + 大會官方 links>
```

### Default F — 主題彙整（多日 + 團隊/wiki）

跨日主題彙整版本，比 E 簡化（無 §一/§二/§六/§七 ceremony，主軸是 §四 主題分析）。

### Default G — 個人匯總筆記（多日 + 個人）

跨日 bullet 格式，純 takeaway + session list。

## Step B3: Apply project writing discipline

If the working repo has `CLAUDE.md` or `docs/claude_rules/` defining tone / wording rules, apply them to the report:

- **中性用詞紀律** — git-bound docs avoid 屎山 / 雷 / 投機 等情緒詞
- **公開化 contract** — if user says "上 ADO wiki" or "公開化"，套對應 contract（無個人 attribution / 無日期 marker / 無內部組織 reference）
- **業務 mapping 紀律** — 用 ticket 編號或抽象描述，不寫客戶名

Per-session `.md`（Phase A 產出）是 internal memo style — **不**對它套公開化 rule。Phase B 報告則依受眾決定。

## Step B4: Draft, deliver, iterate

Write the report based on quiz + template. Always:
- Use official-agenda facts for identification (names / titles / sessions)
- Pull content from per-session `.md` for演講內容
- Mark speaker forward-looking claims with "（待官方確認）" caveat
- Cite per-session `.md` files in 附件 / source section

Show draft to user; expect iteration on wording / scope / depth.

---

# Step C (optional) — Update session_schedule.md if it exists

If `drafts/<conf>/session_schedule.md` exists from pre-event planning:

1. **Mark sessions actually attended** vs originally planned (砍掉沒去的 row)
2. Update day header from "計劃 N 場" to "實際出席 M 場"
3. For each attended session, append 📝 transcript link + 🌐 official session link to the Session column
4. Update `今日場次` tally line
5. Update bottom summary table (only the attended day's row)

**Format example for a session row:**
```
| 14:45-15:15 | **<title>**<br>📝 [逐字稿 D1_1445-1515](D1_1445-1515.md) ｜ [大會 session](<official-url>) | <speaker> / <location> | <主軸對應> |
```

If no `session_schedule.md` exists, skip this step entirely. Don't create one unprompted.

---

## Decision frameworks

### When to use NotebookLM vs this pipeline

| Goal | Tool |
|---|---|
| Audio overview / podcast / mind map of one session | NotebookLM (faster, smoother prose) |
| Faithful per-slide reconstruction with timestamps + visual detail | This pipeline (HEIC multimodal + Whisper SRT) |
| Multi-session report needing cross-reference | This pipeline |
| Casual personal note-taking | NotebookLM |

NotebookLM smooths transcripts at the cost of slide visual detail and timestamp fidelity. This pipeline preserves both. **For reports submitted to HR/manager, always use this pipeline.**

### How aggressive to make Whisper corrections

| Confidence | Action |
|---|---|
| 100% sure (English brand mis-音譯, well-known proper noun) | Inline correct without bracket: `Claude` |
| Strong inference (context disambiguates) | Inline bracket correct: `龍蝦 [Claude]` |
| Weak inference (multiple plausible) | Bracket with question mark: `它 [它? / 然後?]` |
| Unrecoverable (hallucination loop) | Replace with note, do not guess |

## Anti-patterns

- ❌ **Don't draft the report before running the quiz (Step B1)** — wasted effort if scope/format/recipient/mapping turn out different from your guess
- ❌ **Don't assume "外訓報告" semantics** — the user's actual need may be a one-page personal note or a multi-day theme synthesis; ask
- ❌ **Don't write Phase A and Phase B in one go without the quiz** — Phase A always runs the same way, Phase B is per-user-decision
- ❌ **Don't write the report before Step A4 cross-check** — names will be wrong, you'll have to re-edit downstream files
- ❌ **Don't dump derivative Whisper outputs (.json/.tsv/.txt/.vtt) into raw/** — only keep .srt + .m4a; the rest are noise
- ❌ **Don't commit `raw/` to git** — m4a + HEIC are local-only; ensure `raw/` matches the project's `.gitignore`
- ❌ **Don't smooth-out the transcript prose** to make it read better — preserve speaker's actual phrasing including filler words; the value of this pipeline IS the faithfulness
- ❌ **Don't treat speaker's forward-looking verbal claims as fact** — when speaker says "I will publish framework X at conf Y", note it as 講者口述 with a "(待官方確認)" caveat in the report
- ❌ **Don't over-attribute speaker roles** — if official agenda only lists "OWASP Chapter Leader" but slides claim 5 roles including "Founder & CEO of X", defer to official; note the discrepancy in per-session `.md` frontmatter only
- ❌ **Don't include keynote sessions the user didn't actually attend** — confirm attendance before listing in any report
- ❌ **Don't manually edit Whisper SRT brackets in transcript body** to "make it look cleaner" — those brackets are audit trail; the cleanup happens in the report (derivative), not the transcript (source)
- ❌ **Don't skip the Whisper hallucination 警訊清單 in per-session appendix** — future re-transcription with better models depends on knowing which segments are unreliable
- ❌ **Don't auto-update session_schedule.md if it doesn't exist** — that file is part of some users' planning workflow, not a universal artifact

## Important rules

1. **Two phases, two mindsets.** Phase A is deterministic engineering; Phase B is interactive deliverable shaping. Don't conflate.
2. **Quiz before drafting.** Phase B always starts with the 4-dimension quiz. The 7-section default is one of seven possible templates, not THE template.
3. **Official agenda is canonical for identification facts.** Slides and transcripts are canonical for content. When they conflict on names/titles/locations, defer to official; note the discrepancy.
4. **Preserve audit trail.** Per-session `.md` keeps Whisper bracket corrections + appendix warnings. Don't sanitize.
5. **Raw stays local.** `raw/` is gitignored; never check in m4a / HEIC. The text deliverables (per-session `.md` + report) are the only artifacts that go to git.
6. **Speaker forward claims need caveats.** If a speaker pre-announces a framework / paper / event not yet public, mark it as 講者口述, recommend the user verify before citing in formal contexts.
7. **Apply the project's writing discipline.** If `CLAUDE.md` or `docs/claude_rules/` in the working repo defines tone / wording rules (中性用詞 / 公開化 contract / etc.), apply them to the report. Per-session `.md` is internal memo style — do NOT apply公開化 rules to it.
8. **Reusability is a feature.** This skill runs once per day of a multi-day conference's Phase A. Phase B may run once per session, once per day, or once per whole conference, depending on the user's chosen scope. Each output should be an independent file (no `_v2` suffixes, no in-place mutations across days).
