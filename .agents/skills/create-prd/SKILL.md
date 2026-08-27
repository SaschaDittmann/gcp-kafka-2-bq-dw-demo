---
name: create-prd
description: Guides the creation of a clear, actionable PRD from a user's feature request by first asking clarifying questions. Use when starting a new feature or when the user wants to define requirements.
argument-hint: "[feature description]"
---

# Product Requirements Document (PRD) Creation Guide

Generate a detailed PRD in Markdown format based on the user's feature request. PRDs must be clear, actionable, and suitable for developers to understand and implement.

## Process

### Phase 1: Clarification

- **Do NOT start writing the PRD immediately**
- ALWAYS ask clarifying questions first
- Provide options in letter/number lists for easy responses
- Cover these areas (adapt as needed):
  1. Problem/goal the feature solves
  2. Target user
  3. Core functionality / key user actions
  4. Acceptance criteria or success metrics
  5. Scope boundaries / non-goals
  6. Data requirements
  7. Edge cases or error conditions
  8. Technical constraints
- Wait for answers, confirm understanding, and loop back with follow-up questions if anything is still fuzzy

### Phase 2: Generation

Create the PRD using the structure below, based on the user's initial prompt and clarifying answers.

### Phase 3: Output

- Save as `prd-[feature-name].md` in `/docs/prds/` directory
- Use Markdown format exclusively

## PRD Structure

Generate the PRD with these sections in order:

1. **Introduction** — Brief feature description, problem it solves, high-level goal
2. **Goals** — Specific, measurable objectives (bullet points, outcomes not features)
3. **User Stories** — Format: "As a [user type], I want to [action] so that [benefit]"
4. **Functional Requirements** — Numbered list, clear and actionable language, explicit and unambiguous
5. **Non-Goals** — What the feature will NOT include, scope boundaries, future considerations
6. **Design Considerations** — UI/UX requirements, mockups, accessibility
7. **Technical Considerations** — Known constraints, dependencies, integration requirements, performance
8. **Success Metrics** — Measurable criteria (quantitative and qualitative)
9. **Open Questions** — Remaining areas needing clarification, dependencies on other decisions

## Writing Guidelines

- Use simple, direct language
- Provide enough context for implementation decisions
- Include examples where helpful
- Be specific about expected behavior
- Avoid ambiguous terms like "intuitive" or "user-friendly"

## Feature Description

$ARGUMENTS
