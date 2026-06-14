# TODO List App MVP — PRD

A worked example PRD used as input to the prd-breakdown skill. Pair with `example_plan.md` in this directory to see the expected breakdown output.

## Vision

A minimal personal TODO list web app for individuals tracking daily tasks. Single-user, no auth, no collaboration. Works in any modern browser.

## Goals

- 5-second add-task workflow (open page → type → Enter → done)
- State persists across browser refresh
- Works on mobile (read + check-off)
- Zero infrastructure cost (static hosting, no backend)

## Non-goals

- Multi-user / team collaboration
- Native mobile app
- Notifications / reminders
- Subtasks / tags / due dates / priorities

## User flows

### Flow 1: Add a task
User opens app → types task in input field → presses Enter → task appears in list with `[ ]` checkbox prefix.

### Flow 2: Complete a task
User clicks `[ ]` → checkbox toggles to `[x]`. State persists.

### Flow 3: Delete a task
User hovers row → `×` icon appears → click `×` → task removed permanently.

### Flow 4: Edit a task
User double-clicks task text → text becomes editable inline → Enter saves, Esc cancels.

### Flow 5: Filter view
Header has three tabs: All / Active / Completed. Click switches view; only matching tasks shown.

## Architecture sketch

- Single-page web app (vanilla JavaScript, no framework)
- Browser `localStorage` for persistence
- Single HTML file with inline `<script>` for v1
- Static hosting (e.g., GitHub Pages, Netlify, S3)

## Out of scope (v1)

- Drag-and-drop reorder
- Search / sort
- Export / import
- Cloud sync across devices
