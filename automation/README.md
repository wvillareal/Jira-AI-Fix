# Jira-assign → Cloud Agent → local RCA draft

Part of [wvillareal/Jira-AI-Fix](https://github.com/wvillareal/Jira-AI-Fix). After
`Install-ToUserProfile.ps1`, live copies run from `%USERPROFILE%\.jira-ai-automation\`.

Automates: when a Jira bug is **assigned to you**, start a Cursor **Cloud Agent** with
`analyze and fix <KEY>` in **DRAFT_JIRA_COMMENT** mode (full fix + push, **no Jira comment
post**), then save the section 6 RCA body under:

`%USERPROFILE%\.jira-ai-drafts\<KEY>-rca.md`

## Setup

1. From the repo root: `Install-ToUserProfile.ps1` (or copy these scripts into
   `%USERPROFILE%\.jira-ai-automation`).
2. Ensure `config.json` exists there (copy from `config.example.json` if needed).
3. Set `cursorApiKey` (from [Cursor Dashboard](https://cursor.com/dashboard)) **or** set
   user env `CURSOR_API_KEY` (see `cursorApiKeyEnv`).
4. Confirm `defaultRepo.url` / `startingRef` (and `repoByProject` for ST, etc.) match remotes
   connected to your Cursor Cloud Agents account.
5. Confirm `%USERPROFILE%\.jira-ai-config.json` has working `atlassian.email` + `apiToken` +
   `siteUrl`.
6. Optional: install the scheduled task:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Install-ScheduledTask.ps1" -IntervalMinutes 5
```

## Manual / dry-run

```powershell
# Placeholder draft only (no Cursor API)
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Invoke-JiraAssignPoller.ps1" -DryRun -IssueKey ST-13291

# Live: launch Cloud Agent for one key and wait for §6 draft harvest
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Invoke-JiraAssignPoller.ps1" -IssueKey ST-13291

# Poll Jira for recent assignee-changed Open/Reopened bugs
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-automation\Invoke-JiraAssignPoller.ps1"
```

## Draft location and later posting

| File | Purpose |
|------|---------|
| `~\.jira-ai-drafts\<KEY>-rca.md` | §6 RCA / Acceptance Verification body |
| `~\.jira-ai-drafts\<KEY>-meta.json` | agent id, run id, branch, timestamps |
| `~\.jira-ai-automation\processed.json` | dedupe so the same key is not re-fired |
| `~\.jira-ai-automation\logs\poller-YYYYMMDD.log` | run log |

In a **new Cursor chat**, ask:

`post jira comment draft for ST-13291`

The agent should read the draft file (already §6-shaped), show it, and post to Jira only
after you confirm.

## Skill contract

See `%USERPROFILE%\.claude\skills\jira-ai-fix\DRAFT_MODE.md` (mirrored under `.cursor\skills`).

The Cloud Agent prompt forces `Mode: DRAFT_JIRA_COMMENT` and requires a single
`jira-rca-draft` fence containing the full §6 comment from `runbook/JIRA-AI-Fix.md`.

## Notes / limits

- Cursor cannot open a Desktop Composer chat from Jira; this uses **Cloud Agents** instead.
- Cloud Agents need your repo connected in Cursor; SQL restores on your laptop are not
  available in the cloud VM (same disclosure as the runbook when SQL is unavailable).
- Deduping is permanent until you delete the key from `processed.json`.
- `autoCreatePR` stays `false` (use `create-jira-pr` when you want a PR).
