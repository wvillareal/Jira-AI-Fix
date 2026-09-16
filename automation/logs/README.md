# Realtime process logs

When an investigation starts, live automation writes a **per-Jira** process log:

`%USERPROFILE%\.jira-ai-automation\logs\MMddyyyy_<JIRA_KEY>.txt`

Example: `09152026_ST-13275.txt`

Poller housekeeping (busy skip, no candidates, lock acquire/release) stays on the dated file:

`%USERPROFILE%\.jira-ai-automation\logs\MMddyyyy.txt`

That dated file also gets a one-line pointer to the per-Jira log when an investigation begins.

Open/tail the per-Jira file to watch that run’s poller + local-runner activity.
Lines are tagged with the Jira key (e.g. `[ST-13275] process: working on ST-13275`).
When a run finishes, the runner writes a short human summary (draft path, models,
handoff highlights) — not the raw JSON blob (JSON stays on stdout for the poller only).
Failures are written into the same per-Jira file (and annotated on the RCA draft).
There are no per-Jira `failures\*.txt` files.
