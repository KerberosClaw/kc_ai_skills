---
name: md2pdf
description: "Convert Markdown to publication-ready A4 PDF with automatic ASCII-to-Mermaid conversion, CJK font handling, and self-check. Use when user says '/md2pdf', 'convert to pdf', 'markdown to pdf', or similar."
version: 0.1.0
---

# md2pdf

Convert a Markdown file to a clean, publication-ready A4 PDF.

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

If issues found: fix `_pdf.md`, regenerate. **Maximum 3 retries**, then stop and report remaining issues to user.

### Step 8: Cleanup

Remove temporary files:
- `mermaid-filter.lua`
- `style.css`

Ask user: **Keep or delete `{filename}_pdf.md`?**

### Step 9: Report

Output:
- PDF file path
- Page count
- Any known remaining issues (if retry limit was hit)

## Important Rules

- **NEVER modify the original markdown file**
- **Always use PNG for Mermaid rendering** (not SVG)
- **Always disable syntax highlighting** (`--no-highlight`)
- **Always include CJK font fallback** in CSS
- **Fixed A4 page size** — no other options
- **One file at a time** — user can invoke multiple times for batch
