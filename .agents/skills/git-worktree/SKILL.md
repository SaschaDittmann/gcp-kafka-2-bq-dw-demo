---
name: git-worktree
description: Manages Git worktrees for isolated parallel development. Creates branches, copies .env files, and pushes changes to the remote.
allowed-tools:
  - Bash(git *)
  - Bash(mkdir *)
  - Bash(cp *)
  - Bash(grep *)
  - Read
---

# Git Worktree Workflow

Manage Git worktrees to allow isolated, parallel development. This skill ensures your development environment remains clean.

## Core Rules

1. **Repository Root First:** Always operate from the repository root that contains `.git`
2. **Base Branch:** Every feature branch MUST be based on the `development` branch. All PRs must target `development`
3. **No Script Overkill:** Use standard Git commands to manage the worktree lifecycle

## Step-by-Step Workflow

### 1. Initialize the Worktree Environment

```bash
# From the repository root containing .git
mkdir -p worktrees
# Ensure worktrees/ is ignored
grep -q "^worktrees/" .gitignore || echo "worktrees/" >> .gitignore
```

### 2. Create the Worktree

```bash
git fetch origin development
git worktree add worktrees/feature/<feature-name> -b feature/<feature-name> origin/development
```

Use `bug/<name>` for bug fixes instead of `feature/<name>`.

### 3. Copy Environment Files

```bash
cp .env* worktrees/feature/<feature-name>/ 2>/dev/null || true
```

### 4. Work and Iterate

```bash
cd worktrees/feature/<feature-name>
# Perform development and testing here
```

### 5. Commit and Push

```bash
git add .
git commit -m "feat: <description>"
git push -u origin feature/<feature-name>
```

### 6. Finding Existing Worktrees

```bash
git worktree list
```
