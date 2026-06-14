# TODO List App MVP — plan.md

Expected prd-breakdown breakdown output for `example_prd.md`. Five vertical slices across three waves, with one blocked_by relation chain (phase-2/3/4 depend on phase-1; phase-5 depends on phase-3).

## Architectural decisions

- Vanilla JavaScript (no framework) — minimize complexity, zero bundle step
- Browser `localStorage` for persistence — single-user, no backend needed
- Single HTML file with inline `<script>` for v1 — keep entire app in one file
- No build pipeline / no npm — directly editable

## Wave 1: Foundation

### Phase 1: App skeleton with add-task flow
**Type**: HITL
**Assignee**: dev@example.com

#### What to build
Single HTML page with input field at top + empty list area below. Pressing Enter (or clicking Add button) adds a task row to the list with `[ ]` checkbox prefix. No persistence yet — refresh clears all state. End-to-end demo: open page, type, see task appear.

#### Acceptance criteria
- [ ] Empty page renders input field at top + empty list area
- [ ] Typing text + pressing Enter adds task row to list with `[ ]` prefix
- [ ] Multiple tasks render in insertion order
- [ ] Refresh clears all (intentional — persistence comes in phase-2)

#### Blocked by
(none)

## Wave 2: Per-slice features (parallelable)

### Phase 2: localStorage persistence
**Type**: HITL
**Assignee**: dev@example.com

#### What to build
Tasks persist across browser refresh via `localStorage`. On page load, render saved state. On any state change (add / toggle / delete / edit), write back to `localStorage`.

#### Acceptance criteria
- [ ] Adding a task triggers `localStorage` write
- [ ] Page refresh restores previously added tasks in original order
- [ ] Cleared `localStorage` results in empty list (no JS errors)

#### Blocked by
- phase-1

### Phase 3: Complete + delete
**Type**: HITL
**Assignee**: dev@example.com

#### What to build
Click checkbox to toggle task between active (`[ ]`) and complete (`[x]`) state. Hover task row reveals `×` icon; clicking `×` permanently deletes.

#### Acceptance criteria
- [ ] Click `[ ]` → becomes `[x]`, persisted via localStorage
- [ ] Click `[x]` → becomes `[ ]`, persisted
- [ ] Hover row → `×` icon visible at right
- [ ] Click `×` → row removed; state persists across refresh

#### Blocked by
- phase-1

### Phase 4: Inline edit
**Type**: HITL
**Assignee**: dev@example.com

#### What to build
Double-click on task text replaces span with `<input>` field pre-filled with current text. Enter saves new text + persists. Esc reverts to original. Click outside the field behaves like Enter.

#### Acceptance criteria
- [ ] Double-click task → text becomes editable input field
- [ ] Enter → saves new text, persists, exits edit mode
- [ ] Esc → reverts to old text, exits edit mode
- [ ] Click outside the input → behaves like Enter

#### Blocked by
- phase-1

## Wave 3: View modes

### Phase 5: Filter tabs (All / Active / Completed)
**Type**: HITL
**Assignee**: dev@example.com

#### What to build
Header row above the input field has three tabs: All, Active, Completed. Click switches view filter. Active tab visually distinct (e.g., underline or bold).

#### Acceptance criteria
- [ ] Default tab = "All"; shows every task
- [ ] "Active" tab → only tasks with `[ ]` shown
- [ ] "Completed" tab → only tasks with `[x]` shown
- [ ] Tab switch is instant (no reload, no flash)
- [ ] Active tab visually distinct from inactive tabs

#### Blocked by
- phase-3
