# DRAFT_JIRA_COMMENT mode

When the user prompt contains `DRAFT_JIRA_COMMENT` or `Mode: DRAFT_JIRA_COMMENT`:

## Do

1. Follow `runbook/JIRA-AI-Fix.md` through analysis, implementation, validation,
   feature-branch creation, and commit. Resolve `TARGET_BRANCH` from the Jira
   **Fix Version** using SKILL.md *Feature-branch base selection*: prefer the
   matching **Dev** branch on origin; if no Dev line exists for that version, use
   the matching **Prod** branch. Then create/reuse
   `FEATURE_BRANCH = <TARGET_BRANCH>_<JIRA>` and **commit** the validated fix
   locally on that feature branch.
   **Do not push.** DRAFT mode replaces the runbook push step: after the feature
   branch exists, commit only — never `git push` or upload the branch.
2. **Author** the Jira comment body using SKILL.md
   [RCA Jira comment shape (this install)](SKILL.md#rca-jira-comment-shape-this-install)
   — **only** Non-technical analysis, Technical analysis, Root cause, and Solution.
   Do not use the full runbook §6 block register in the comment. Prose must be
   **short, direct, and professional** (see SKILL.md *Jira comment voice*).
   Put Module/branch/commit and “committed locally, not pushed” in the conversation
   handoff outside the fence; never claim remote delivery or a successful §5 push.
3. At the end of the run, emit **exactly one** fenced block:

````markdown
```jira-rca-draft
# Root Cause Analysis

**Non-technical analysis:**
...

**Technical analysis:**
...

**Root cause:**
...

**Solution:**
...
```
````

4. When running **locally** (Desktop / local agent), also write the same body to:

   `%USERPROFILE%\.jira-ai-drafts\<JIRA_KEY>-rca.md`

## Do not

- Post any comment to Jira (no Atlassian MCP `addCommentToJiraIssue`, no REST comment).
- Run `git push`, create a remote branch, or otherwise upload the fix to any remote.
- Create a pull request (unchanged from the base skill).
- Expand the RCA draft back to the full runbook §6 register (Acceptance Verification,
  Delivery, footers, etc.).
- Emit multiple `jira-rca-draft` fences.

## Later posting

A human (or a later chat) posts the draft with a prompt like:

`post jira comment draft for ST-13291`

Read `%USERPROFILE%\.jira-ai-drafts\ST-13291-rca.md`, show it, and post only after
confirmation unless the user explicitly says to post without confirming.
