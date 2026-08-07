#!/usr/bin/env bash
# build_pdf.sh — Markdown -> A4 PDF (pandoc + weasyprint), with the layout
# decisions that are painful to rediscover every time baked in.
#
#   ./build_pdf.sh SOURCE.md [OUTPUT.pdf] [options]
#
# Options
#   --style professional|technical|minimal   default: professional
#   --toc / --no-toc                         default: --no-toc
#   --toc-depth N                            default: 2
#   --mermaid vertical|keep                  default: vertical (see below)
#
# Requires: pandoc, mmdc (@mermaid-js/mermaid-cli), weasyprint.
# Optional: pdftoppm + Pillow, for the per-page ink self-check.
#
# What this handles that a bare pandoc call does not
# --------------------------------------------------
# 1. VERSION FOOTER. A `> Version: x` / `> 版本：x` line directly under the H1 is
#    lifted out of the body and printed bottom-right on every page. Without it,
#    nobody can tell which draft they are holding. No version line -> no footer.
# 2. TOC IS OPT-IN. A cover page plus a contents list for a 2-page document is
#    pure overhead. Off by default; turn it on for long documents.
# 3. WIDE MERMAID -> VERTICAL. A `flowchart LR` chain is fine on screen but gets
#    scaled down to unreadable when squeezed into A4's ~17cm text column. Long
#    horizontal chains are flipped to TD for the PDF only; the source keeps LR.
# 4. TABLES SPLIT, ROWS DO NOT. A table taller than the page must break between
#    rows with the header repeated, or it gets pushed whole onto the next page
#    and leaves most of one blank.
#
# The original file is never modified; all rewriting happens on a temp copy.

set -euo pipefail

SRC_IN=""; OUT=""; STYLE="professional"; WANT_TOC=0; TOC_DEPTH=2; MERMAID="vertical"
while [ $# -gt 0 ]; do
  case "$1" in
    --style)     STYLE="$2"; shift 2 ;;
    --toc)       WANT_TOC=1; shift ;;
    --no-toc)    WANT_TOC=0; shift ;;
    --toc-depth) TOC_DEPTH="$2"; shift 2 ;;
    --mermaid)   MERMAID="$2"; shift 2 ;;
    -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
    -*)          echo "unknown option: $1" >&2; exit 2 ;;
    *)           if [ -z "$SRC_IN" ]; then SRC_IN="$1"; else OUT="$1"; fi; shift ;;
  esac
done

[ -n "$SRC_IN" ] || { echo "usage: build_pdf.sh SOURCE.md [OUTPUT.pdf] [options]" >&2; exit 2; }
[ -f "$SRC_IN" ] || { echo "source not found: $SRC_IN" >&2; exit 1; }

for t in pandoc mmdc weasyprint; do
  command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }
done

# Work from the source file's directory so relative <img src="img/..."> still resolve.
SRC_ABS="$(cd "$(dirname "$SRC_IN")" && pwd)/$(basename "$SRC_IN")"
cd "$(dirname "$SRC_ABS")"
SRC="$(basename "$SRC_ABS")"
OUT="${OUT:-$(basename "$SRC" .md).pdf}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- preprocess
python3 - "$SRC" "$WORK/doc.md" "$MERMAID" "$WORK" <<'PY'
import re, struct, subprocess, sys

src, dst, mermaid_mode, work = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src, encoding="utf-8").read()

# --- Mermaid: render, and pick the orientation that stays legible ----------
# A horizontal chain is fine on screen and too small on paper: A4's text column
# is ~17cm, so a 5:1 diagram is scaled to about a quarter and its labels stop
# being readable. Which orientation wins is not guessable from node count -- a
# vertical version can be so tall that the height cap shrinks it right back.
#
# So render both and measure. The objective is the scale factor the page will
# actually apply, min(width_fit, height_fit); whichever orientation keeps the
# larger one keeps the bigger text. Vertical costs page height, which is the
# cheaper resource. `--mermaid keep` opts out entirely.
PAGE_W_PX = 643      # 17cm text column at 96dpi
PAGE_H_PX = 640      # CSS img max-height
flipped = rendered = 0

def png_size(path):
    with open(path, "rb") as f:
        return struct.unpack(">II", f.read(26)[16:24])

def render(body, tag):
    mmd, png = f"{work}/{tag}.mmd", f"{work}/{tag}.png"
    open(mmd, "w", encoding="utf-8").write(body)
    r = subprocess.run(["mmdc", "-i", mmd, "-o", png, "-b", "white", "--scale", "3"],
                       capture_output=True)
    if r.returncode != 0:
        return None
    try:
        return png, png_size(png)
    except Exception:
        return None

def fit(size):
    w, h = size
    return min(PAGE_W_PX / w, PAGE_H_PX / h)

def handle(m):
    global flipped, rendered
    body = m.group(1)
    rendered += 1
    tag = f"d{rendered}"
    base = render(body, tag)
    if base is None:
        return m.group(0)          # let it through as a code block rather than lose it
    png, size = base
    horizontal = re.match(r"^\s*(flowchart|graph)\s+LR\b", body)
    if mermaid_mode == "vertical" and horizontal:
        alt_body = re.sub(r"^(\s*)(flowchart|graph)\s+LR\b", r"\1\2 TD", body, count=1, flags=re.M)
        alt = render(alt_body, tag + "v")
        if alt and fit(alt[1]) > fit(size):
            png = alt[0]
            flipped += 1
    # Alt text must stay empty: pandoc promotes a non-empty alt into a figure
    # caption, so every diagram would print the word "diagram" underneath it.
    return f"![]({png})"

s, total = re.subn(r"```mermaid\n(.*?)```", handle, s, flags=re.S)

# --- H1 -> pandoc metadata title ------------------------------------------
# Must be removed from the body, not hidden with {.unlisted}: the H1 is the TOC's
# only top-level entry and everything else nests under it, so marking it unlisted
# deletes the entire tree and the contents page comes out empty.
m = re.search(r"^# (.+)$", s, flags=re.M)
title = m.group(1).strip() if m else ""
if m:
    s = s[:m.start()] + s[m.end():].lstrip("\n")

# --- Version line -> per-page footer --------------------------------------
mv = re.search(r"^> *(?:版本|Version)[：:] *(.+)$", s, flags=re.M)
version = mv.group(1).strip() if mv else ""
if mv:
    s = s[:mv.start()] + s[mv.end():].lstrip("\n")

open(dst, "w", encoding="utf-8").write(s)
open(dst + ".title", "w", encoding="utf-8").write(title)
open(dst + ".version", "w", encoding="utf-8").write(version)

print(f"title: {title or '(none)'}")
print(f"version footer: {version or '(none — no `> Version:` line found)'}")
print(f"mermaid: {total} diagram(s), {flipped} turned vertical for legibility")
PY

# -------------------------------------------------------------------- styles
case "$STYLE" in
  professional) ACCENT="#1a3a5c"; ACCENT2="#2c5480"; RULE="#c8d4e0"; ZEBRA="#f4f7fa"; BODY_PT="10.5pt"; TBL_PT="9.5pt" ;;
  technical)    ACCENT="#8a4b08"; ACCENT2="#a9631a"; RULE="#e0d2c0"; ZEBRA="#faf6f1"; BODY_PT="10pt";   TBL_PT="9pt" ;;
  minimal)      ACCENT="#000000"; ACCENT2="#333333"; RULE="#cccccc"; ZEBRA="#f5f5f5"; BODY_PT="10.5pt"; TBL_PT="9.5pt" ;;
  *) echo "unknown --style: $STYLE (professional|technical|minimal)" >&2; exit 2 ;;
esac
if [ "$STYLE" = "minimal" ]; then TH_BG="#ffffff"; TH_FG="#000000"; else TH_BG="$ACCENT"; TH_FG="#ffffff"; fi

cat > "$WORK/style.css" <<CSS
@page { size: A4; margin: 2cm; @bottom-center { content: counter(page); font-size: 9pt; color: #888; } }
__VERSION_FOOTER__

/* NEVER add "Apple Color Emoji" to this font-family, at any position. It carries
   keycap glyphs for 0-9, and weasyprint will route every Arabic numeral in the
   document to it -- they then print as blank space. The text layer still contains
   the digits, so the damage is invisible until someone looks at the paper.
   For coloured status markers, embed a PNG instead of relying on emoji glyphs. */
body { font-family: "Heiti TC","PingFang TC","Arial Unicode MS",sans-serif; font-size: $BODY_PT; line-height: 1.65; color: #222; }
h1 { color: $ACCENT; font-size: 20pt; border-bottom: 3px solid $ACCENT; padding-bottom: 8px; }
h2 { color: $ACCENT; font-size: 15pt; margin-top: 1.6em; border-bottom: 1px solid $RULE; padding-bottom: 4px; page-break-after: avoid; }
h3 { color: $ACCENT2; font-size: 12.5pt; margin-top: 1.2em; page-break-after: avoid; }
h4 { color: $ACCENT2; font-size: 11pt; page-break-after: avoid; }

/* table-layout: fixed is what makes the separator-row dash ratios (which pandoc
   emits as <col style="width:N%">) actually bind. Ratios alone are a silent
   no-op; run scripts/table_widths.py to compute them from cell contents. */
table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: $TBL_PT; page-break-inside: auto; table-layout: fixed; }
td, th { word-wrap: break-word; overflow-wrap: break-word; }
thead { display: table-header-group; }
tr { page-break-inside: avoid; }
th { background-color: $TH_BG; color: $TH_FG; padding: 7px 9px; text-align: left; font-weight: 600; border-bottom: 2px solid $RULE; }
td { padding: 6px 9px; border-bottom: 1px solid $RULE; vertical-align: top; }
tr:nth-child(even) td { background-color: $ZEBRA; }

blockquote { border-left: 4px solid $ACCENT2; background: $ZEBRA; margin: 1em 0; padding: 0.6em 1em; color: #33475b; }
code { font-family: "Menlo","Heiti TC","Arial Unicode MS",monospace; font-size: 9pt; background: #eef1f5; padding: 1px 4px; border-radius: 3px; }
pre { white-space: pre-wrap; word-wrap: break-word; background: #f6f8fa; padding: 10px; border-radius: 4px; }
pre code { background-color: transparent; padding: 0; }
img { max-width: 100%; max-height: 640px; display: block; margin: 1em auto; }
/* Tall portrait diagrams need more headroom than the default; A4's text area is
   25.7cm high, so leave room for the heading that precedes it.
   Use a class, not img[src*="..."]: --pdf-engine base64-inlines images, so the
   src becomes data:image/png;... and attribute selectors never match. */
img.tall { max-height: 23cm; }
a { color: $ACCENT2; text-decoration: none; }
ul, ol { padding-left: 1.6em; }
li { margin: 0.25em 0; }

/* Contents page. weasyprint supports target-counter() for real page numbers and
   leader('.') for the dot fill. pandoc --toc emits <nav id="TOC">. */
h1.title { color: $ACCENT; font-size: 20pt; font-weight: 700; border-bottom: 3px solid $ACCENT; padding-bottom: 8px; margin-bottom: 1.4em; }
__TOC_PAGE__
nav#TOC::before {
  content: "__TOC_LABEL__";
  display: block; color: $ACCENT; font-size: 15pt; font-weight: 700;
  border-bottom: 1px solid $RULE; padding-bottom: 4px; margin-top: 1.6em; margin-bottom: 1em;
}
nav#TOC ul { list-style: none; padding-left: 0; margin: 0; }
nav#TOC > ul > li { margin-top: .5em; font-weight: 600; }
nav#TOC ul ul { padding-left: 1.4em; margin-top: .2em; }
nav#TOC ul ul li { font-weight: 400; font-size: 10pt; }
nav#TOC a { color: #222; text-decoration: none; }
nav#TOC a::after { content: leader('.') target-counter(attr(href), page); color: #8a97a5; font-weight: 400; }
@page toc { @bottom-center { content: none; } }
CSS

VER="$(cat "$WORK/doc.md.version" 2>/dev/null || true)"
TOC_LABEL="${TOC_LABEL:-Contents}"

python3 - "$WORK/style.css" "$VER" "$WANT_TOC" "$TOC_LABEL" <<'PY'
import sys
path, version, want_toc, label = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
css = open(path, encoding="utf-8").read()

css = css.replace("__VERSION_FOOTER__",
    '@page { @bottom-right { content: "%s"; font-size: 8pt; color: #999; } }' % version.replace('"', "'")
    if version else "")

# A named page forces a break, so the title block and the TOC must share ONE named
# page or they each take a sheet. With no TOC, the title must NOT be on a named
# page at all, or it still gets a sheet to itself in front of a 2-page document.
css = css.replace("__TOC_PAGE__",
    "header#title-block-header { page: toc; }\nnav#TOC { page: toc; page-break-after: always; }"
    if want_toc else "header#title-block-header { margin-top: 0; }")
css = css.replace("__TOC_LABEL__", label)
open(path, "w", encoding="utf-8").write(css)
PY

# -------------------------------------------------------------------- render
# Note the `+` expansion: under `set -u`, bash 3.2 (still the macOS default)
# treats "${arr[@]}" on an empty array as an unbound variable and aborts.
TOC_ARGS=()
[ "$WANT_TOC" = "1" ] && TOC_ARGS=(--toc --toc-depth="$TOC_DEPTH")

pandoc "$WORK/doc.md" \
  ${TOC_ARGS[@]+"${TOC_ARGS[@]}"} \
  --metadata title="$(cat "$WORK/doc.md.title")" \
  --pdf-engine=weasyprint \
  --css="$WORK/style.css" \
  --resource-path=".:$PWD:$WORK" \
  --syntax-highlighting=none \
  -o "$OUT"

echo "wrote: $PWD/$OUT"

# ---------------------------------------------------------------- self-check
# Two different failures, two different thresholds:
#   - a middle page under ~4% ink means a table or diagram was pushed off it
#   - a LAST page holding one or two lines is a trailing orphan. Do NOT exempt
#     the final page from checking: a real tail page is still fairly full, and
#     blanket-skipping it is exactly how a one-line page ships unnoticed.
if command -v pdftoppm >/dev/null; then
  pdftoppm -png -r 80 "$OUT" "$WORK/pg"
  python3 - "$WORK" "$WANT_TOC" <<'PY'
import glob, sys
try:
    from PIL import Image
except ImportError:
    print("(Pillow not installed — skipping ink self-check)"); raise SystemExit
work, want_toc = sys.argv[1], sys.argv[2] == "1"
pages = sorted(glob.glob(work + "/pg-*.png"))
def ink(p):
    im = Image.open(p).convert("L")
    return sum(im.histogram()[:240]) / (im.size[0] * im.size[1]) * 100
thin, orphan = [], None
for i, p in enumerate(pages):
    if i == 0 and want_toc:      # cover + contents is legitimately sparse
        continue
    v = ink(p)
    if i == len(pages) - 1:
        if v < 1.5 and len(pages) > 1:
            orphan = v
    elif v < 4:
        thin.append((i + 1, v))
print(f"{len(pages)} page(s)")
if thin:
    print("WARNING thin pages (something was pushed off):",
          ", ".join(f"p{n} {v:.1f}%" for n, v in thin))
if orphan is not None:
    print(f"WARNING last page is a trailing orphan ({orphan:.2f}% ink) — "
          "shorten the text above it, or fold the closing line into the "
          "preceding block, so the document ends one page earlier")
if not thin and orphan is None:
    print("ink check passed — no thin or orphan pages")
PY
fi
