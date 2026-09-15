# Jira-assign → local Desktop `jira-ai-fix` (Cursor SDK)

Part of [wvillareal/Jira-AI-Fix](https://github.com/wvillareal/Jira-AI-Fix). Live copies run from
`%USERPROFILE%\.jira-ai-automation\` after `Install-ToUserProfile.ps1`.

## What it does

**Default (`mode: local`):** when a Jira bug is assigned to you, the **hidden** scheduled poller:

1. Detects the assignment via Jira REST
2. Starts a **local Cursor agent on your PC** (Cursor SDK) with prompt:

   ```text
   jira-ai-fix <KEY>

   Mode: DRAFT_JIRA_COMMENT
   ```

3. Loads your real skill from `~\.cursor\skills\jira-ai-fix` (`settingSources: user`)
4. Uses `i21.repoRoot` (e.g. `C:\i21Source`) so local clones / SQL / config apply
5. Implements and validates a fix when appropriate, then commits it to a local feature branch without pushing
6. Immediately emails and toasts that the investigation started, including the Jira's current status
7. Saves the RCA draft to `~\.jira-ai-drafts\<KEY>-rca.md`
8. Emails the completed draft, or sends a failure email if the run stops early

Before launching the agent, the poller records the Jira as `in-progress`. This prevents duplicate
launches and start emails. If Windows interrupts the run, the next poll recovers it and sends an
`Investigation resumed` email.

Before fetching Jira details or starting an investigation, the poller also checks for
`~\.jira-ai-drafts\<KEY>-rca.md`. If that draft already exists, the Jira is treated as
previously investigated and skipped. Delete the draft first only when a fresh investigation
is intentionally required.

If an investigation fails, the poller **keeps** any RCA draft and appends an
`Automation failure` section (or creates a failure draft marker if none exists).
It also writes `~\.jira-ai-automation\logs\failures\<KEY>-failure.txt`. Because the
draft remains, the next poll skips that Jira and will not investigate forever.
Delete the draft only when you intentionally want a fresh run.

The local runner retries stall/AbortError failures up to 3 attempts. After final
failure it preserves the draft and records the failed part, why, and root cause.

Cloud Cursor Agents are **not** used.

**Fallback (`mode: notify`):** toast + clipboard only — you paste into Desktop yourself.

## Setup

1. Node.js on PATH; `CURSOR_API_KEY` user env (Cursor Dashboard → API Keys).
2. `Install-ToUserProfile.ps1` (copies scripts + `local-runner`, runs `npm install`).
3. `"mode": "local"` in `%USERPROFILE%\.jira-ai-automation\config.json`.
4. Hidden scheduled task:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Install-ScheduledTask.ps1" -IntervalMinutes 5
```

## Manual

```powershell
# Full local agent for one key (long-running)
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Invoke-JiraAssignPoller.ps1" -IssueKey ST-13297

# Or call the runner directly
node "$env:USERPROFILE\.jira-ai-automation\local-runner\run-jira-ai-fix.mjs" --jira ST-13297
```

## Files

| Path | Purpose |
|------|---------|
| `automation/local-runner/` | Node + `@cursor/sdk` runner |
| `~\.jira-ai-drafts\<KEY>-rca.md` | section 6 draft |
| `~\.jira-ai-automation\logs\` | poller + local-runner logs |
| `~\.jira-ai-automation\logs\failures\<KEY>-failure.txt` | failure diagnostics |
