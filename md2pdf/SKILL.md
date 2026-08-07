---
name: md2pdf
description: "Use when the user wants to convert one Markdown file into a publication-ready A4 PDF, especially when the source may contain Mermaid diagrams, ASCII diagrams, CJK text, tables, or pandoc/weasyprint edge cases. Works by copying the source to a _pdf.md working file, converting diagrams, escaping PDF-breaking syntax, balancing table column widths, rendering with pandoc + weasyprint, then self-checking pages by ink coverage. Cleans up intermediates only after the user calls the version final. NOT for batch conversion, slide decks, or editing the original Markdown in place."
version: 1.3.0
status: stable
triggers:
  - "/md2pdf"
  - "轉 pdf"
  - "markdown 轉 pdf"
  - "convert to pdf"
---

# md2pdf

You are a Markdown-to-PDF production assistant. You convert exactly one Markdown file at a time into a clean, publication-ready A4 PDF while preserving the original source file.

## Trigger

```
/md2pdf path/to/file.md
```

## Prerequisites Check

Before anything else, verify these tools exist. If any is missing, stop and show install commands:

```bash
# Check all three
which pandoc && which mmdc && which weasyprint
```

Missing tool install commands:
- **pandoc**: `brew install pandoc`
- **mmdc**: `npm install -g @mermaid-js/mermaid-cli`
- **weasyprint**: `pip install weasyprint` or `brew install weasyprint`

## Workflow

### Step 1: Check for existing _pdf.md

If `{filename}_pdf.md` already exists, ask the user:
- **Use existing**: convert `_pdf.md` directly to PDF (user may have manually tuned it)
- **Regenerate**: copy from original and redo all conversions

### Step 2: Ask style, and ask about a table of contents

**2a. CSS style.** Present options; if the user doesn't choose, pick the most suitable one automatically:

- **Professional** — dark blue headers, gray alternating rows, blue accent blockquotes (good for client-facing docs)
- **Technical** — compact, orange accent blockquotes, smaller fonts (good for dev manuals)
- **Minimal** — black and white, no colored headers (good for printing)

**2b. Table of contents — always ask, never assume.** A contents page also pulls the
title onto a cover sheet, so switching it on costs a full page before the reader
reaches any content. That is right for a report and absurd for a two-page memo.

Ask outright. If the user has no opinion, decide by length and say which you picked:

| Source length | Default | Why |
|---------------|---------|-----|
| Under ~6 pages of content | **No TOC** | A cover plus a contents list for a handful of sections is pure overhead |
| Longer, or many `##` sections | **TOC** | Real page numbers make it navigable |

**2c. Version footer.** If the document carries a `> Version: ...` (or `> 版本：...`)
line under its H1, it is lifted out of the body and printed bottom-right on every
page. If the document is going to a third party and has no version line, offer to
add one — without it nobody can tell which draft they are holding.

### Step 3: Copy original → {filename}_pdf.md

**Never modify the original file.** All changes happen on the copy.

### Step 4: ASCII Art → Mermaid conversion

Scan all code blocks (` ``` ` without language tag) and classify:

| Pattern | Classification | Action |
|---------|---------------|--------|
| Arrows (`→ ► ▼ ──►`) + boxes (`┌ ┐ └ ┘`) | Flowchart / architecture | Convert to Mermaid |
| `├──` `└──` + file paths | Directory tree | Keep as-is |
| Already ` ```mermaid ` | Mermaid | Keep as-is |
| Simple one-liner `A → B → C` | Ambiguous | Keep as-is |
| Anything uncertain | Unknown | Keep as-is |

When converting to Mermaid:
- Write the direction that reads best at the source (usually `LR` for linear flows). **Do not hand-tune direction for the PDF** — Step 6 measures both orientations and picks the legible one.
- Keep node text short (< 20 chars per line)
- Use `<br/>` for line breaks (never `\n`)
- Avoid markdown-triggering syntax in nodes: no `1.` prefix, no `*`, no `[]()`
- Replace full-width brackets `（）` with half-width or remove
- Replace `≥ ≤` with `>=` `<=`

### Step 5: Markdown sanitization for pandoc

**5a. Mermaid syntax cleanup** — for ALL mermaid blocks (both converted and pre-existing):
- `\n` → `<br/>`
- Remove numbered prefixes in node text (`1. `, `2. ` etc.)
- Simplify special characters that may cause parsing errors
- **Leave the flow direction alone** — Step 6 chooses it by measurement

**5b. Dollar sign escaping** — pandoc interprets `$...$` as LaTeX inline math. In markdown table cells, an unescaped `$` (e.g. `NT$1`) will pair with a later `$` (e.g. `NT$5,000`) and swallow everything between them into a math span, destroying table row boundaries.
- Escape ALL `$` signs outside of code blocks: `$` → `\$`
- This applies to currency symbols (`NT$`, `US$`, `€` is fine), variable references (`$HOME`), and any other bare `$`
- `$` inside code blocks (`` ` `` or ` ``` `) are safe — pandoc doesn't process them

**5c. Table column widths** — the single biggest lever on how the PDF *looks*.

With the usual `|---|---|---|`, every column renders equal width, so a one-character `#` column gets as much room as a column holding three sentences. On a table-heavy document this wastes a large fraction of every page and reads as amateurish.

**The fix needs two halves, and neither works alone:**

| Half | Where | What it does |
|------|-------|--------------|
| Dash proportions in the separator row | Markdown: `\|---\|------------\|` | pandoc's **default** markdown reader emits `<col style="width:N%">` from the ratio |
| `table-layout: fixed` | CSS | Makes the browser/weasyprint actually honor those widths instead of auto-sizing |

⚠️ **pandoc's `gfm` reader ignores separator proportions entirely.** If the build passes `-f gfm`, drop that flag — otherwise this step is a no-op. Verify with:

```bash
pandoc -t html file.md | grep -o 'width: [0-9]*%'   # should print one % per column
```

**Do not hand-tune 20 tables.** Run the bundled script, which derives each column's share from its actual content:

```bash
python3 scripts/table_widths.py "{filename}_pdf.md"
```

It handles two things that are easy to get wrong:

- **CJK width** — CJK characters occupy two cells, so weights are measured in display width, not `len()`.
- **Unbreakable-token floor** — `word-wrap: break-word` will split a Latin word mid-token when its column is too narrow (`PostgreSQL` → `PostgreS / QL`). Each column gets a floor wide enough for its longest token. The default factor is tuned for a CJK sans-serif at ~9.5pt; if you still see mid-word breaks, raise `TOKEN_FACTOR` in the script and re-run.

Re-run the script after any table edit — it is idempotent, and ratios are recomputed from cell contents rather than from the previous separator row.

**Observed effect**: on a 40-page table-heavy report, rebalancing widths brought it to 34 pages with no content removed.

### Step 6: Generate PDF

Use the bundled builder. It carries the CSS, the diagram pipeline, the version
footer and the page-break rules, so none of that has to be reassembled per run:

```bash
scripts/build_pdf.sh "{filename}_pdf.md" "{filename}.pdf" \
  --style professional \
  --no-toc                 # or --toc, per Step 2b
```

Options: `--style professional|technical|minimal`, `--toc` / `--no-toc`,
`--toc-depth N`, `--mermaid vertical|keep`.

**Diagram orientation is measured, not guessed.** A horizontal chain that reads
fine on screen is scaled to roughly a quarter inside A4's ~17cm text column and
its labels stop being readable. But flipping blindly is also wrong: a vertical
version can be tall enough that the height cap shrinks it right back. So the
builder renders each `LR` diagram both ways, computes the scale the page will
actually apply — `min(width_fit, height_fit)` — and keeps whichever orientation
holds the larger one. Vertical costs page height, which is the cheaper resource.

Measured on a six-diagram report: LR chains came out at 4.4–5.0 : 1 and were
unreadable; going vertical grew the document from 7 to 11 pages and was still
clearly the right trade. Pass `--mermaid keep` to opt out.

What the builder handles that a bare pandoc call does not:

| Behaviour | Why it matters |
|-----------|----------------|
| `> Version:` / `> 版本：` line → bottom-right on every page, removed from body | Otherwise nobody can tell which draft they are holding |
| TOC off by default; title inlined when off | A named CSS page forces a break, so a cover sheet appears even with no TOC unless the title's `page:` rule is also dropped |
| Diagrams rendered to PNG, empty alt text | SVG mis-renders fonts in weasyprint; a non-empty alt becomes a visible figure caption under every diagram |
| `table-layout: fixed` + `thead` repeat + `tr` unbreakable | Step 5c's ratios are a no-op without `fixed`; tables taller than a page must split between rows, not jump whole to the next page |
| Ink self-check including the **last** page | See Step 7 |

⚠️ **Never add `"Apple Color Emoji"` to the CSS `font-family`, at any position.**
It carries keycap glyphs for 0–9, and weasyprint routes every Arabic numeral in
the document to it — they print as blank space. The text layer still contains the
digits, so `pdftotext` looks correct and the damage is invisible until someone
reads the paper. For coloured status markers, embed a PNG.

If you need something the builder doesn't cover, fall back to assembling pandoc
by hand — but copy the CSS out of the script rather than rewriting it, or you
will rediscover the traps above one at a time.

### Step 7: Self-check

Read every page of the generated PDF. Check for:

| Issue | Detection | Fix |
|-------|-----------|-----|
| Nearly blank page | Page has < 10% content | Diagram too tall → switch to LR layout or reduce nodes |
| "Unsupported markdown" text | Literal string match | Node text has list syntax → remove numbered prefixes |
| `?` boxes in text | Character replacement indicators | Font fallback issue → check CSS font-family |
| Table rows merged into one cell | Single row contains `\|\|` or content from multiple expected rows | Unescaped `$` triggering LaTeX math mode → escape all `$` outside code blocks |
| All table columns equal width | A one-character column as wide as a prose column | Step 5c not applied, or the build passes `-f gfm`, or CSS lacks `table-layout: fixed` |
| A Latin word split mid-token | `PostgreS / QL` across two lines | Column narrower than its longest token → raise `TOKEN_FACTOR` in `table_widths.py` and re-run |
| Mostly-blank page before a big table | Page under ~4% ink, next page starts with that table | Table set to `page-break-inside: avoid` but taller than one page → allow it to split, keep `tr` unbreakable, repeat `thead` |

Reading 40 pages by eye is slow and misses things. `build_pdf.sh` runs this check
automatically; the logic, if you are assembling by hand:

```bash
pdftoppm -png -r 80 out.pdf /tmp/pg
python3 - <<'PY'
import glob
from PIL import Image
pages = sorted(glob.glob("/tmp/pg-*.png"))
for i, p in enumerate(pages):
    im = Image.open(p).convert("L")
    ink = sum(im.histogram()[:240]) / (im.size[0] * im.size[1]) * 100
    last = i == len(pages) - 1
    if (ink < 1.5 if last else ink < 4):
        print(f"{p}: {ink:.2f}% — {'trailing orphan' if last else 'inspect this page'}")
PY
```

Under ~4% on a middle page almost always means a table or diagram was pushed off it.

⚠️ **Do not exempt the final page from the check.** It is tempting — a tail page is
legitimately sparse — but blanket-skipping it is exactly how a document ships with
one stranded line on its own sheet. A genuine tail page still carries a paragraph
or two; under ~1.5% ink means one or two lines, which is an orphan, not a tail.

Fixing an orphan is not "delete a sentence until it fits". The reliable move is to
**fold the closing line into the block above it** — into the last table row, or
into the preceding paragraph. Trimming prose is unreliable: shortening a line that
still wraps to the same number of rendered lines frees nothing, and the boundary
does not move. Measure instead of guessing: if the free space at the bottom of the
previous page is smaller than one line height plus the paragraph's top margin, no
amount of rewording that keeps the paragraph separate will pull it up.

If issues found: fix `_pdf.md`, regenerate. **Maximum 3 retries**, then stop and report remaining issues to user.

### Step 8: Cleanup — only once the user has signed off

Cleanup is **not** part of every render. Iteration usually takes several rounds, and re-running is far cheaper when the working file and the CSS are still on disk.

**While iterating** — keep everything: `{filename}_pdf.md`, `mermaid-filter.lua`, `style.css`, and any generated diagram PNGs.

**Once the user confirms the version is final** — delete the whole intermediate set without asking again:

```bash
rm -f "{filename}_pdf.md" mermaid-filter.lua style.css
# plus any diagram PNGs generated during the run
```

What survives: the original `.md` and the finished `.pdf`. Nothing else.

The confirmation to wait for is an explicit "this version is good / final / ship it" — not merely the absence of complaints about the last render.

⚠️ **Before deleting, check whether the user asked to keep an earlier PDF.** If they did, make sure the earlier file still exists under its own name; never let a later render silently overwrite a version the user asked to preserve. Version filenames (`_v1`, `_v2`) are cheaper than regenerating a version you can no longer reproduce.

### Step 9: Report

Output:
- PDF file path
- Page count
- Any known remaining issues (if retry limit was hit)

## Anti-patterns

- ❌ **Editing the original `.md`** — all changes happen on the `_pdf.md` copy; the source is never touched
- ❌ **SVG for Mermaid** — weasyprint mis-renders SVG fonts; always render diagrams to PNG
- ❌ **Leaving `$` unescaped outside code blocks** — pandoc pairs them into LaTeX math spans and eats table rows; escape every bare `$`
- ❌ **Batch-converting in one call** — one file per invocation; loop by re-invoking, don't glob
- ❌ **Retrying forever on a broken page** — cap at 3 regenerations, then stop and report the remaining issue instead of silently shipping a bad page
- ❌ **Leaving `|---|---|---|` on every table** — equal widths make a `#` column as wide as a prose column and waste a large share of each page; run `scripts/table_widths.py`
- ❌ **Setting column ratios but forgetting `table-layout: fixed`** (or vice versa) — the two halves only work together; one alone is a silent no-op
- ❌ **Reading `-f gfm` output and wondering why widths are ignored** — the gfm reader drops separator proportions; use pandoc's default markdown reader
- ❌ **Hand-picking diagram direction for the PDF** — `LR` looks right in the source and prints too small; blind flipping to `TD` can be worse. Let the builder render both and measure
- ❌ **Adding `"Apple Color Emoji"` to the font stack** — every digit in the document silently prints blank while `pdftotext` still shows them
- ❌ **Non-empty alt text on rendered diagrams** — pandoc promotes it to a figure caption, printing the alt word under every diagram
- ❌ **Turning the TOC on by default** — it drags the title onto a cover sheet; two pages of overhead in front of a short memo. Ask
- ❌ **Exempting the last page from the ink check** — that is how a one-line orphan page ships
- ❌ **Trimming prose to kill an orphan page** — shortening text that still wraps to the same line count frees nothing; fold the line into the block above instead
- ❌ **Cleaning up before the user signs off** — deleting `_pdf.md` and the CSS mid-iteration means rebuilding all manual tuning on the next round
- ❌ **Overwriting a PDF the user asked to keep** — give the new render a version suffix instead
- ❌ **Leaving temp files behind after sign-off** — once the version is final, remove `_pdf.md`, `mermaid-filter.lua`, `style.css` and diagram PNGs without asking again

## Important Rules

- **NEVER modify the original markdown file**
- **Always use PNG for Mermaid rendering** (not SVG)
- **Always disable syntax highlighting** (`--no-highlight`)
- **Always include CJK font fallback** in CSS
- **Fixed A4 page size** — no other options
- **One file at a time** — user can invoke multiple times for batch
- **Table widths need markdown ratios AND `table-layout: fixed`** — neither half works alone
- **Ask before adding a TOC** — it costs a cover sheet plus a contents page
- **Lift the version line into a per-page footer** — a third party must be able to tell which draft they hold
- **Let the builder measure diagram orientation** — never hand-tune `LR`/`TD` for print
- **Check the last page too** — under ~1.5% ink is an orphan, not a tail
- **Clean up only after the user calls the version final** — then delete the intermediates outright, no second confirmation
