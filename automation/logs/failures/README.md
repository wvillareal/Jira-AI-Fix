# Failure diagnostics (runtime)

Live failure reports are written to:

`%USERPROFILE%\.jira-ai-automation\logs\failures\<JIRA_KEY>-failure.txt`

Each file records:

- which process/part failed
- why it failed
- root cause
- exit code / stack details when available

This folder in the package documents the layout. The install script creates the
live directory under the user profile.
