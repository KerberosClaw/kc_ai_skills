---
name: rewrite-tone
description: "Rewrite Markdown files with a conversational, humorous, self-deprecating tone. Turns dry technical docs into engaging war stories. Use when user says 'rewrite', 'change tone', 'make it fun', or similar."
version: 1.0.0
triggers: ["/rewrite-tone", "改寫語氣", "rewrite tone", "寫得好玩點"]
---

# Rewrite Tone

Rewrite the specified Markdown file(s) with a conversational, humorous, self-deprecating engineering tone.

## Tone Guidelines

- **Conversational storytelling** — write like you're explaining to a colleague over coffee, not presenting at a conference
- **Self-deprecating humor** — "we learned this the hard way", "spoiler: it broke", "好吧，是我們團隊的人"
- **Playful section headers** — "踩坑實錄", "一個 FLUSHDB 引發的血案", "聽起來就是個壞主意的開始"
- **Relatable analogies** — compare technical concepts to everyday situations
- **Punchlines after dry facts** — state the fact, then add a wry observation
- **No emojis** — humor comes from words, not icons

## What to Change

- Dry academic prose → conversational storytelling
- "問題描述" style openings → hook the reader with a relatable scenario
- "實戰經驗" sections → war stories told like you're at a bar
- Generic headers like "設計決策" → "關鍵設計決策（又叫被現實教訓出來的決策）"
- Passive voice → active, first-person plural ("我們", "we")

## What to Keep Unchanged

- All code blocks (Python, YAML, bash, etc.)
- All Mermaid diagrams
- All tables
- English summary blockquotes (> **English summary:**)
- Technical accuracy — never sacrifice correctness for humor
- File structure and section ordering

## Language

- Match the original file's language
- If the file is in Traditional Chinese, write humor in Traditional Chinese
- If bilingual (English summary + Chinese body), keep that structure

## Execution

1. Read the target file(s)
2. Rewrite prose sections with the tone guidelines above
3. Verify all code/diagrams/tables are preserved unchanged
4. Write the updated file(s)
