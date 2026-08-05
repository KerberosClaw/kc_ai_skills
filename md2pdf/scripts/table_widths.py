#!/usr/bin/env python3
"""Rewrite markdown table separator rows so dash counts encode per-column width ratios.

Why this exists
---------------
pandoc's DEFAULT markdown reader turns the dash proportions in a table's separator
row into `<col style="width:N%">`. That only has any visible effect when the CSS
also sets `table-layout: fixed`. Both halves are required:

    |---|------------|          <- ratio lives here (markdown)
    table { table-layout: fixed }  <- enforcement lives here (CSS)

With the usual `|---|---|---|`, every column is equal width, so a one-character
"#" column gets as much room as a column holding three sentences. On a
table-heavy document that wastes a large fraction of every page.

Two gotchas this script handles
-------------------------------
1. CJK characters occupy two cells, so column weight is measured in display
   width, not `len()`.
2. `word-wrap: break-word` will split a Latin word mid-token when its column is
   too narrow (e.g. "PostgreSQL" -> "PostgreS / QL"). Each column therefore gets
   a floor wide enough for its longest unbreakable token.

Usage
-----
    python3 table_widths.py FILE.md [FILE.md ...]

Rewrites in place. Idempotent: running it twice produces the same result, because
ratios are recomputed from cell contents, not from the previous separator row.

Caveat: pandoc's `gfm` reader ignores separator-row proportions entirely. If the
build passes `-f gfm`, drop that flag or this script has no effect.
"""

import re
import sys
import unicodedata

TOTAL_DASHES = 110      # ~= full text width; only ratios matter, not the absolute
POWER = 0.62            # <1 compresses extremes so one long column can't crush the rest
MIN_DASHES = 3
TOKEN_FACTOR = 1.5      # empirical: dashes needed per char of an unbreakable token
TOKEN_PAD = 5           # plus cell padding, in dashes


def display_width(text):
    """Width in terminal cells, ignoring markdown emphasis and inline HTML."""
    text = re.sub(r"\*\*|`|<[^>]+>", "", text)
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def longest_token(texts):
    """Longest unbreakable run of Latin/digits across the given cells."""
    best = 0
    for t in texts:
        t = re.sub(r"\*\*|`|<[^>]+>", "", t)
        for tok in re.findall(r"[A-Za-z0-9][A-Za-z0-9._+-]*", t):
            best = max(best, len(tok))
    return best


def split_row(line):
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in re.split(r"(?<!\\)\|", s)]   # keep escaped \| intact


def is_separator(line):
    s = line.strip()
    return bool(s.startswith("|") and re.fullmatch(r"\|[\s:\-|]+\|", s) and "-" in s)


def rewrite(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    out, i, count = [], 0, 0

    while i < len(lines):
        if i + 1 < len(lines) and lines[i].strip().startswith("|") and is_separator(lines[i + 1]):
            header = split_row(lines[i])
            ncol = len(header)

            body, j = [], i + 2
            while j < len(lines) and lines[j].strip().startswith("|") and not is_separator(lines[j]):
                row = split_row(lines[j])
                if len(row) == ncol:
                    body.append(row)
                j += 1

            weights, floors = [], []
            for c in range(ncol):
                cells = [display_width(header[c])] + [display_width(r[c]) for r in body]
                # average drives the ratio; max keeps a column with one long cell from being starved
                weights.append(0.7 * (sum(cells) / len(cells)) + 0.3 * max(cells))
                tok = longest_token([header[c]] + [r[c] for r in body])
                floors.append(max(MIN_DASHES, round(tok * TOKEN_FACTOR) + TOKEN_PAD) if tok else MIN_DASHES)

            adjusted = [max(w, 1) ** POWER for w in weights]
            total = sum(adjusted)
            dashes = [max(floors[c], round(TOTAL_DASHES * adjusted[c] / total)) for c in range(ncol)]

            old = split_row(lines[i + 1])
            sep = []
            for c in range(ncol):
                marker = old[c] if c < len(old) else "---"
                left, right = marker.startswith(":"), marker.endswith(":")
                sep.append((":" if left else "") + "-" * dashes[c] + (":" if right else ""))

            out.append(lines[i])
            out.append("|" + "|".join(sep) + "|")
            out.extend(lines[i + 2:j])
            i = j
            count += 1
        else:
            out.append(lines[i])
            i += 1

    open(path, "w", encoding="utf-8").write("\n".join(out))
    return count


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not args or any(a in ("-h", "--help") for a in sys.argv[1:]):
        print(__doc__)
        return 0 if args or "-h" in sys.argv or "--help" in sys.argv else 1
    for path in args:
        print(f"{path}: {rewrite(path)} tables rebalanced")
    return 0


if __name__ == "__main__":
    sys.exit(main())
