<!--
ADO work item description body template.
Claude reads this file at push time and substitutes placeholders before
calling `az boards work-item create --fields "System.Description=..."`.

Placeholders:
  {{parent_prd}}         ADO link to parent PRD work item
                         e.g. https://dev.azure.com/your-org/your-project/_workitems/edit/123
  {{description}}        Slice's "What to build" prose (2–4 sentences)
  {{acceptance_criteria}} Markdown checkbox list (one [ ] per AC)
  {{blocked_by}}         Plain phase_id list (e.g. "phase-1, phase-3")
                         Relations are added separately via `az boards work-item relation add`
  {{user_stories}}       Comma-separated ADO IDs (or "(none)")

After substitution, Claude appends the fingerprint marker on a new line:
  <!-- prd-breakdown-id: phase-N-<hash> -->
where hash = sha256(<absolute_plan_md_path> + ":" + <phase_id>)[:8]
-->

**Parent PRD**: {{parent_prd}}

## Description

{{description}}

## Acceptance criteria

{{acceptance_criteria}}

## Blocked by

{{blocked_by}}

## Linked user stories

{{user_stories}}
