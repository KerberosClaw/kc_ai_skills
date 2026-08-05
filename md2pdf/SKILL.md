---
name: md2pdf
description: "Use when the user wants to convert one Markdown file into a publication-ready A4 PDF, especially when the source may contain Mermaid diagrams, ASCII diagrams, CJK text, tables, or pandoc/weasyprint edge cases. Works by copying the source to a _pdf.md working file, converting diagrams, escaping PDF-breaking syntax, balancing table column widths, rendering with pandoc + weasyprint, then self-checking pages by ink coverage. Cleans up intermediates only after the user calls the version final. NOT for batch conversion, slide decks, or editing the original Markdown in place."
version: 1.2.0
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

### Step 2: Ask CSS style preference

Present options to the user. If they don't choose, pick the most suitable one automatically:

- **Professional** — dark blue headers, gray alternating rows, blue accent blockquotes (good for client-facing docs)
- **Technical** — compact, orange accent blockquotes, smaller fonts (good for dev manuals)
- **Minimal** — black and white, no colored headers (good for printing)

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
- Determine flow direction: prefer `LR` (horizontal) for linear flows, `TD` (vertical) for hierarchical
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
- If a vertical flowchart has > 5 nodes, consider switching to `LR`

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

Create temporary files:

**Lua filter** (mermaid-filter.lua):
- Intercept `mermaid` code blocks
- Call `mmdc -o output.png -b white --scale 3`
- Embed as PNG (never SVG — SVG has font rendering issues with weasyprint)

**CSS** (based on user's style choice):
- Body font: `"Heiti TC", "PingFang TC", "Arial Unicode MS", sans-serif`
- Code font: `"Menlo", "Heiti TC", "Arial Unicode MS", monospace`
- `pre code { background-color: transparent; }`
- `img { max-width: 100%; max-height: 700px; }`
- `white-space: pre-wrap; word-wrap: break-word;` on `pre`
- Page: `@page { size: A4; margin: 2cm; }`
- **`table { table-layout: fixed; }`** — required, or Step 5c's column ratios are ignored
- **`td, th { word-wrap: break-word; overflow-wrap: break-word; }`** — keeps long cells inside their column
- **`thead { display: table-header-group; } tr { page-break-inside: avoid; }`** — a table taller than one page should split between rows and repeat its header, not get pushed whole onto the next page leaving a mostly-blank one

**pandoc command:**
```bash
pandoc "{filename}_pdf.md" \
  --lua-filter=mermaid-filter.lua \
  --pdf-engine=weasyprint \
  --css=style.css \
  --no-highlight \
  -o "{filename}.pdf"
```

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

Reading 40 pages by eye is slow and misses things. Measure ink coverage first, then only look at the outliers:

```bash
pdftoppm -png -r 80 out.pdf /tmp/pg
python3 - <<'PY'
import glob
from PIL import Image
for p in sorted(glob.glob("/tmp/pg-*.png")):
    im = Image.open(p).convert("L")
    ink = sum(im.histogram()[:240]) / (im.size[0] * im.size[1]) * 100
    if ink < 4:
        print(f"{p}: {ink:.1f}% — inspect this page")
PY
```

Under ~4% almost always means something got pushed to the next page. A final page below the threshold is normal (it is just the tail of the document).

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
- **Clean up only after the user calls the version final** — then delete the intermediates outright, no second confirmation
