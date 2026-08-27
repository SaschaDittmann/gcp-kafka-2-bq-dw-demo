---
name: create-tasks
description: Generates step-by-step task lists in Markdown based on PRDs, ensuring each parent task is a complete vertical slice. Use after a PRD has been created.
argument-hint: "[prd file reference]"
---

# Task List Generation from PRD

Generate detailed, step-by-step task lists based on an existing Product Requirements Document (PRD). Task lists must guide developers through complete vertical implementation where each feature includes code, tests, observability, and documentation.

## Core Principle: Vertical Planning

Each parent task must include:
- Implementation code
- End-to-end tests
- Observability/logging
- Code documentation

**Never bundle all testing and documentation at the end.** Each task should be independently shippable.

## Process

### Phase 1: Read and Analyze

- Read the PRD thoroughly (from `docs/prds/` or as specified by $ARGUMENTS)
- Scan the repository to identify existing components, utilities, or patterns
- Note reusable code paths or conventions

### Phase 2: Generate Parent Tasks

- Create 4–6 high-level parent tasks mapping to PRD goals and requirements
- Each parent task represents a complete vertical slice
- Present them to the user in Markdown without sub-tasks
- Tell the user: "I have generated the high-level tasks. Ready to generate the sub-tasks? Respond with 'Go' to proceed."

### Phase 3: Wait for Confirmation

- **MUST wait for the user to respond with "Go"**
- Do not proceed to sub-tasks without explicit confirmation

### Phase 4: Detailed Breakdown

- Break each parent task into actionable sub-tasks
- Include implementation + testing + observability + docs in each slice
- Identify potential files (new or existing) that need creation or modification

### Phase 5: Save Output

- Save as `tasks-[prd-file-name].md` in `/docs/tasks/` directory

## Output Format

```markdown
## Relevant Files

- `path/to/file.py` - Brief description of purpose
- `tests/test_file.py` - Tests for file.py

### Notes

- Each parent task represents a complete vertical slice (code + tests + observability + docs)

## Tasks

- [ ] 1.0 Parent Task Title (Complete Vertical Slice)
  - [ ] 1.1 [Implementation sub-task]
  - [ ] 1.2 [Testing sub-task for 1.1]
  - [ ] 1.3 [Observability sub-task]
  - [ ] 1.4 [Documentation sub-task]
- [ ] 2.0 Parent Task Title (Complete Vertical Slice)
  - [ ] 2.1 [Implementation sub-task]
  - [ ] 2.2 [Testing sub-task for 2.1]
  - [ ] 2.3 [Observability integration]
```

## File Naming

- Format: `tasks-[prd-file-name].md`
- Location: `/docs/tasks/`
- Example: PRD `prd-data-ingestion.md` → Task list `tasks-prd-data-ingestion.md`
