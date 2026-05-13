#!/usr/bin/env python3
"""md2ppt — pre-analyze input.md to give the user a summary before quiz.

Usage:
    md_analyze.py <input.md>

Prints structured summary the SKILL.md Step 1 expects.
"""
import sys
import re
from pathlib import Path


def analyze(md_text):
    lines = md_text.splitlines()
    h1 = None
    h2_titles = []
    h3_count = 0
    code_blocks = {"ascii": 0, "mermaid": 0, "plain": 0}
    table_count = 0
    largest_table_rows = 0
    largest_table_cols = 0
    bullet_list_count = 0

    in_code = False
    code_lang = None
    code_buf = []
    in_bullets = False
    in_table = False
    table_row_buf = 0

    for line in lines:
        if line.startswith("```"):
            if in_code:
                content = "\n".join(code_buf)
                if code_lang == "mermaid":
                    code_blocks["mermaid"] += 1
                elif _looks_like_ascii_art(content):
                    code_blocks["ascii"] += 1
                else:
                    code_blocks["plain"] += 1
                code_buf = []
                in_code = False
                code_lang = None
            else:
                in_code = True
                code_lang = line[3:].strip()
            continue
        if in_code:
            code_buf.append(line)
            continue
        if line.startswith("# ") and h1 is None:
            h1 = line[2:].strip()
            continue
        if line.startswith("## "):
            h2_titles.append(line[3:].strip())
            continue
        if line.startswith("### "):
            h3_count += 1
            continue
        if "|" in line and not in_table:
            in_table = True
            table_row_buf = 1
            cols = len([c for c in line.split("|") if c.strip()])
            largest_table_cols = max(largest_table_cols, cols)
            continue
        if in_table:
            if "|" in line:
                if not re.match(r"^\s*\|[\s\-:|]+\|\s*$", line):
                    table_row_buf += 1
            else:
                table_count += 1
                largest_table_rows = max(largest_table_rows, table_row_buf)
                in_table = False
                table_row_buf = 0
        if re.match(r"^\s*[-*]\s", line) or re.match(r"^\s*\d+\.\s", line):
            if not in_bullets:
                bullet_list_count += 1
                in_bullets = True
        else:
            if in_bullets and not line.strip().startswith(("  ", "\t")):
                in_bullets = False

    if in_table:
        table_count += 1
        largest_table_rows = max(largest_table_rows, table_row_buf)

    return {
        "h1": h1,
        "h2_titles": h2_titles,
        "h3_count": h3_count,
        "tables": table_count,
        "largest_table": (largest_table_rows, largest_table_cols),
        "code_blocks": code_blocks,
        "bullet_lists": bullet_list_count,
        "estimated_slides": 1 + len(h2_titles) + 1,
    }


def _looks_like_ascii_art(text):
    indicators = ["┌", "└", "┐", "┘", "├", "┤",
                  "│", "─", "▶", "►", "→", "──"]
    return any(ind in text for ind in indicators)


def main():
    if len(sys.argv) != 2:
        print("Usage: md_analyze.py <input.md>", file=sys.stderr)
        sys.exit(1)
    md = Path(sys.argv[1]).read_text()
    a = analyze(md)
    print(f"H1 (cover):     {a['h1'] or 'MISSING'}")
    print(f"H2 sections:    {len(a['h2_titles'])}")
    print(f"H3 subsections: {a['h3_count']}")
    print(f"Tables:         {a['tables']} (largest: {a['largest_table'][0]} rows x {a['largest_table'][1]} cols)")
    cb = a["code_blocks"]
    print(f"Code blocks:    {sum(cb.values())} (ASCII art: {cb['ascii']}, mermaid: {cb['mermaid']}, plain: {cb['plain']})")
    print(f"Bullet lists:   {a['bullet_lists']}")
    print(f"Estimated slides: {a['estimated_slides']} (1 cover + {len(a['h2_titles'])} H2 + 1 Q&A)")
    print()
    print("H2 section list:")
    for i, t in enumerate(a["h2_titles"], 1):
        print(f"  {i:2}. {t}")


if __name__ == "__main__":
    main()
