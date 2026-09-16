# Jira-assign â†’ local Desktop `jira-ai-fix` (Cursor SDK)

Part of [wvillareal/Jira-AI-Fix](https://github.com/wvillareal/Jira-AI-Fix). Live copies run from
`%USERPROFILE%\.jira-ai-automation\` after `Install-ToUserProfile.ps1`.

## What it does

**Default (`mode: local`):** when a Jira bug is assigned to you, the **hidden** scheduled poller:

1. Detects the assignment via Jira REST
2. Starts a **local Cursor agent on your PC** (Cursor SDK) in two model phases:

   - **Phase 1 (`investigateModel`, default `grok-4.5`):** Jira / HDTN / root cause / plan / code
   - **Phase 2 (`wrapUpModel`, default `auto`):** feature branch packaging / RCA draft / wrap-up

3. Loads your real skill from `~\.cursor\skills\jira-ai-fix` (`settingSources: user`)
4. Uses `i21.repoRoot` (e.g. `C:\i21Source`) so local clones / SQL / config apply
5. Implements and validates a fix when appropriate (phase 1), then packages the local feature branch without pushing (phase 2)
6. Immediately emails and toasts that the investigation started, including the Jira's current status
7. Saves the RCA draft to `~\.jira-ai-drafts\<KEY>-rca.md`
8. Emails only that Jira's RCA draft (copy/paste ready for Jira), or a failure email if the run stops early

Before launching the agent, the poller records the Jira as `in-progress`. This prevents duplicate
launches and start emails. If Windows interrupts the run, the next poll recovers it and sends an
`Investigation resumed` email.

**One Jira at a time:** a run lock plus scheduled-task `IgnoreNew` ensure only one
investigation runs. The 5-minute assigned-Jira poll is skipped entirely while automation
is busy (no Jira search, no new launch). Extra candidates are deferred to a later idle poll.

**Stale lock reclaim:** if the lock owner **PID is dead** (or the lock is orphaned
with no live process), the next poller pass reclaims it. A **live** owner is never
auto-reclaimed — even if `current-agent.json` stops updating — because clearing the
lock under a running investigation causes dual runners / connection resets. Use
**`-Force`** on a manual `-IssueKey` run to stop a live owner and take the lock.
Optional `lockStaleMinutes` (default **45**) still gates orphan/heartbeat warnings.

Before fetching Jira details or starting an investigation, the poller also checks for
`~\.jira-ai-drafts\<KEY>-rca.md`. If that draft already exists, the Jira is treated as
previously investigated and skipped. Delete the draft first only when a fresh investigation
is intentionally required.

If an investigation fails, the poller **keeps** any RCA draft and appends an
`Automation failure` section (or creates a failure draft marker if none exists). Failure
details are written into that Jira's realtime process log
`~\.jira-ai-automation\logs\MMddyyyy_<JIRA_KEY>.txt` (example: `09152026_ST-13275.txt`). Because the draft
remains, the next poll skips that Jira and will not investigate forever.

The local runner retries stall/AbortError failures up to **2** attempts. On retry it
prefers `Agent.resume` (same conversation) and, when phase 1 already finished, re-runs
**wrap-up only**. Repeated intake loops (Jira/HDTN/attachments/comments) fail fast as
non-retryable thrash. After final failure it preserves the draft and records the failed
part, why, and root cause in the process log.

Phase 1 prompts also force a **speed triage**: one-pass intake, skip customer DB restore
when the symptom is code-only, and avoid re-fetching the same ticket/attachments.

**Automation MCP:** the local runner passes empty inline `mcpServers` so it does **not**
start `~\.cursor\mcp.json` (npx Confluence / Azure DevOps). That avoids unattended hangs.
Desktop/manual Cursor is unchanged and still uses your normal MCP config.

Cloud Cursor Agents are **not** used.

**Fallback (`mode: notify`):** toast + clipboard only — you paste into Desktop yourself.

## Realtime process log

Each investigation writes its own file:

```text
%USERPROFILE%\.jira-ai-automation\logs\MMddyyyy_<JIRA_KEY>.txt
```

Example for ST-13275 on 15 Sep 2026: `09152026_ST-13275.txt`. Poller events and local-runner
output for that Jira stream into this file as the run progresses.

Poller-only housekeeping (busy skip, empty polls) stays on:

```text
%USERPROFILE%\.jira-ai-automation\logs\MMddyyyy.txt
```

Snapshot of the active agent (updated continuously during a run):

```text
%USERPROFILE%\.jira-ai-automation\current-agent.json
```

## Setup

1. Node.js on PATH; `CURSOR_API_KEY` user env (Cursor Dashboard â†’ API Keys).
2. `Install-ToUserProfile.ps1` (copies scripts + `local-runner`, runs `npm install`).
3. `"mode": "local"` in `%USERPROFILE%\.jira-ai-automation\config.json`
   (optional: `investigateModel` / `wrapUpModel`; `lockStaleMinutes` default `45`).
4. Hidden scheduled task (silent — no PowerShell flash; uses wscript launcher):

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Install-ScheduledTask.ps1" -IntervalMinutes 5
```

## Manual

```powershell
# Full local agent for one key (long-running)
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Invoke-JiraAssignPoller.ps1" -IssueKey ST-13297

# Jump the queue: stop the current investigation and start this key immediately
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Invoke-JiraAssignPoller.ps1" -IssueKey ST-13297 -Force

# Or call the runner directly
node "$env:USERPROFILE\.jira-ai-automation\local-runner\run-jira-ai-fix.mjs" --jira ST-13297
```

## Files

| Path | Purpose |
|------|---------|
| `automation/local-runner/` | Node + `@cursor/sdk` runner |
| `~\.jira-ai-drafts\<KEY>-rca.md` | section 6 draft |
| `~\.jira-ai-automation\logs\MMddyyyy_<JIRA_KEY>.txt` | per-Jira process log while investigating |
| `~\.jira-ai-automation\logs\MMddyyyy.txt` | poller housekeeping + pointer to per-Jira log |
| `~\.jira-ai-automation\current-agent.json` | snapshot of the agent currently running |
