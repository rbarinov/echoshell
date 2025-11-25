---
description: Commit changes with conventional commits, optionally bump version and push
argument-hint: "commit message (optional)"
---

Please help me commit the current changes following this workflow:

## Step 1: Review Changes
First, show me:
- Git status (staged and unstaged files)
- Git diff summary of changes

## Step 1.5: Verify Same-Version Policy
Check that all package.json files have the same version:
- Read `./package.json` (root)
- Read `./laptop-app/package.json`
- Read `./tunnel-server/package.json`

If versions don't match:
- **STOP and report the discrepancy**
- Ask: "Versions are out of sync. Sync all to root version before proceeding?"
- If yes: Update all workspace packages to match root version
- If no: Abort commit

## Step 2: Version Bump Decision (BEFORE commit)
Ask me: "Do you want to bump the version? (Options: major/minor/patch/none)"

Parse $ARGUMENTS for version hints (e.g., "patch version", "minor bump", "major release").

## Step 3: Create Commit Message
Create a commit message following Conventional Commits format:
- `<type>(<scope>): <subject>`
- Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
- Subject: imperative, present tense, no capital first letter, no period at end

Parse $ARGUMENTS for commit message if provided.

Show me the proposed commit message and wait for confirmation.

## Step 4: Stage and Commit
### If version bump requested:
- **First, sync workspace packages BEFORE npm version:**
  - Stage all changes: `git add .`
  - Read current version from `./package.json`
  - Update `./laptop-app/package.json` to match current version
  - Update `./tunnel-server/package.json` to match current version
  - Stage workspace packages: `git add laptop-app/package.json tunnel-server/package.json`
- **Then run npm version with --no-git-tag-version flag:**
  - Run: `npm version <type> --no-git-tag-version`
  - This updates root package.json WITHOUT creating commit or tag
- **Sync workspace packages to new version:**
  - Read new version from `./package.json`
  - Update `./laptop-app/package.json` to match new version
  - Update `./tunnel-server/package.json` to match new version
  - Stage all: `git add .`
- **Create single commit with tag:**
  - Commit: `git commit -m "commit message"`
  - Create tag: `git tag v<new-version>`
- **Result:** ONE commit with all packages synced + ONE tag pointing to correct commit

### If no version bump:
- Stage all changes: `git add .`
- Create commit: `git commit -m "commit message"`

## Step 5: Push
Ask me: "Push to remote? (yes/no)"

Parse $ARGUMENTS for push hints (e.g., "and push", "push after").

If yes:
- Use `git push --follow-tags` which pushes commits and any tags that point to them
- This ensures version tags are pushed automatically if they exist

## Important Rules
- MUST follow Conventional Commits specification
- All commit messages in English only
- **SAME-VERSION POLICY**: All packages must have identical version numbers
- Verify version sync BEFORE committing
- **CRITICAL**: Use `npm version --no-git-tag-version` to avoid orphaned tags
- Sync workspace packages BEFORE and AFTER version bump
- Create commit and tag manually AFTER all packages are synced
- Never use `git commit --amend` after `npm version` (causes tag misalignment)
- Version bump decision BEFORE creating commit (not after)
- Use `--follow-tags` when pushing to handle tags correctly
- Let me confirm before each step (version, commit, push)
