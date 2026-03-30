---
name: prep-repo
description: "Prepare a project for GitHub: README, commit conventions, sensitive data scan, broken link check, project structure, tests, CI, Docker, and final cleanup."
version: 2.0.0
---

# Prep Repo

Prepare a local project for publishing to GitHub. Run through all checks and fix issues found.

## Checklist

### 1. README

- [ ] `README.md` exists with an **engaging, descriptive title** (not the repo/folder name — e.g. "Job Radar -- Because Life's Too Short to Browse 104 Manually" instead of "kc_job_radar")
- [ ] `README_zh.md` exists (Traditional Chinese version)
- [ ] `README.md` has `[正體中文](README_zh.md)` link (not 繁體中文、繁體中文版 etc.)
- [ ] `README_zh.md` has `[English](README.md)` link (not English Version etc.)
- [ ] Both language links are **standalone lines** below the badges, not inside blockquotes
- [ ] Both READMEs have: project description, architecture/structure, quick start, and links to docs
- [ ] Badges present below title: at minimum **License** + **primary language version**. Common badges:
  - `[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)`
  - `[![Python 3.12+](https://img.shields.io/badge/Python-3.12+-blue.svg)](https://www.python.org/)`
  - `[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg)](https://www.docker.com/)`
  - CI badge if GitHub Actions exists
- [ ] **Security Notice** section exists (what external services are used, how credentials are handled, how to report issues)

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
- [ ] No redundant wrapper patterns in headers — e.g. `（又名「...」）` or `(a.k.a. "...")` should be simplified to just the quoted text

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

### 11. Project Directory Structure

Root directory should only contain entry-point files and config. Documentation and assets go in `docs/`.

```
project/
├── src/ or main code      # Source code
├── tests/                 # Automated tests
├── docs/                  # Design docs, guides, images
│   ├── images/            # Screenshots, architecture diagrams
│   └── DESIGN.md          # Design document (not in root)
├── .github/workflows/     # CI pipeline
├── README.md              # Entry-point docs stay in root
├── README_zh.md
├── LICENSE
├── .gitignore
├── .gitattributes
├── pyproject.toml / package.json
├── Dockerfile (if applicable)
└── docker-compose.yml (if applicable)
```

- [ ] No documentation files (DESIGN.md, guides, etc.) floating in root — move to `docs/`
- [ ] `docs/images/` exists if project has screenshots or diagrams
- [ ] Root contains only: README*, LICENSE, config files, entry-point scripts

### 12. README Tree vs Actual Directory

The project structure tree in README must match reality.

- [ ] Every file/directory listed in README tree actually exists
- [ ] No existing important directories omitted from tree (e.g. `tests/`, `docs/`, `.github/`)

```bash
# Compare: extract directory names from README tree, check each exists
```

### 13. Tests & CI

- [ ] `tests/` directory exists and contains test files
- [ ] Tests can run successfully (`pytest`, `npm test`, etc.)
- [ ] `.github/workflows/` exists with at least one CI workflow
- [ ] CI workflow runs tests on push/PR to main

### 14. .gitattributes & Language Detection

- [ ] `.gitattributes` exists
- [ ] Lock files marked as generated to prevent language misdetection

Common rules:
```gitattributes
uv.lock linguist-generated=true
package-lock.json linguist-generated=true
pnpm-lock.yaml linguist-generated=true
yarn.lock linguist-generated=true
poetry.lock linguist-generated=true
```

### 15. Docker Build Verification (if applicable)

If project has a `Dockerfile` or `docker-compose.yml`:

- [ ] `docker build` completes without errors
- [ ] `docker compose up` starts all services successfully
- [ ] Services are reachable (health check or basic connectivity test)
- [ ] Common pitfalls checked:
  - Files referenced in `COPY` actually exist at that build stage
  - Multi-stage builds don't miss required files
  - Build args and env vars have sensible defaults

### 16. GitHub Repo Metadata (post-push)

After pushing to GitHub, verify:

- [ ] **Description** is set (the one-line summary shown on repo cards and search results)
- [ ] **Topics** are set (tags like `python`, `modbus`, `mcp` — helps discoverability)

```bash
# Set description
gh repo edit OWNER/REPO --description "one-line summary"

# Set topics
gh repo edit OWNER/REPO --add-topic python --add-topic modbus --add-topic mcp-server
```

- [ ] Language badge is displaying correctly (should reflect primary language, not lock files)

## Execution

Run through each section. For each issue found:
1. Show the issue
2. Fix it
3. Verify the fix

After all checks pass, stage and commit with: `Docs: prep repo for GitHub publish`

For post-push checks (section 16), run after the repo is on GitHub.
