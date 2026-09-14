# JIRA-AI-Fix

Canonical package for the **jira-ai-fix** Cursor/Claude skill (analyze + fix i21 Jiras, push a feature branch, author §6 RCA) plus optional **Windows assignment automation** that launches a Cursor Cloud Agent in draft-only mode and saves the RCA locally.

**GitHub:** https://github.com/wvillareal/Jira-AI-Fix

## What’s in this repo

| Path | Purpose |
|------|---------|
| `SKILL.md`, `DRAFT_MODE.md`, `runbook/`, `standards/`, `config/` | Skill package installed under `~/.claude/skills/jira-ai-fix` (and Cursor mirror) |
| `Setup-JiraAiFix.ps1` | Interactive config wizard → `%USERPROFILE%\.jira-ai-config.json` |
| `automation/` | Jira-assign poller → Cloud Agent → `~/.jira-ai-drafts/<KEY>-rca.md` |

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

## Assignment automation (draft RCA only)

See [automation/README.md](automation/README.md).

Flow: Jira assigned to you → Cloud Agent `analyze and fix <KEY>` with `Mode: DRAFT_JIRA_COMMENT` → fix + push branch → **no Jira comment post** → local draft at `~/.jira-ai-drafts\<KEY>-rca.md`.

Later, in a Cursor chat: `post jira comment draft for ST-xxxxx` (show, then confirm).

## Secrets (never commit)

- `%USERPROFILE%\.jira-ai-config.json` — Atlassian / SQL / SSH (from Setup wizard)
- `%USERPROFILE%\.jira-ai-automation\config.json` — Cursor API key
- `%USERPROFILE%\.jira-ai-automation\processed.json` and `logs\` — runtime state

Only `*.example.json` files belong in git.

## License / use

Internal iRely / personal tooling for Wendell. Do not publish customer dumps, tokens, or restored DB paths into this repo.
