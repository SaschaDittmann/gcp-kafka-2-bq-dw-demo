---
name: finalize-tasks
description: Prepares a feature for review — cleans the worktree, resolves conflicts, creates a PR. Use after all tasks for a feature are completed.
allowed-tools:
  - Bash(git *)
  - Bash(gh *)
  - Read
  - Edit
  - Write
---

# Finalize Tasks Workflow

Execute this workflow end to end:

## 1. Collect Context

1. Ask for the task or issue if not known
2. Read the relevant `tasks-*.md` file in `docs/tasks/`
3. Confirm every checkbox for the current task is `[x]`. If not, stop and tell the user to finish implementation first
4. Run `git worktree list` and identify the relevant worktree/branch

## 2. Prepare the Worktree

1. Change into the worktree directory
2. Run `git status` — if unstaged changes exist, include them or ask the user
3. Fetch and merge latest `origin/development`:
   ```bash
   git fetch origin
   git merge origin/development
   ```
4. If merge conflicts appear, attempt to resolve them. If you cannot, pause and ask the user

## 3. Verify Readiness

1. Stage any conflict resolution adjustments
2. Ensure commit messages follow project conventions
3. Update the task file to note the branch is ready for PR

## 4. Create or Update Pull Request

1. Check for existing PR: `gh pr list --head <branch>`
2. If no PR exists:
   ```bash
   gh pr create --base development --head <branch> --title "<concise title>" --body "<summary>"
   ```
3. Record the PR URL

## 5. Update Task File

Update `docs/tasks/` with a link to the PR

## 6. Seek Merge Approval

1. Present the PR to the user with any outstanding checks
2. Only merge when the user explicitly approves ("merge", "yes", "go")

## 7. Merge When Approved

1. Run `gh pr merge <url> --merge --delete-branch=false`
2. If merge fails, surface the error and ask the user

## 8. Report

Summarize: worktrees processed, conflicts resolved, PR URLs, merge status, and any follow-up actions needed.

## Important

- Do not leave worktrees dirty
- `docs/tasks/` files are the single source of truth
- Never skip conflict resolution or testing before creating PRs
