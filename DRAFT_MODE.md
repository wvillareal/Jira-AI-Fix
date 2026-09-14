# DRAFT_JIRA_COMMENT mode

When the user prompt contains `DRAFT_JIRA_COMMENT` or `Mode: DRAFT_JIRA_COMMENT`:

## Do

1. Follow `runbook/JIRA-AI-Fix.md` end-to-end: analyze, implement the fix, push
   `<TARGET_BRANCH>_<JIRA>` (or the runbook's feature-branch naming).
2. **Author** the Jira comment body using **§6** of `runbook/JIRA-AI-Fix.md`
   (Root Cause Analysis / Acceptance Verification, `RCA_CONTRACT_VERSION = 1.0.0`)
   exactly as for a live post — same block register, Acceptance Verification entries,
   and honesty rules.
3. At the end of the run, emit **exactly one** fenced block:

````markdown
```jira-rca-draft
# Root Cause Analysis
...full section 6 body...
```
````

4. When running **locally** (Desktop / local agent), also write the same body to:

   `%USERPROFILE%\.jira-ai-drafts\<JIRA_KEY>-rca.md`

## Do not

- Post any comment to Jira (no Atlassian MCP `addCommentToJiraIssue`, no REST comment).
- Create a pull request (unchanged from the base skill).
- Invent a shorter custom comment template — reuse section 6 only.
- Emit multiple `jira-rca-draft` fences.

## Later posting

A human (or a later chat) posts the draft with a prompt like:

`post jira comment draft for ST-13291`

Read `%USERPROFILE%\.jira-ai-drafts\ST-13291-rca.md`, show it, and post only after
confirmation unless the user explicitly says to post without confirming.
