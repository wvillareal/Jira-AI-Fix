---
name: jira-ai-fix
description: >-
  Analyze an i21 JIRA for ANY module (AP, AR, GL, IC, CM, SM, Store, any other),
  prove a root cause against the code and — when the symptom is data-dependent —
  a restored customer database, implement the fix using Reported-Build version
  tiers (≤22.1 SqlScripts + app/server; ≥24.3 Liquibase + universal/web-api)
  under the configured REPO_ROOT, push the `<TARGET_BRANCH>_<JIRA>` feature
  branch, and post the Root Cause Analysis / Developer's Testing comment on the
  Jira. Use whenever a JIRA key is handed over with a request to fix, analyze,
  investigate, review, debug, work, or resolve it — "jira-ai-fix AP-24818",
  "analyze and fix AR-12034", "investigate ST-13228", "review ongoing tickets",
  "run the JIRA-AI-Fix runbook" — even when the runbook is not named. Replaces
  the retired jira-investigate skill. Creates NO pull request and propagates to
  no other branch; it stops after the push and the Jira comment.
---

# JIRA-AI-Fix

The full runbook is [`runbook/JIRA-AI-Fix.md`](runbook/JIRA-AI-Fix.md) in this directory.
Read it in full and follow it from the top — its §-numbered gates are mandatory and ordered.
Do not skip a gate, and do not summarize the runbook instead of executing it.

## Machine overrides (this install)

Apply [Version-tier code locations](#version-tier-code-locations) when choosing the
database repo and Store UI/server paths. These overrides live here so redistributed
packages do not wipe them — do not edit `runbook/JIRA-AI-Fix.md` for this.

Also apply [DRAFT_JIRA_COMMENT mode](DRAFT_MODE.md) when the prompt contains
`DRAFT_JIRA_COMMENT` or `Mode: DRAFT_JIRA_COMMENT`: run through implementation,
validation, feature-branch creation, and a **local commit**, but **never push**.
**Author** the §6 RCA / Acceptance Verification comment, **do not post it to Jira**,
and emit a `jira-rca-draft` fence (and write
`%USERPROFILE%\.jira-ai-drafts\<JIRA_KEY>-rca.md` when running locally).

## Jira comment voice (all comments)

Every Jira comment this skill posts or drafts — §6 RCA / Acceptance Verification,
information request, triage, handoff, and local RCA drafts — must be **short, direct,
and professional**:

- Keep the required §6 block register and honesty rules; compress the **prose inside**
  each block. Do not invent a shorter custom template.
- Prefer short sentences and tight bullets. Cut filler, hedging, narration, and
  throat-clearing (“In order to…”, “It should be noted that…”, long restatements).
- One claim per bullet; evidence factual and minimal. Link or name the artifact once.
- No casual tone, no emoji (unless a runbook marker requires it), no marketing language.
- Ask only for what is missing; state only what was done, found, or blocked.

## Scope, before you read anything else

Two gates decide whether a ticket enters the flow at all. Both are cheap, and both are in
the runbook.

- **Issue type.** In scope: `Bug`, `Bug-QC`, `Bug-UAP`, `Bug-Ongoing UAP`, `Technical Debt`,
  `Performance`, `Data Fix`. Out of scope and a **silent STOP** — no analysis, no branch, no
  label, no Jira comment: `Feature`, `Gap`, `Paid`, `Suggestion`, `Config`.
- **Issue status.** `Open` or `Reopened` only.

Inputs are a **JIRA_KEY** plus optional `TARGET_BRANCH`, `REPO`, `REPO_ROOT` and `APP_ENV`
overrides. The affected repository is resolved from the Jira's own evidence — never assume the
current working directory. For `REPO_ROOT`, see the binding rule below: this machine's value
comes from the config file, not from the runbook's built-in default.

This runbook **creates no pull request and propagates nothing.** It ends after the push and
the Jira comment, with a handoff — **except** in `DRAFT_JIRA_COMMENT` mode, where the
fix is committed only to the local feature branch with no push, and the comment is
authored per §6 but saved as a local draft instead of posted (see
[DRAFT_MODE.md](DRAFT_MODE.md)).

## Distributed copy — read this before following the runbook

This is a **packaged, read-only distribution** of the runbook. Three things about it differ
from the maintainer's working copy, and the runbook text cannot know that:

1. **Companion documents resolve to `standards/` beside the runbook, not to `D:\Markdown`.**
   The runbook cites its mandatory companions by bare filename, and its `INET_DOC_SYNC`
   section names `D:\Markdown\…` as their home. On this machine they are here:

   | Runbook cites | Read it from |
   |---|---|
   | `TEAM_LIQUIBASE_STANDARDS.md` | [`standards/TEAM_LIQUIBASE_STANDARDS.md`](standards/TEAM_LIQUIBASE_STANDARDS.md) |
   | `beautify 3.md` | [`standards/beautify 3.md`](standards/beautify%203.md) |
   | `JIRA-PR-Automation.md` (§A–§J Liquibase compliance) | [`standards/JIRA-PR-Automation.md`](standards/JIRA-PR-Automation.md) |

   A `D:\Markdown\…` path in the runbook body is a **maintainer source-of-truth location,
   not a read path**. Never fail a gate because that path is absent — resolve the file from
   `standards/` and continue. If a cited companion is genuinely missing from `standards/`,
   that is a packaging fault: report it and treat the gate it feeds as skipped-and-disclosed,
   exactly as the runbook treats any other unavailable capability.

2. **`INET_DOC_SYNC` is maintainer-only and does not apply here.** That section instructs the
   agent to mirror runbook edits onto a Confluence page and re-upload attachments. It exists
   for the single editable copy at `D:\Markdown\JIRA-AI-Fix.md`. On a distributed install it
   is **N/A**: never edit this runbook, never push a Confluence page, never upload an
   attachment on its behalf. Report improvements to the runbook owner instead.

3. **Everything here is read-only.** `MANIFEST.json` in this directory records a sha256 for
   every file, so the install can be verified at any time. If the runbook needs a change, it
   changes at source and is redistributed — never patch the local copy.

## Configuration

All configuration is one file, outside every repository:

```
Windows   %USERPROFILE%\.jira-ai-config.json
other     $HOME/.jira-ai-config.json
```

Its sections — `i21`, `atlassian`, `sqlServer`, `sqlServer.knownServers`, `helpdesk` — are
documented inline in [`config/jira-ai-config.example.json`](config/jira-ai-config.example.json),
which is also the template a fresh install is seeded from. The runbook's *Optional
configurations* table is authoritative on what `atlassian`, `sqlServer` and `helpdesk` enable.

**`REPO_ROOT` binding — apply this on every run.** The runbook defaults `REPO_ROOT` to
`C:\i21Source`, which is a *convention*, not this machine's truth. Resolve it in this order:

1. An explicit `REPO_ROOT` (or `REPO` as a full path) given in the request — always wins.
2. **`i21.repoRoot` in the config file** — this machine's actual clone root.
3. The runbook's `C:\i21Source` default, only when neither of the above is set.

If you land on step 3 and that path does not exist, do not start searching the disk mid-run
and do not assume the current working directory: say the repo root is unconfigured, point at
`i21.repoRoot`, and stop. `REPO_ROOT` is the **container** of the repository clones and is not
itself a git working tree — never run git commands against it directly.

**Restore paths and the space floor.** When §1.7 restores a database, take the staging, data
and log directories from `sqlServer.restore` and fall back to the instance defaults only when
they are empty. Before starting a restore, check free space against
`sqlServer.restore.minimumFreeSpaceGB` and **stop rather than start a restore that cannot
fit** — the `.bak` and the fully expanded data and log files must all fit at once, and where
staging shares a volume with data the requirement is their sum. Report the numbers in the run
output. Unless `keepRestoredDatabases` is true, drop the restored copy when the run is done:
a stale customer database left behind is how a later run silently analyzes last month's data.

**Setup status — read it at run start.** If the config carries a `_setupStatus` block, read it
before §0 and let it shape the run:

- A section marked `skipped`, `not-applicable` or `failed` names a capability this machine does
  not have. **Do not attempt it, and do not treat its absence as a discovery** — the developer
  already accepted the consequence at install time. Carry it straight into the run's
  disclosure and the §6 RCA, using the recorded consequence.
- `verdict: NOT-READY` means a foundation is missing. Say which one, and stop rather than
  starting an analysis that cannot finish.
- The block is a record of the last setup, not live truth. Where a gate depends on a
  capability, still check the capability — `_setupStatus` tells you what to *expect* and what
  to disclose, never what to skip verifying. If reality disagrees with the block, trust
  reality and say the setup record is stale.

Absent `_setupStatus`, behave exactly as before: determine each capability from the config and
disclose whatever is missing.

**Already-restored servers.** Before downloading anything, check `sqlServer.knownServers`
against the server named in the ticket or its helpdesk restore note — matching on `name` and
`aliases` — and use the existing database in place when it matches. For a tunnelled entry the
address is `127.0.0.1,<port>`; never `localhost`, which resolves to `::1` and times out in a
way indistinguishable from an unreachable server.

**An empty section does not stop a run; it removes a capability.** The runbook's rule is that
a removed capability is skipped **and disclosed** — named in the run output and in the §6 RCA
— never guessed around. Follow that rule strictly: a run that quietly omits a validation it
could not perform is worse than one that states the gap.

Secrets in that file — SQL password, helpdesk cookie, Atlassian API token — are never copied
into a repository, a Jira comment, a Confluence page, a pull request, or run output. That
rule is the runbook's and it holds here.

If the developer needs to set up or re-check their configuration, the interview and the live
capability checks are in `START-HERE.md` in the original package (Phase 5 and Phase 6).

## Version-tier code locations

Resolve the tier from the Jira **Reported Build** (and §1.5 / fix-version evidence) before
searching or editing code. Prefer Reported Build over the local checkout branch.

| Reported Build | Tier | Database repo | Store UI / server paths (i21_Store) |
|----------------|------|---------------|--------------------------------------|
| **22.1 or below** | legacy | **i21_SqlScripts** | **`app/`** (UI) + **`server/`** (API, models, etc.) |
| **24.3 or higher** | modern | **i21_Liquibase** | **`universal/`** (UI) + **`web-api/`** (server) |
| **22.2–24.2** or unparseable | uncertain | **Ask the user** | **Ask the user** |

Rules:

1. **Database:** ≤22.1 → change SQL only under **i21_SqlScripts**. ≥24.3 → change SQL only
   under **i21_Liquibase** (apply `TEAM_LIQUIBASE_STANDARDS.md` + beautify + §A–§J). Never put
   a ≤22.1 fix into Liquibase or a ≥24.3 fix into SqlScripts unless the operator explicitly
   overrides.
2. **Store application code (i21_Store / ST module):** ≤22.1 → edit under `app/` and
   `server/` only. ≥24.3 → edit under `universal/` and `web-api/` only. Do not mix tiers
   (e.g. no `web-api/` edits on a 22.1 ticket).
3. **Other module repos** (AP, AR, GL, …): still resolve the module repo from Jira evidence
   as the runbook says; the database half of the table above still applies when the fix is
   SQL. Pre-Liquibase runbook gate (`TARGET_VERSION` < 24.1 → no Liquibase) remains in force
   for non-Store modules when it is stricter.
4. When the tier is **uncertain**, stop and ask which database repo and which Store layout
   to use — do not guess.
5. **UI + Ext metadata must stay in sync:** Whenever you add, rename, remove, or change
   display of UI components (grid columns, labels, fields, buttons, tabs) in a Store view
   (`.js` under `app/` or `universal/`), also update the matching Designer metadata:
   `metadata/view/<ViewName>` and/or `universal/.../metadata/view/<ViewName>`. Display-only
   UI changes still require metadata. Example: adding an ADD/CHG column to
   `GenerateShelfTags.js` requires the same column in `metadata/view/GenerateShelfTags`.

## Liquibase stored-procedure changeset rules (mandatory)

When creating or editing **i21_Liquibase** logic for stored procedures (and other
`runOnChange` objects that need batch splitting), apply these code-review rules before
commit/push:

### Rule lb-204 — `endDelimiter:GO` on the changeset line

Add `endDelimiter:GO` on the `--changeset` line for the stored procedure.

Example:

```sql
--changeset wendell.villareal@irely.com:20260910160100 runOnChange:true endDelimiter:GO
```

### Rule lb-205 — standalone `GO` before `--rollback`

Put a standalone `GO` on its own line before `--rollback` so the batch splits correctly.

Example:

```sql
END
GO
--rollback EXEC uspSMLiquibaseRollbackLogic 'uspSTGenerateShelfTagPreview'
```
