---
name: prep-repo
description: "Prepare a project for GitHub: README, commit conventions, sensitive data scan, broken link check, and final cleanup."
version: 1.0.0
---

# Prep Repo

Prepare a local project for publishing to GitHub. Run through all checks and fix issues found.

## Checklist

### 1. README

- [ ] `README.md` exists with a **human-readable title** (not the repo/folder name)
- [ ] `README_zh.md` exists (Traditional Chinese version)
- [ ] `README.md` has `[正體中文](README_zh.md)` link
- [ ] `README_zh.md` has `[English](README.md)` link
- [ ] Both READMEs have: project description, architecture/structure, quick start, and links to docs
- [ ] Badges (License, etc.) are present if applicable

### 2. Docs (if any)

- [ ] Chinese docs have an **English summary** block at the top (in a `> **English summary:**` blockquote)
- [ ] All internal links are valid (no broken links)

### 3. Naming Conventions

- [ ] Repository/folder uses consistent naming (snake_case preferred)
- [ ] If user has a prefix convention (e.g. `kc_`), verify all repos follow it

### 4. Git Commit Messages

Follow the convention: `Category: lowercase description`

Common categories:
- `Init:` — initial commit
- `Core:` — core functionality changes
- `Docs:` — documentation only
- `fix:` — bug fixes
- `fix(security):` — security fixes
- `Build:` — build/Docker/CI changes
- `Plugins:` — plugin/skill/extension changes

### 5. Files

- [ ] `.gitignore` exists (at minimum: `.DS_Store`, `*.pyc`, `__pycache__/`)
- [ ] `LICENSE` exists
- [ ] No unnecessary files tracked (`.env`, credentials, `.DS_Store`, `__pycache__`)

### 6. Sensitive Data Scan

Scan **all tracked files AND git history** for:
- Real IP addresses (e.g. `192.168.x.x` with actual values)
- API tokens, bot tokens, gateway tokens
- Telegram user IDs, chat IDs
- SSH key paths with usernames
- Tailscale domains
- Real usernames / home directory paths

```bash
# Scan tracked files
grep -rn --exclude-dir=.git --exclude-dir=vendor --exclude-dir=node_modules --exclude-dir=.venv \
  -iE "192\.168\.[0-9]+\.[0-9]+|bot.?token.*[0-9]{9}|chat.?id.*[0-9]{9}" .

# Scan git history
git log --all -p | grep -E "KNOWN_SENSITIVE_VALUES_HERE"
```

If found in git history, use `git filter-repo --replace-text` to rewrite history.

### 7. Co-Authored-By Removal

- [ ] No `Co-Authored-By` lines in any commit messages

```bash
git log --all --format="%B" | grep -i "co-authored"
```

If found, use `git filter-repo --message-callback` to remove.

### 8. Link Validation

- [ ] All internal markdown links point to existing files
- [ ] External URLs are valid (spot check, not exhaustive)

```bash
# Extract and verify internal links
grep -rn '\[.*\](.*\.md\|.*\.py\|.*\.json)' --include="*.md" . | grep -v .git
```

### 9. Markdown Rendering Check

- [ ] No bare `===` or `---` lines outside code blocks (causes heading/hr rendering issues)
- [ ] Nested code blocks use different fence levels (outer ```````` ```````` ````````, inner ```` ``` ````)
- [ ] Report blocks, ASCII art, and formatted text are wrapped in code fences

```bash
# Find bare === lines that may cause rendering issues
grep -n "^===" --include="*.md" -r . | grep -v .git
```

### 10. Skill Directory Structure (if applicable)

Each skill follows:
```
skill-name/
├── SKILL.md              # Frontmatter (name, description, version) + instructions
└── scripts/              # Executable scripts
    └── script.py
```

- [ ] SKILL.md has YAML frontmatter with `name`, `description`, `version`
- [ ] Scripts are in `scripts/` subdirectory
- [ ] No orphan metadata files (`_meta.json` etc.) unless required

## Execution

Run through each section. For each issue found:
1. Show the issue
2. Fix it
3. Verify the fix

After all checks pass, stage and commit with: `Docs: prep repo for GitHub publish`
