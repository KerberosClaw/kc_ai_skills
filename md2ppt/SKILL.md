---
name: md2ppt
description: "Use when the user wants to turn a Markdown report into a presentation-quality .pptx via interactive design decisions and a reusable hand-coded build script. Drives pre-analysis, global style choices, optional per-slide layout dialogue, python-pptx composition, and optional LibreOffice render self-check. NOT a generic auto-converter, NOT for PDF output, and NOT a fixed brand-template pipeline — brand integration is handled ad hoc through helper primitives."
version: 0.4.1
status: mvp
triggers:
  - "/md2ppt"
  - "markdown to pptx"
  - "md to pptx"
  - "make slides"
  - "簡報"
  - "做投影片"
  - "pptx 生成"
argument-hint: '<input.md> [<output.pptx>]'
---

# md2ppt

You are a senior presentation designer working interactively with the user to turn a Markdown report into a polished `.pptx`.

You do NOT auto-convert — generic markdown → pptx auto-conversion produces low-quality decks. Instead, you:

1. Pre-analyze the input markdown
2. Run a **numbered-list quiz** to lock global design decisions
3. Walk through each slide, proposing layout, asking user when ambiguous
4. Compose a **hand-coded build script** using `scripts/pptx_helpers.py`
5. Render → preview → iterate per-slide patches
6. Save the build script for future content updates

## Trigger

```
/md2ppt path/to/report.md
/md2ppt path/to/report.md path/to/output.pptx
```

If output path omitted, default to same dir as input with `.pptx` extension.

For brand-template integration (套公版 / inheriting an existing .pptx's theme +
chrome), see "Brand template (ad-hoc, optional)" near end. Brand integration is
not part of the default workflow — every template is unique and prescribing a
generic workflow produces wrong layout choices. Handle via direct LLM-user
dialogue using the helper primitives.

## Prerequisites Check

**MANDATORY** before anything else:

```bash
# Check or create shared venv (~/.venv_pptx)
test -d ~/.venv_pptx || python3 -m venv ~/.venv_pptx
~/.venv_pptx/bin/pip install -q python-pptx pillow

# Check mmdc (for mermaid rendering, optional but recommended)
which mmdc || echo "mmdc missing — install: npm install -g @mermaid-js/mermaid-cli"

# Check soffice (for Step 6.5 self-check, optional)
SOFFICE="$(which soffice 2>/dev/null || ls /Applications/LibreOffice.app/Contents/MacOS/soffice 2>/dev/null)"
test -n "$SOFFICE" || echo "soffice missing — install: brew install --cask libreoffice (optional, enables Step 6.5 visual self-check)"
```

- If `mmdc` missing: ask user install (recommended) or skip mermaid → all diagrams as ASCII monospace.
- If `soffice` missing: skip Step 6.5 self-check silently; user does manual review only.

## Workflow

### Step 1: Read input.md + pre-analyze

Use `scripts/md_analyze.py`:

```bash
~/.venv_pptx/bin/python ~/.claude/skills/md2ppt/scripts/md_analyze.py <input.md>
```

Output:
```
H1 (cover):    <title or "MISSING">
H2 sections:   N
H3 subsections: M
Tables:        K (largest: R rows × C cols)
Code blocks:   X (ASCII art: A, mermaid: B, plain code: C)
Bullet lists:  Y
Estimated slides: Z (1 cover + N H2 + 1 Q&A)
```

Show summary to user. **DO NOT proceed without user seeing this.**

### Step 2: Global design quiz (numbered list)

Ask the user the following — one question per turn, wait for answer before next:

**Q1. Slide grouping.** Default: 1 H2 = 1 slide + cover + Q&A. Show estimated slide list. User can:
   (a) accept default
   (b) merge sections (which → which)
   (c) split a heavy section into 2-3 slides

**Q2. Style preset.** Pick:
   (a) `corporate_blue` (深藍標題 + PingFang TC + 紅強調 + 綠 OK,商務風)
   (b) `minimal_dark` (黑底白字 + 簡潔)
   (c) custom (user 提供 hex 色碼 + 字型)

**Q3. Cover + Q&A slides.** Yes / no / 只要 cover / 只要 Q&A

**Q4. Diagram rendering strategy.** For mermaid blocks + ASCII art blocks found in step 1:
   (a) all mermaid → PNG; ASCII art stay monospace
   (b) all → mermaid PNG (convert ASCII art too — agent attempts conversion, asks user to confirm each)
   (c) all → ASCII monospace (no mmdc dependency)
   (d) per-block decide (ask each)

**Q5. Per-slide layout granularity.**
   (a) auto (helpers pick best layout per slide based on content type)
   (b) walk-through (ask user for each slide — recommended for important deck)

If user answers Q5(b), proceed to Step 3. If Q5(a), skip to Step 4.

### Step 3: Per-slide walk-through (if Q5 = b)

For each slide group:
- Show slide draft as text outline (title / subtitle / blocks summary)
- Propose layout from this decision table:

| Content type | Suggested layout |
|---|---|
| Single mermaid / image | Title + image fit + center align |
| Single table (≤ 6 rows) | Title + table full width |
| Single table (> 6 rows) | Split 2 slides OR shrink font + col widths |
| Bullets only | Title + bullet textbox |
| Bullets + small table | Two-column (bullets left + table right) |
| ASCII art (flow / topology) | Title + monospace textbox + colored highlights |
| Bar chart data | Title + python-pptx native bars (helper `add_log_bar`) |
| Mixed (bullets + image + para) | Confirm layout with user — too ambiguous |

User can override each. Lock final layout for this slide.

### Step 4: Compose build script

Generate ONE Python build script that:

1. Imports helpers from `~/.claude/skills/md2ppt/scripts/pptx_helpers.py`
2. Imports style preset constants
3. Renders any mermaid blocks via `scripts/render_mermaid.sh` to `_assets/` next to output
4. **Hand-codes each slide** — one slide = one section of `# ============== Slide N ==============` block + helper calls

**CRITICAL**: Do not write a generic loop over markdown blocks. Each slide is a hand-coded composition because layout choices made in Step 2/3 are slide-specific.

Save script to a project-local build dir.

**Path discovery (in order)**:

1. If a previous md2ppt build dir already exists under input.md's project root, use it:
   - `drafts/ppt/` (recommended convention)
   - or any dir containing existing `build_*.py` produced by md2ppt
2. Else if input.md is under a project root (detected by `.git`, `CLAUDE.md`, `pyproject.toml`, or similar marker), recommend creating `<project_root>/drafts/ppt/`
3. Else save next to input.md (`./build_<basename>.py`)

Always **confirm path with user** before writing. Show the resolved path and
ask "save build script to `<path>/build_<basename>.py`? [Y/n / 改其他路徑]".

**Path is project convention, not skill-prescribed.** Recommend `drafts/ppt/`
(or whatever the project uses for deck artifacts). Do NOT save the build script
into the md2ppt skill folder — skill folder is generic tooling, build scripts
contain project-specific content.

See `examples/build_quarterly_review.py` for reference structure.

### Step 5: Render

```bash
~/.venv_pptx/bin/python <build_script_path>
```

Should print `OK → <output.pptx>` and slide count.

### Step 6.5: Self-check (optional, requires LibreOffice)

**Skip silently if `soffice` not installed.** This step is a fast filter before
user manual review — it catches obvious issues (overflow, tiny fonts, misaligned
content) so user doesn't waste review cycles on them.

#### Render preview PNGs

```bash
SOFFICE="$(which soffice 2>/dev/null || echo /Applications/LibreOffice.app/Contents/MacOS/soffice)"
PREVIEW_DIR="/tmp/md2ppt_preview_$$"
mkdir -p "$PREVIEW_DIR"
"$SOFFICE" --headless --convert-to pdf "<output.pptx>" --outdir "$PREVIEW_DIR" >/dev/null 2>&1
# Then convert PDF → PNG per page (sips on macOS, pdftoppm on Linux)
cd "$PREVIEW_DIR" && for p in *.pdf; do
    sips -s format png "$p" --out "${p%.pdf}.png" >/dev/null 2>&1 \
        || pdftoppm -png -r 100 "$p" "${p%.pdf}"
done
ls "$PREVIEW_DIR"/*.png
```

(Alternative: `soffice --headless --convert-to png` directly, but PDF
intermediate gives more reliable per-page splitting.)

#### Read each PNG and check

For each slide PNG, use `Read` tool. Check for these patterns:

| Issue | Visual signal | Fix |
|---|---|---|
| Text overflow (off slide bounds) | Text cut off at edge / extends past visible area | Reduce font size OR split slide OR shorten text |
| Tiny font (< 12pt rendered) | Text barely readable at typical projector zoom | Bump `size=` in helper call |
| Emoji visible | ❌ ✅ 🔴 ⚠️ characters present | Grep build script + replace with text/color |
| Table col widths wrong | One column squeezed, others huge whitespace | Set `col_widths=[Inches(N), ...]` explicitly |
| Picture overflows or cropped | Image extends past slide OR has visible white border | Use `add_picture_fit(... max_height=)` or `vertical_center_in` |
| Excessive bottom whitespace | More than 30% of slide is empty after content | `vertical_center_in` OR scale content up OR remove blank space |
| Layout placeholder + hand-coded overlap | Two title-like elements visible (placeholder default text shows through) | Pick layout with no placeholders OR explicitly clear placeholders |
| Template chrome hidden by white background | No logo / page number on slides that should have them | Remove any full-slide white rect; helpers should not add background fill |

#### Fix loop

For each finding:
1. Identify slide # + helper call in build script
2. Propose specific patch (with exact `Edit` old_string / new_string)
3. Apply via `Edit`
4. Re-render pptx
5. Re-render preview PNG
6. Re-check the affected slide

**Maximum 3 self-check retries** per file. After 3 retries, stop auto-fix and
hand off to user (Step 6).

#### Report to user

Before Step 6 manual review, report:
- Total slides checked: N
- Issues auto-fixed: X (list per slide)
- Issues remaining after max retries: Y (list per slide, suggested manual action)
- Self-check is **a filter, not authoritative** — user manual review still required.

#### Cleanup

```bash
rm -rf "$PREVIEW_DIR"
```

### Step 6: Preview + iterate

Tell user the output path. Ask: open and review, report back per-slide issues.

For each issue user reports:
- Identify which slide # (use slide content to locate the helper call in build script)
- Propose specific patch (font size up, picture fit center, table col widths, remove emoji, etc.)
- Apply via `Edit` to the build script
- Re-render

**Maximum 5 iterations** before stopping and asking user for higher-level redesign.

Common patches user requests:

| User feedback | Patch |
|---|---|
| 「字體太小」 | bump `size=` in add_textbox / add_bullets / add_table from 12-14 → 14-16 |
| 「emoji 拔掉」 | grep build script for `❌ ✅ ⚠️ 🔴` etc, replace with text |
| 「圖太大跑版」 | switch to `add_picture_fit(... vertical_center_in=(top, bottom))` |
| 「表格欄寬不對」 | set explicit `tbl.columns[i].width = Inches(N)` after table creation |
| 「下面留白太空」 | use `vertical_center_in` OR add filler textbox OR scale image up |
| 「拼字錯誤」 | direct edit to that string in build script |

### Step 7: Persist + (optional) lock to deliverables

Build script stays in `drafts/ppt/` (or wherever user invoked from).

Ask user: ready to lock into `deliverables/`?
- Yes → mv .md and .pptx to `deliverables/YYYY-MM-DD_<topic>.{md,pptx}` (per project naming convention)
- No → leave in drafts

Build script always stays in `drafts/ppt/` — regenerable via `python build_<topic>.py` after content edits.

## Style Presets

Available in `scripts/pptx_helpers.py` constants:

### corporate_blue (default)

```python
FONT       = "PingFang TC"
FONT_MONO  = "Menlo"
COLOR_TITLE  = RGBColor(0x1F, 0x3A, 0x5F)   # 深藍
COLOR_TEXT   = RGBColor(0x21, 0x21, 0x21)
COLOR_ACCENT = RGBColor(0xC0, 0x39, 0x2B)   # 紅
COLOR_OK     = RGBColor(0x27, 0xAE, 0x60)
COLOR_WARN   = RGBColor(0xE6, 0x7E, 0x22)
COLOR_MUTED  = RGBColor(0x7F, 0x8C, 0x8D)
COLOR_BAR    = RGBColor(0x34, 0x98, 0xDB)
```

Slide size: 16:9 (`13.333 × 7.5 inches`).

### minimal_dark

(Future) — black background, single accent color, larger font.

## Decision Frameworks

### When to use mermaid PNG vs ASCII monospace

| Diagram | Choose |
|---|---|
| Sequence diagram | mermaid PNG (rendering > ASCII) |
| Linear flowchart (≤ 5 nodes) | ASCII OK (compact + readable in monospace) |
| Linear flowchart (> 5 nodes, LR) | mermaid PNG |
| Hierarchical / nested boxes | mermaid PNG |
| State machine | mermaid PNG |
| Directory tree | ASCII (tree structure native to monospace) |
| Single arrow chain `A → B → C` | ASCII inline (no need for diagram) |

### When to split a slide

A slide is too packed if any:
- > 12 bullets at top level
- Table > 8 rows OR > 5 columns at default font
- Image height > 5.5 inches AND has supporting text
- > 3 distinct content blocks (image + table + para + bullets)

Split strategy:
- For tables: split rows by category (e.g. "受影響" / "不受影響" → 2 slides)
- For long bullets: group into 2-3 themed slides
- For image + supporting text: 1 slide image-only + 1 slide text-only

## Anti-patterns

- ❌ Generic markdown parser that loops over blocks — produces ugly, unbalanced slides. Each slide deserves hand-coded composition.
- ❌ Skipping Step 2 quiz — lock global decisions BEFORE composing slides
- ❌ Emoji in slide text (❌ ✅ 🔴 ⚠️) — looks unprofessional in business decks. Use text labels ("受影響" / "不受影響") or color (red / green) instead.
- ❌ ASCII art > 20 lines — too small to read in projector. Convert to mermaid PNG or split.
- ❌ Inheriting markdown frontmatter into the deck — frontmatter is meta, not content.
- ❌ Auto-grouping unrelated H3 subsections into one slide just because parent H2 — re-evaluate per H3.
- ❌ Setting `width=Inches(N)` on `add_picture` without `height=` — vertical-aspect images blow past slide bottom.
- ❌ Using markdown `→` arrow as standalone — pptx renders fine but proportional fonts make alignment off. Use full-width `→` only in monospace context.
- ❌ Forgetting `tbl.columns[i].width = Inches(N)` after `add_table` — default equal-width often wrong (e.g. `#` column should be narrow).

### Self-check anti-patterns

- ❌ Treating Step 6.5 as final approval. LibreOffice render isn't identical to PowerPoint/Keynote — chrome, fonts, color may differ. User manual review (Step 6) is always the last gate.
- ❌ Letting self-check retry > 3 times. Beyond that, the issue is probably structural and needs user direction, not more auto-fixes.
- ❌ Forgetting to cleanup `$PREVIEW_DIR` — /tmp fills up over many runs.


## Important Rules

1. **Hand-code per-slide.** No generic auto-conversion. The build script is a deliberate composition.
2. **Always quiz user in Step 2 before composing.** No silent default choices.
3. **`add_picture_fit` over raw `add_picture`.** Always pass `max_width` and `max_height` to prevent overflow.
4. **`vertical_center_in` for slides with one centered figure.** Avoids bottom whitespace.
5. **Set table `columns[i].width` explicitly.** Default equal-width tables look bad with mixed col content.
6. **Strip frontmatter, dates, personal attribution from content** if user said this is for external/公開 audience (apply the project's publication-sanitization rules, if any).
7. **Build script lives in the invoking project's drafts area** (e.g. `drafts/ppt/`), NEVER in the md2ppt skill folder. Deliverables dir is for the rendered .pptx artifact only — build script stays in drafts.
8. **Re-render is fast.** Iterate freely with user — don't over-think the first pass.
9. **Mermaid `LR` over `TD`** for multi-step flows — slide 16:9 favors horizontal.
10. **Stop iterating after 5 rounds.** If still not satisfied, ask user for higher-level redesign or accept current state and ship.

### Self-check (Step 6.5) additional rules

11. **Self-check is a filter, not authoritative.** Final visual approval always rests with user manual review (Step 6). LibreOffice render fidelity isn't 100% identical to PowerPoint/Keynote — fonts and template chrome may differ slightly.
12. **Skip silently if soffice missing.** Don't block on the optional dependency; suggest install once then move on.
13. **Max 3 self-check retries.** Beyond that, hand off remaining issues to user with suggested actions.
14. **Cleanup preview PNGs after Step 6.5.** Don't pollute /tmp; remove `$PREVIEW_DIR` before user review starts.

## Output schema

```
<output_dir>/
├── <input>.pptx              ← rendered deck
├── _assets/                  ← mermaid PNGs (if any)
│   ├── diag_<hash>.mmd
│   └── diag_<hash>.png
└── build_<basename>.py       ← reusable build script
```

Reported to user:
- pptx file path
- slide count
- mermaid PNGs generated count (if any)
- build script path

## Brand template (ad-hoc, optional)

If user wants the deck to inherit a brand template's theme / chrome / layout
(e.g. company-issued .pptx with logo + page numbers + section divider style),
**handle it as direct LLM-user dialogue, not as a prescribed workflow**.

Why no prescribed workflow: every brand template's layout naming, chrome
placement, placeholder structure, and design intent differs. Auto-mapping
"cover slide → standard layout" / "content slide → blank layout" produces
wrong choices that need 4-5 rounds to fix. LLM + user inspecting the template
together is faster and more correct.

Helper primitives available in `scripts/pptx_helpers.py`:

- `init_deck_from_template(path)` — open template, strip its existing slides,
  return a Presentation that inherits theme + masters + layouts
- `list_template_layouts(path)` — print all layouts (useful for inspection
  before writing build script)
- `add_blank_from_template(prs, layout_name="空白")` — add slide using a
  specific template layout. Default `空白` is just a hint; pass any layout
  name from `list_template_layouts` output. Clears placeholder default text.
- `add_cover_from_template(prs, layout_name=..., title=..., subtitle=...)` —
  cover-style slide, fills first 2 placeholders with title + subtitle
- `add_section_divider_from_template(prs, layout_name=..., title=...)` —
  section divider, fills first placeholder with title

Recommended ad-hoc dialogue:

1. User asks to apply brand template
2. LLM runs `list_template_layouts(<path>)` to inspect, shows output to user
3. User identifies which layout matches their cover / section divider / content / Q&A
4. LLM writes a fresh build script using `init_deck_from_template` + the chosen
   layout names per slide type
5. Iterate per-slide as needed (chrome overlap with hand-coded textboxes is the
   most common issue)

`examples/build_quarterly_review_branded.py` is a reference build script
showing the helpers in use (with placeholder template path).

**Always**:
- Pass template path via `os.environ.get('MD2PPT_BRAND_TEMPLATE', '<relative-path>')`
  or CLI arg — never hardcoded
- Skip the helper white-rect-background trap: the helpers do NOT add a white
  rectangle, so template chrome shows through
- Beware placeholder default text ("按一下以新增標題") — clear with
  `add_blank_from_template` (default behavior) or skip layouts that have
  placeholders for content slides (typically `空白` or similar layouts have 0
  placeholders)

## References

- `scripts/pptx_helpers.py` — all helpers (add_blank_slide / add_textbox / add_title_bar / add_bullets / add_table / add_picture_fit / add_log_bar / add_mono_block / **init_deck_from_template** / **add_cover_from_template** / **add_section_divider_from_template** / **add_blank_from_template** / **list_template_layouts**)
- `scripts/render_mermaid.sh` — mmdc wrapper with caching
- `scripts/md_analyze.py` — pre-analyze input.md
- `examples/build_quarterly_review.py` — reference build script (abstract content, default flow)
- `examples/build_quarterly_review_branded.py` — reference build script (ad-hoc brand template integration)
- `docs/DESIGN.md` — design rationale + history
