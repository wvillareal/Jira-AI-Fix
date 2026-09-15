# JIRA-AI-Fix

Canonical package for the **jira-ai-fix** Cursor/Claude skill (analyze + fix i21 Jiras, push a feature branch, author §6 RCA) plus optional **Windows assignment automation** that detects new Jira assignments and notifies you with the exact Desktop prompt (`jira-ai-fix <KEY>` + `Mode: DRAFT_JIRA_COMMENT`).

**GitHub:** https://github.com/wvillareal/Jira-AI-Fix

## What’s in this repo

| Path | Purpose |
|------|---------|
| `SKILL.md`, `DRAFT_MODE.md`, `runbook/`, `standards/`, `config/` | Skill package installed under `~/.claude/skills/jira-ai-fix` (and Cursor mirror) |
| `Setup-JiraAiFix.ps1` | Interactive config wizard → `%USERPROFILE%\.jira-ai-config.json` |
| `automation/` | Hidden Jira-assign poller → Desktop `jira-ai-fix` notify (Cloud Agents retired) |

## Install the skill

```powershell
git clone https://github.com/wvillareal/Jira-AI-Fix.git C:\Repo\GitHub\Jira-AI-Fix
cd C:\Repo\GitHub\Jira-AI-Fix
powershell -ExecutionPolicy Bypass -File .\Install-ToUserProfile.ps1
powershell -ExecutionPolicy Bypass -File .\Setup-JiraAiFix.ps1
```

`Install-ToUserProfile.ps1` copies the skill into:

- `%USERPROFILE%\.claude\skills\jira-ai-fix`
- `%USERPROFILE%\.cursor\skills\jira-ai-fix`

and the automation scripts into `%USERPROFILE%\.jira-ai-automation` (example config only; your live `config.json` is not overwritten if it already exists).

## Assignment automation

See [automation/README.md](automation/README.md).

**`mode: local` (default):** Jira assigned → hidden poller starts a **local Cursor SDK agent on your PC** with `jira-ai-fix <KEY>` + `Mode: DRAFT_JIRA_COMMENT`, using your real skill under `~\.cursor\skills\jira-ai-fix` and `i21.repoRoot` (e.g. `C:\i21Source`). A validated fix is committed to a local feature branch but never pushed; the RCA is saved to `~\.jira-ai-drafts\<KEY>-rca.md`.

**`mode: notify`:** toast + clipboard only (paste into Desktop yourself).

Requires Node.js and `CURSOR_API_KEY`. Cloud Agents are not used.

## Secrets (never commit)

- `%USERPROFILE%\.jira-ai-config.json` — Atlassian / SQL / SSH (from Setup wizard)
- `%USERPROFILE%\.jira-ai-automation\config.json` — poller / notify settings
- `%USERPROFILE%\.jira-ai-automation\processed.json` and `logs\` — runtime state

Only `*.example.json` files belong in git.

## License / use

Internal iRely / personal tooling for Wendell. Do not publish customer dumps, tokens, or restored DB paths into this repo.
