# AI Skills That Actually Do Things

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[正體中文](README_zh.md)

A collection of reusable AI agent skills for benchmarking, local search, and project publishing. Works with any LLM client that supports skill/prompt loading — cloud or local.

> Skills follow the [Claude Code skill convention](https://code.claude.com/docs/en/skills) (SKILL.md + scripts/), but the concepts are framework-agnostic.

## Skills

| Skill | Description |
|-------|-------------|
| [prep-repo](prep-repo/) | Prepare a project for GitHub: README conventions, commit style, sensitive data scan, broken link check |
| [llm-benchmark](llm-benchmark/) | Automated Ollama model benchmark with CPU offload detection and markdown report generation |
| [searxng](searxng/) | Local search integration via SearXNG for OpenClaw or any exec-based AI agent |

## Installation

Clone this repo, then copy the skills you need:

```bash
git clone https://github.com/KerberosClaw/kc_ai_skills.git

# Example: install for Claude Code (user-level)
cp -r kc_ai_skills/prep-repo ~/.claude/skills/

# Example: install for OpenClaw (workspace-level)
cp -r kc_ai_skills/searxng ~/.openclaw/workspace/skills/
```

> **Naming tip:** Feel free to rename the skill folder with your own prefix when copying (e.g. `my_prep-repo`).

> **Other clients:** Each SKILL.md is a self-contained markdown instruction file. You can paste its content into any AI chat, system prompt, or custom instruction field.

## Skill Structure

Each skill follows a simple convention:

```
skill-name/
├── SKILL.md          # Frontmatter (name, description, version) + instructions
└── scripts/          # Executable scripts (optional)
    └── script.py
```

## Related Projects

- [kc_tradfri_mcp](https://github.com/KerberosClaw/kc_tradfri_mcp) — IKEA TRADFRI MCP Server for AI smart home control
- [kc_openclaw_local_llm](https://github.com/KerberosClaw/kc_openclaw_local_llm) — OpenClaw + local LLM guide with 13 models tested
