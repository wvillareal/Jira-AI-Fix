# Failure diagnostics (runtime)

Live failure reports are written to:

`%USERPROFILE%\.jira-ai-automation\logs\failures\<JIRA_KEY>-failure.txt`

Each file records:

- which process/part failed
- why it failed
- root cause
- exit code / stack details when available

On failure the RCA draft under `~\.jira-ai-drafts\<KEY>-rca.md` is **kept** (or
created as a failure marker) and annotated with the same details so automation
does not keep reinvestigating forever.

This folder in the package documents the layout. The install script creates the
live directory under the user profile.
