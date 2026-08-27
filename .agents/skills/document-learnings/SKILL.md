---
name: document-learnings
description: Lightweight skill to capture solved problems and learnings into simple markdown files. Use after fixing a bug or discovering a useful pattern.
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Bash(mkdir *)
---

# Document Learnings

A lightweight way to document solved problems, bug fixes, and new learnings into searchable markdown files.

## 3-Step Process

### Step 1: Gather Context

Extract from the conversation:
1. **Topic/Symptom:** Brief description of the issue or concept learned
2. **Solution/Takeaway:** What was the fix or the key learning?

If context is missing, ask: "What was the key learning or fix you'd like to document?"

### Step 2: Create File

```bash
mkdir -p docs/learnings
```

Generate filename: `docs/learnings/YYYY-MM-DD-[short-topic].md`

Filename rules:
- Lowercase
- Replace spaces with hyphens
- Truncate to < 50 characters

Write the file using this template:

```markdown
---
date: [YYYY-MM-DD]
topic: [Short Topic]
---

# [Topic/Symptom]

## The Problem / Context
[Clear description of the issue or what was being attempted]

## The Solution / Learning
[Explanation of how it was fixed or the key takeaway]
```

### Step 3: Confirm

```
Saved to: docs/learnings/[filename].md
```

Return control to the user.

## Guidelines

- Create the `docs/learnings/` directory before writing
- Keep documentation concise and to the point
- Do not block the user with excessive questions if the conversation already contains the answer
