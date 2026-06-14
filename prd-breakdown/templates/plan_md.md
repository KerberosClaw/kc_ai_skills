<!--
plan.md structure reference. Output of prd-breakdown Workflow A (PRD breakdown).
Claude writes plan.md following this shape; push CLI (Workflow B) parses it.

Structure:
- ## Architectural decisions (optional but encouraged) — durable cross-slice
  decisions (tech stack, data model invariant, integration boundary)
- ## Wave N: <label> (optional) — group of slices that can run in parallel
- ### Phase N: <title> (required) — one vertical slice
  - **Type**: HITL | AFK
  - **User stories**: comma-separated ADO IDs (optional)
  - **Assignee**: email (optional, per-slice override of CLI fallback)
  - #### What to build (prose, 2–4 sentences)
  - #### Acceptance criteria (markdown checkbox list)
  - #### Blocked by (phase_id list, or "(none)")

phase_id naming: phase-N where N is sequential (phase-1, phase-2, ...).
blocked_by refs use the same phase_id form.
-->

## Architectural decisions
- <decision 1: e.g. "Vanilla JavaScript, no framework — minimize complexity">
- <decision 2: e.g. "Browser localStorage for persistence, no backend">

## Wave 1: Foundation

### Phase 1: <slice title>
**Type**: HITL
**User stories**: 670, 671
**Assignee**: dev@example.com

#### What to build
<2–4 sentences describing the user-visible end-to-end demo this slice delivers>

#### Acceptance criteria
- [ ] <AC 1: concrete, observable behavior>
- [ ] <AC 2>

#### Blocked by
(none)

## Wave 2: Per-slice features

### Phase 2: <slice title>
**Type**: HITL

#### What to build
<...>

#### Acceptance criteria
- [ ] <...>

#### Blocked by
- phase-1
