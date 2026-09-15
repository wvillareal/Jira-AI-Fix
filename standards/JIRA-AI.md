# JIRA-AI runbook — analyze → apply acceptance → feature branch → RCA/Developer's Testing

Execute this runbook **immediately and completely** in **Agent mode** once a **JIRA_KEY** is provided. Given only a Jira key, it:

1. **Analyzes** the Jira issue.
2. **Checks** the acceptance criteria.
3. **Applies** the acceptance criteria (implements the change in the current repository).
4. **Creates** a feature branch.
5. **Pushes** the feature branch.
6. **Comments** the **Root Cause Analysis (RCA) — Developer's Testing** on the Jira.

Between steps 1 and 2 two mandatory gates run: **§1.5** (branch/Jira consistency — auto-align) and **§1.6** (resolution feasibility — skip already-resolved tickets; restore the reported database locally per **§1.7** when the symptom is data-dependent; post a single **Information Request** comment and stop when required evidence is missing).

Do not summarize or ask for confirmation unless a mandatory **STOP** condition applies or **the affected repository cannot be auto-resolved from the Jira evidence** (see Input parameters — the runbook identifies the repository itself; it asks the user only as a last resort when that resolution stays ambiguous).

**This runbook does NOT create a Pull Request and does NOT propagate.** It stops after pushing the feature branch and posting the RCA / Developer's Testing comment on the Jira. (For the PR flow, use `JIRA-PR-Automation.md`.)

**Order:** Accept **JIRA_KEY** (optional **TARGET_BRANCH** override, optional **REPO_ROOT** / **REPO**) → resolve **REPO_ROOT** (the main folder where all i21 repositories reside, default `C:\i21Source`) → read the Jira (§1 issue read + **issue type gate: bug / technical debt / performance / data-fix types only — `Feature`, `Gap`, `Paid`, `Suggestion` and `Config` are out of scope** + **issue status gate: `Open` / `Reopened` only**) → **auto-resolve REPO_PATH** = `<REPO_ROOT>\<repo folder>` from the Jira/module evidence and cross-repo code search (an explicit REPO parameter wins; ask the user only when resolution stays ambiguous) and **load/clone the repository** so the code is locally available and current → resolve a provisional **TARGET_BRANCH** / **FEATURE_BRANCH** → complete the Jira code analysis (§1) → align the branch with the Jira fix version / build (§1.5 — **auto-switch**, STOP only when no base can be derived) → **classify resolution feasibility** (§1.6 — `STATIC` / `DB_REQUIRED-ACTIONABLE` / `DB_REQUIRED-BLOCKED` / `INFO_REQUIRED` / `CANNOT-FIX`; when required, acquire and restore the reported database locally per §1.7, when required information is missing post the standardized **Information Request** comment and STOP, and when the fix cannot land here post the **CANNOT-FIX** details+recommendation comment and STOP) → check acceptance criteria (§2) → apply the acceptance criteria and validate (§3) → when the fix touches Liquibase and a DB for the JIRA is known, launch the **async schema-change confirmation** on a separate agent (§3.5 — `liquibase update` → rollback verification, DB left rolled back, logs tracked, result commented on the PR; on a pre-24.1 branch the confirmation is instead the case-C **execute-then-restore**: run the changed script on the JIRA's DB, prove it executes, restore the pre-fix definitions so the DB is left unfixed; the main run continues without waiting) → author, validate, test and roll back the **data fix (§3.6)** when ISSUE_CATEGORY = DATA_FIX → check **regression impact (§3.7** — dependents + golden-set differential; repo/DB layer only, no app environment**)** → trace the **defect lineage (§3.8** — which change introduced the defect, which lines already carry a fix, and whether that fix is complete**)** → **property-test the changed object (§3.9** — old vs new side by side on a throwaway local DB, grid built from the code's own decision boundaries, invariants asserted so the fix provably cannot drift**)** → create the feature branch and commit (§4) → push (§5) → post the **RCA — Developer's Testing** comment on the Jira (§6 — **successful deliveries only**; every run that ends without a delivered fix posts the §6.5 triage / information-request / cannot-fix comment instead) → **status handoff (§6.6)** → **PR handoff (§6.7)**.

---

# Optional configurations (accuracy boosters — check at run start)

**All runbook configuration lives in ONE consolidated file:**

`JIRA_AI_CONFIG` = **`%USERPROFILE%\.jira-ai-config.json`** — user profile, NEVER in a repo. It has three sections: `atlassian`, `helpdesk`, and `sqlServer` (which contains the `knownServers` registry). Secrets (SQL password, session cookie) may be stored directly in it because the file lives outside every repo — never copy them into a repo, Jira, Confluence, PR, or log.

```json
{
  "atlassian": { "email": "", "apiToken": "", "tokenFile": "<path to ~/.atlassian-token>" },
  "helpdesk":  { "baseUrl": "https://helpdesk.irely.com/irelyi21Live", "cookie": "<session cookie>", "obtainedAt": "<date>" },
  "sqlServer": { "server": "…", "instance": "…", "auth": "sql", "user": "…", "password": "…", "…": "…", "knownServers": [ "…" ] }
}
```

Legacy fallbacks are honored when the file or a section is absent: env `ATLASSIAN_EMAIL`/`ATLASSIAN_API_TOKEN` and `~/.atlassian-token` for `atlassian` (that token file is shared with other runbooks and remains valid — the `atlassian` section can point at it via `tokenFile` instead of duplicating the secret), and the retired per-purpose files `.i21-sqlserver.json` / `.i21-helpdesk.json` for older setups.

No section is required to start a run, but each one that is **missing or empty removes a capability**: the run then proves less, falls back to an Information Request, or must disclose a skipped validation. At run start, check the file and report the gaps in the run output, so the operator knows why a run was narrower than it could have been.

| # | Section | What it enables | Behavior when missing / no info |
|---|---------|-----------------|--------------------------------|
| 1 | `atlassian` | §1 attachment evidence: downloading and reading screenshots/PDFs and attached DB backups (the Atlassian MCP is 403-blocked on attachment content). Precedence: `email`+`apiToken` in the section → `tokenFile` → env vars. | Load-bearing screenshot/attachment evidence cannot be read → STOP / §1.6 Information Request instead of a root cause |
| 2 | `sqlServer` | §1.7 local restore of a DB attached/linked on the JIRA (defines **where** the AI restores it); §3.5 `liquibase update` + rollback confirmation and its logs | `DB_REQUIRED` issues cannot be reproduced/proven → Information Request asking for the DB; §3.5 skipped with the RCA disclosure `liquibase update NOT run` |
| 3 | `sqlServer.knownServers` | §1.7 step 0: when the JIRA (description/comment) says the DB was **already restored on a server** (e.g. an HDTN restore note naming a QA server + DB name), the AI matches that server by name/alias and uses the existing DB directly — no download, no re-restore | Server names mentioned in the JIRA cannot be resolved to a connection → the run falls back to downloading/restoring locally, or to an Information Request; record the unmatched server name in the run output so the operator can add it to the registry |
| 4 | `helpdesk` | §1 HDTN evidence enrichment (**supplementary — an HD ticket is never required**): reading a *referenced* helpdesk ticket — above all its **`Database Copy` tab / restore comment / restore screenshot**, which names the server + database IT restored the copy onto (→ §1.7 step 0), plus its discussion thread, screenshots/attachments, and **helpdesk-hosted images embedded in Jira descriptions** (the Jira attachment field is often empty — refs AP-24771/AP-24802). Image GETs work with the cookie directly; the ticket thread and the `Database Copy` tab need the SPA driven via Playwright with the saved cookie (§1 step 6). | Cookie missing/**expired** (HTTP 401 / login redirect) → **record the gap and CONTINUE** on the JIRA's own evidence (operator 2026-08-07); the restore location then falls through to the §1.7 registry sweep or a §1.6 DB information request. Never a STOP. Never guess or brute-force a login. |

Accuracy rule: a missing optional config is never guessed around — the affected capability is skipped **and disclosed** (run output + RCA/Information Request), never silently faked.

---

# INET_DOC_SYNC (maintenance — keep the iNet page in sync)

This runbook is documented on iNet (Confluence). **Whenever this markdown changes, update the iNet page in the same change** and add a row to its change-history table. Keep the page and this file describing the same steps, gates, and rules.

- iNet page: **JIRA-AI Runbook — Analyze → Apply Acceptance → Feature Branch → RCA (JIRA-AI.md)**
  https://irely.atlassian.net/wiki/spaces/AP/pages/661389848/
- cloudId: `irely.atlassian.net` · Space: `AP` (i21 Purchasing, spaceId `83394560`) · Page ID: `661389848`
- **SINGLE SOURCE OF TRUTH: `D:\Markdown\JIRA-AI.md`.** There is exactly ONE markdown copy. Do not create a second copy inside any i21 repository working tree (operator 2026-08-07 — the former `c:\i21Source\Liquibase\JIRA-AI.md` "workspace copy" was **deleted**).
  **Why the second copy was removed:** it was never tracked by `i21_Liquibase` and never gitignored, so it sat as an untracked file in a working tree that routinely carries 1,800+ dirty entries on someone's feature branch — where this runbook's own §4 `git add -A` would sweep 159 KB of documentation into a code commit on that branch. It also had dangling references (the mandatory `TEAM_LIQUIBASE_STANDARDS.md`, `beautify 3.md`, and `JIRA-PR-Automation.md` §A–§J live only in `D:\Markdown`). Distribution is served instead by the iNet page, which carries this file as an always-current attachment (refreshed on every sync — see the Mechanics below).
  If a repo-adjacent copy is ever genuinely needed again, **gitignore it in that repo first**, and treat it as read-only: `D:\Markdown` remains the only editable source.
- Process-flow diagram: `D:\Markdown\jira-ai-flow.svg` — same single-source rule, and uploaded to the page as a dated attachment on each regeneration.

**Auto-update procedure:** after editing this file, mirror the changed sections onto the page, append a dated row to the **Maintenance & change history** table, set a `versionMessage`, and re-upload this markdown as the page's `JIRA-AI.md` attachment so the published copy never goes stale. When the change alters the flow or a gate, also regenerate `jira-ai-flow.svg`, upload it under a new dated filename, and repoint the page's image node at it. Do not let the page diverge from this file.

**Mechanics (verified 2026-08-07 — prefer REST over the MCP for this page):**
- **Edit in STORAGE format via the Confluence REST API**, not by round-tripping the page through markdown: `GET /wiki/rest/api/content/661389848?expand=body.storage,version` → apply **surgical string replacements** on the storage XHTML (each anchor asserted to match exactly once, aborting before the write if any anchor misses) → `PUT` the same document back with `version.number + 1`. A markdown round-trip **destroys the page's non-text nodes** — the `<ac:image>`/`<ri:attachment>` diagram reference, the `view-file` macro embedding this markdown, panel macros, and `<time>` nodes all come back as unusable placeholders. Storage-format surgery preserves them untouched. Auth: basic auth with the Confluence account in `~/.cursor/mcp.json` (`CONFLUENCE_USERNAME` + `CONFLUENCE_API_TOKEN`), the same credentials the other `sync_*.py` scripts use.
- **Attachments CAN be uploaded programmatically** — the *MCP* has no attachment tool, but REST does: a NEW file is `POST /wiki/rest/api/content/<pageId>/child/attachment` (multipart, header `X-Atlassian-Token: no-check`); an EXISTING filename must go to `POST /wiki/rest/api/content/<pageId>/child/attachment/<attachmentId>/data` (posting a duplicate filename to the collection endpoint returns HTTP 400 "Cannot add a new attachment with same file name"). After uploading a regenerated SVG under a new dated name, repoint the `<ri:attachment ri:filename="…">` in the image node and update `ac:original-height`. **The former "attach the SVG manually" step is obsolete.**

---

# Input parameters

JIRA_KEY = <provided issue key parameter>

Validation:
- JIRA_KEY MUST match regex: `[A-Z][A-Z0-9]+-\d+$`
- If JIRA_KEY is missing or invalid -> STOP execution (do not infer it from the current branch).
- JIRA_KEY is used for the feature-branch name, the commit message, and the Jira comment only.

TARGET_BRANCH = <optional target branch override parameter> (default: the current branch)

Validation:
- TARGET_BRANCH is OPTIONAL. If it is not provided, resolve it from the current branch (see "Feature-branch detection" below).
- TARGET_BRANCH MUST be a single branch name. It MUST NOT be a comma-separated list and MUST NOT contain `{` or `}`.
- TARGET_BRANCH MUST exist on origin (`git ls-remote --heads origin <TARGET_BRANCH>`). If it does not exist on origin -> STOP execution (do not guess or create the target branch).
- The feature branch will be `<FEATURE_BRANCH>` (= `<TARGET_BRANCH>_<JIRA>`). TARGET_BRANCH MUST NOT equal FEATURE_BRANCH.
- TARGET_BRANCH MUST additionally pass the **Branch/Jira consistency check** (§1.5) once the Jira has been read. An auto-detected branch that does not match the Jira's fix version / reported build is **automatically switched** to the Jira-derived `EXPECTED_BRANCH` (§1.5); an explicitly provided TARGET_BRANCH is kept with a warning.

REPO_ROOT = <optional local path of the **main folder where all i21 repositories reside**> (default: `C:\i21Source`)

REPO = <optional repository to analyze/modify> (repo name / PRODUCT, e.g. `AP` / `Accounts Payable`, `Liquibase`, `SqlScripts` — or a full local path such as `C:\i21Source\AP`)

Validation:
- REPO_ROOT is OPTIONAL; when not provided it defaults to `C:\i21Source`. It is the **container** of the i21 repo clones (~45 sibling repos) and is **NOT itself a git repository** — never run git commands against `<REPO_ROOT>` directly.
- REPO is OPTIONAL. When provided (repo name or full path) it wins and is used directly.
- **IF REPO is not provided -> AUTO-RESOLVE the affected repository from the Jira** (do NOT ask the user first, and do NOT silently assume the current working directory or the opened workspace):
  1. Read the Jira (§1 issue read) and extract the module/artifact evidence: project key & module (e.g. `AP-*` → Accounts Payable), screens, ExtJS classes/xtypes, C# types, SQL objects, and any file paths named in the description, comments, or attachments.
  2. Map that evidence to candidate repositories under `<REPO_ROOT>` (the PRODUCT table in **Repository scope** covers the common AP set, but ANY i21 repo under `<REPO_ROOT>` is a valid candidate when the evidence points there — e.g. a framework/EntityManagement widget consumed by an AP screen).
  3. Confirm by code search: the candidate whose tree actually contains the affected artifact(s) (`git -C <candidate> grep -il "<artifact>" origin/<Jira-derived branch>`) is REPO_PATH. If parts of the fix genuinely span repos, the PRIMARY repo is the one owning the defective artifact; record the others in the §1 analysis.
  4. ONLY IF the repository is still ambiguous after the code search (no candidate contains the artifact, or several contain same-named but different objects) -> ASK THE USER and WAIT.
- REPO_PATH = `<REPO_ROOT>\<repo folder>` resolved from REPO (when provided) or from the auto-resolution above, via the PRODUCT table in **Repository scope** (e.g. `C:\i21Source\AP`). If a full path to one repository is given, use that path as REPO_PATH directly (and its parent folder as REPO_ROOT).
- REPO_PATH MUST be the path of **one repository**, not the `<REPO_ROOT>` container — the container fails the `rev-parse --is-inside-work-tree` check in **Repository scope**.
- Resolution, loading, and cloning of REPO_PATH are defined in **Repository scope** below. All git commands in this runbook run against `<REPO_PATH>` (`git -C <REPO_PATH> …`).

APP_ENV = <optional URL of a running i21 application environment for this JIRA (e.g. `https://…/2710DEV`)>

Validation:
- APP_ENV is OPTIONAL and is **never provisioned by this runbook** (no app environment is built, deployed, or configured here). Its ONLY purpose is to enable the **§1.7a runtime reproduction** (R-RUNTIME-REPRO) for symptoms that cannot be reached from SQL alone — screen behavior, ExtJS field state, document/PDF rendering, HTTP payloads.
- When APP_ENV is NOT provided: skip §1.7a entirely, never STOP for it, and — when the EVIDENCE_SET is UI-level — record `runtime reproduction NOT run — no APP_ENV provided` in the run output and disclose it in the §6 RCA (same disclosure discipline as a skipped `liquibase update`).
- When APP_ENV IS provided it MUST pass the **§1.7a version match** before any evidence taken from it is used: the app's version must match `TARGET_VERSION` **and** the restored/connected database's `tblSMBuildNumber` version on **main.major only** (see §1.7 step 2.6). A mismatch does not stop the run — the runtime evidence is DISCARDED and the mismatch is reported (`APP_ENV version <x> ≠ DB <y> / branch <z> — runtime evidence discarded`), because a screen served by the wrong build proves nothing about this branch.
- Never write to a customer-facing/production APP_ENV. Reproduction only: read, navigate, and capture. No posting, saving, approving, or deleting on an environment that is not a restored copy under the operator's control.
- Credentials for APP_ENV are never echoed into any Jira comment, RCA, PR, log, or run output (same rule as ticket-embedded credentials in §1 step 5).

**Feature-branch detection (mandatory when TARGET_BRANCH is not provided):**
The current branch may itself already be a `<base>_<JIRA>` feature branch (a previous run, or a manually created one). Auto-detection MUST handle this so it never double-suffixes:
1. `CURRENT_BRANCH = git -C <REPO_PATH> branch --show-current`.
2. IF `CURRENT_BRANCH` matches `^(?<base>.+)_(?<key>[A-Z][A-Z0-9]+-\d+)$` (i.e. it ends in `_<JIRA-KEY>`):
   - `TARGET_BRANCH = <base>` (the prefix with the `_<JIRA>` suffix stripped), and
   - `FEATURE_BRANCH = CURRENT_BRANCH` (reuse the existing feature branch as-is — do NOT create `<base>_<JIRA>_<JIRA>`).
   - If the trailing key does not equal JIRA_KEY, STOP and report the mismatch (the operator must confirm which branch to work from).
3. ELSE (current branch is a plain branch, e.g. `26.1Dev`):
   - `TARGET_BRANCH = CURRENT_BRANCH`, and `FEATURE_BRANCH = <TARGET_BRANCH>_<JIRA>` (created in §4).
4. After resolution, assert `TARGET_BRANCH != FEATURE_BRANCH` and that `TARGET_BRANCH` exists on origin; otherwise STOP.
5. An auto-detected TARGET_BRANCH is **provisional** until §1.5 — which **auto-switches** to the Jira-derived `EXPECTED_BRANCH` on mismatch. A checked-out branch is often leftover from unrelated work and must never be trusted as the base on its own.

# Queue selection for batch & scheduled runs (R-QUEUE-LABEL-STATE, operator 2026-08-11)

This runbook processes **one JIRA per run**. When it is driven repeatedly — a batch pass over the open queue, or a **Claude scheduled task** firing on a cron — something must decide which JIRA is next, and that selector MUST exclude the tickets a previous run already terminated on. **R-DB-LEDGER-REUSE forbids this runbook from writing any ledger, index, or log**, so the durable state is the one place Jira already keeps it: the **§6.6 labels**. Without this filter a nightly task re-analyzes the same blocked tickets forever and re-posts information requests the reporter has already been asked (the 2026-08-04 audit measured exactly this waste class: 25 of 65 runs would have duplicated existing work).

**Canonical selection JQL** (the AP queue; adapt `project` / `issuetype` to the pass's scope):

```
project = AP
AND issuetype in ("Bug", "Bug-QC", "Bug-UAP", "Bug-Ongoing UAP", "Technical Debt", "Performance", "Data Fix")
AND status in (Open, Reopened)
AND (labels IS EMPTY OR labels NOT IN ("AP-AI-NeedInfo", "AP-AI-CannotFix", "AP-AI-Triaged", "AP-AI-Fixed", "AP-AI-DataFix"))
ORDER BY priority DESC, updated ASC
```

- **`labels IS EMPTY OR …` is mandatory, not defensive.** Jira's `NOT IN` does not match issues whose field is empty, so `labels NOT IN (…)` alone silently drops every unlabeled ticket — i.e. exactly the never-processed ones the pass exists to find.
- **Filter on labels, never on status.** Every not-fixed outcome deliberately leaves the status untouched (§6.6: an information request keeps the ticket `Open` because the reporter owns it), so status alone cannot dedupe. The type and status gates still apply to whatever this JQL returns — the filter narrows the candidate set, it never replaces a gate.
- **Which labels gate selection:** the five terminal outcome labels above, and only those. `AP-AI-Fixed` / `AP-AI-DataFix` are terminal for this runbook — the fix exists and the next move belongs to `JIRA-PR-Automation.md` or a human. `AP-AI-NeedInfo` / `AP-AI-CannotFix` / `AP-AI-Triaged` mean the run's conclusion stands until the blocking gap changes.
- **Never filter on `AP-AI-RegressionFlag` or `AP-AI-FixPropagated`.** The first is an attribute of a delivered fix, the second belongs to the propagation runbook — neither says anything about whether *this* runbook has processed the ticket. Excluding them wrongly drops live work (ref AP-24523: `Reopened` on 2026-08-11 while carrying `AP-AI-FixPropagated` from an earlier propagation run — a genuine re-analysis candidate).
- **Re-entry is evidence-driven, not time-driven.** A labeled ticket comes back into scope when the gap that stopped the run is addressed: a human clears the label, or the ticket gains a comment/attachment **newer than** the runbook's own terminal comment. Re-picking such a ticket is correct and the §1.6 **dedupe guard** — not this filter — decides whether a second comment is warranted. Never re-post an identical request against unchanged evidence; never age a label out on a schedule.
- **An explicitly provided `JIRA_KEY` always wins.** This filter governs *automatic* selection only. An operator naming a ticket runs it regardless of its labels.
- **Cohort expansion (batch passes).** When the pass is cohort-based, expand the selected JIRA into its customer/environment cohort (§1 step 7a) and process the cohort in one run — one restore serves all of it, and **R-DB-SLOT-LIMIT** caps concurrent DB cohorts at two. Apply the label filter to each member individually; an already-terminated sibling stays out.
- **Unattended runs must always leave a label.** A scheduled run cannot ask the operator anything, so every STOP that would normally await an answer — the §1.5 case-twin guard, the artifact-present-only-on-a-forbidden-Prod-branch conflict, an ambiguous repo resolution — terminates through the **§6.5 D TRIAGE comment + `AP-AI-Triaged`** (R-NOFIX-COMMENT), naming the decision the operator owes. Otherwise the next scheduled pass re-derives the same stall from scratch, indefinitely.
- **Reporting benefit:** because every outcome lands a label, a batch pass's statistics are a set of JQL counts (`labels = "AP-AI-Fixed"`, `= "AP-AI-NeedInfo"`, …) rather than a hand-maintained tally — countable by anyone, at any time, without a tracking file.

# Issue type gate (mandatory)

Before doing any work, read `<JIRA_KEY>` from Jira and cache:

PARENT_ISSUE_TYPE = <the issue type that gates the run: the issue's **own** type. Only when `<JIRA_KEY>` is a **sub-task** does the gate read its parent instead — the sub-task inherits the parent work item's classification. The Epic/Story/Initiative *above* a standard issue is never read and never gated on (an Epic parent does not make a Bug-QC out of scope).>

Allowed bug issue types:
- `Bug`
- `Bug-QC`
- `Bug-UAP`
- `Bug-Ongoing UAP`

Allowed technical debt / performance issue types:
- `Technical Debt`
- `Performance`   (performance optimization — ISSUE_CATEGORY = TECHNICAL_DEBT)

Allowed data-fix issue type:
- `Data Fix`   (Jira issue type id `10038` — "issues that require only a datafix and not a bug fix; the data issue can be the result of old bugs that were already resolved" — ISSUE_CATEGORY = DATA_FIX)

**Explicitly OUT OF SCOPE — never run (operator 2026-08-11):**
- **New-feature issue types: `Feature`, `Gap`, `Paid`, `Suggestion`.** This runbook no longer has a `FEATURE` category. New-feature work does not enter this flow at all — not analysis, not a branch, not a comment.
- **`Config` (billable bugs).** Removed from the allowed bug types; a `Config` issue is treated exactly like any other out-of-scope type.

All five of these types are a **silent STOP**, identical to any other out-of-scope type: no analysis, no repo load, no branch, no label, and **no Jira comment**. Report the skip as `OUT-OF-TYPE (<issue type>)` in the run output; in a batch, continue to the next JIRA.

IF PARENT_ISSUE_TYPE is not exactly one of the allowed types:
    STOP execution — this runbook applies only to allowed bug, technical debt, performance, and data-fix issue types. (Do NOT post any comment for an out-of-scope issue type.)

IF PARENT_ISSUE_TYPE is one of the allowed technical debt / performance issue types (`Technical Debt`, `Performance`):
    ISSUE_CATEGORY = TECHNICAL_DEBT
ELSE IF PARENT_ISSUE_TYPE is `Data Fix`:
    ISSUE_CATEGORY = DATA_FIX
ELSE:
    ISSUE_CATEGORY = BUG

**R-DATAFIX-DB — a data fix ALWAYS requires the database (no exception).** When `ISSUE_CATEGORY = DATA_FIX`, the §1.6 feasibility classification can never be `STATIC`: a data fix corrects rows that exist only in the customer's database, so the affected row set cannot be identified, counted, or verified without it. §1.6 resolves to `DB_REQUIRED-ACTIONABLE` (DB reachable → §1.7 immediately) or `DB_REQUIRED-BLOCKED` (→ ONE information request for the backup, then STOP). Never author, deliver, or "reason out" a data fix against code alone.

# Issue status gate (mandatory)

ISSUE_STATUS = <the issue's current status, from the §1 issue read>

Allowed statuses:
- `Open`
- `Reopened`

IF ISSUE_STATUS is not exactly one of the allowed statuses:
    STOP execution — this runbook runs ONLY on issues whose status is **Open** or **Reopened**. (Do NOT post any comment for an out-of-status issue.) Any other status means the issue is already being worked, tested, or verified — `Coding`/`In Progress` belongs to its assignee, `Testing`/`Ready to Test` already has a delivered fix (an automated run would duplicate it — see the §1.6 ALREADY-RESOLVED evidence class), and `Closed`/`Done` needs no fix. Report the skip as `OUT-OF-STATUS (<status>)` in the run output; in a batch, continue to the next JIRA.

# Repository scope (REPO_ROOT container → single repo REPO_PATH, loaded/cloned before analysis)

REPO_ROOT = the **main folder where all i21 repositories reside** (default `C:\i21Source`). It is a container of sibling repo clones and is NOT itself a git repository — no git command runs against it directly.

REPO_PATH = `<REPO_ROOT>\<repo folder>` — the local repository this runbook analyzes and modifies, resolved from the **REPO input parameter** when provided, otherwise **auto-resolved from the Jira/module evidence and cross-repo code search** (see Input parameters → REPO auto-resolution). Ask the user only when that resolution stays ambiguous — and never assume the opened workspace is the intended repo.

**Repo load/clone (mandatory — the repository MUST be locally present and up to date BEFORE the §1 analysis, so the code analysis reads real, current code):**

1. IF `<REPO_PATH>` exists locally AND `git -C <REPO_PATH> rev-parse --is-inside-work-tree` returns `true` (repo already cloned):
   - **Load it:** `git -C <REPO_PATH> fetch origin` so branch/commit analysis runs against the current remote state.
   - Check `git -C <REPO_PATH> status --porcelain`. If the tree is dirty with edits **unrelated** to `<JIRA>` -> **STASH AND CONTINUE** (operator policy 2026-08-04; replaces the former STOP): `git -C <REPO_PATH> stash push -u -m "JIRA-AI auto-stash <current branch> <JIRA> <UTC timestamp>"`, verify `status --porcelain` is now clean, record the stash ref and message in the run output, and continue. Never `pop`/`drop` the stash automatically — the WIP owner restores it from `git stash list` via the labeled entry. If the stash command itself fails -> STOP.
2. ELSE (path does not exist, or exists but is not a git repository):
   - **Clone the required repo from Azure DevOps into `<REPO_PATH>`:**
     `git clone https://dev.azure.com/irely/i21/_git/<ADO_REPO> <REPO_PATH>`
     using the Azure DevOps MCP / `az`-authenticated git (no PAT). Resolve `<ADO_REPO>` from the repo the user named, via the PRODUCT table below. (Create `<REPO_ROOT>` first if the container folder itself does not exist yet.)
   - If the clone fails (auth, network, unknown repo) -> STOP execution.
3. When `TARGET_BRANCH` was provided: `git -C <REPO_PATH> checkout <TARGET_BRANCH>` then `git -C <REPO_PATH> pull --ff-only origin <TARGET_BRANCH>`, so §1/§3 analyze the correct branch. (When TARGET_BRANCH was not provided, the current branch is used — see Feature-branch detection.)
4. Confirm it is a git repository: `git -C <REPO_PATH> rev-parse --is-inside-work-tree` returns `true`. If not -> STOP execution.
5. Resolve `ADO_REPO` from the origin remote: `git -C <REPO_PATH> remote get-url origin` -> the name after `/_git/`. Cache `ADO_REPO`.
6. Resolve `PRODUCT` for display from the remote substring:

| PRODUCT | ADO_REPO | REPO_PATH (under REPO_ROOT) | Typical remote substring |
|---------|----------|------------------------------|---------------------------|
| Accounts Payable | i21_accountspayable | `<REPO_ROOT>\AP` (e.g. `C:\i21Source\AP`) | AP or i21_accountspayable |
| Liquibase | i21_Liquibase | `<REPO_ROOT>\Liquibase` (e.g. `C:\i21Source\Liquibase`) | Liquibase |
| SQLScript | i21_sqlscripts | `<REPO_ROOT>\SqlScripts` (e.g. `C:\i21Source\SqlScripts`) | SQLScript, SqlScripts, or i21_sqlscripts |

# Derived variables (must be resolved before execution)

JIRA = JIRA_KEY
PARENT_ISSUE_TYPE = <resolved from parent JIRA>
ISSUE_CATEGORY = BUG | TECHNICAL_DEBT | DATA_FIX   # from issue type gate (there is no FEATURE category — new-feature types are out of scope)
ISSUE_STATUS = <the issue's current status — must be `Open` or `Reopened`, see Issue status gate>
REPO_ROOT = <input parameter — the main folder where all i21 repositories reside; default C:\i21Source>
REPO_PATH = <`<REPO_ROOT>\<repo folder>` (e.g. C:\i21Source\AP), resolved from the REPO parameter; if the repository was not provided, ASK THE USER — then loaded/cloned per Repository scope>
ADO_REPO = <resolved from origin remote `/_git/<name>`>
PRODUCT = <Accounts Payable | Liquibase | SQLScript, for display>
TARGET_BRANCH = <override parameter, else current branch — auto-aligned to the Jira-derived EXPECTED_BRANCH by §1.5>
FEATURE_BRANCH = `<TARGET_BRANCH>_<JIRA>`   # branch carrying the acceptance-criteria implementation
JIRA_FIX_VERSION = <fixVersions from the JIRA, e.g. 26.3 — see §1.5>
JIRA_BUILD = <reported version/build from the JIRA, e.g. 26.3ProdSucafina.0724.235 — see §1.5>
JIRA_CUSTOMER = <customer from the JIRA, e.g. Sucafina — see §1.5>
ACCEPTANCE_CRITERIA = <extracted from the Jira — see §2>
FEASIBILITY = STATIC | DB_REQUIRED-ACTIONABLE | DB_REQUIRED-BLOCKED | INFO_REQUIRED | CANNOT-FIX   # resolution-feasibility class — see §1.6
JIRA_AI_CONFIG = <the consolidated runbook configuration file, `%USERPROFILE%\.jira-ai-config.json` — sections `atlassian` / `helpdesk` / `sqlServer`; see Optional configurations. Lives in the user profile, NEVER inside a repo.>
SQLSERVER_CONFIG = <the `sqlServer` section of JIRA_AI_CONFIG — see §1.7>
RESTORE_DB_NAME = <name of the locally restored copy of the reported database, from the §1.7 naming pattern, e.g. `i21_AP-24754_ECOM`>
RESTORE_SLOTS = <the local restore pool: at most **2** databases matching `dbNamePattern` may exist on the local instance at once; a third DB_REQUIRED cohort is parked as `DB_QUEUED` until a slot is released (**drop the DATABASE only — the compressed backup archive is kept**, see **R-DB-KEEP-ARCHIVE**) — see **R-DB-SLOT-LIMIT** in §1.7>
DB_BUILD_VERSION = <the `strVersionNo` of the newest row in the restored/connected DB's `tblSMBuildNumber` — see §1.7 step 2.6>
APP_ENV = <optional input parameter — URL of a running i21 app environment, used ONLY by §1.7a runtime reproduction; never provisioned by this runbook>
APP_ENV_VERSION = <the i21 version reported by APP_ENV, resolved in §1.7a>
IS_DATAFIX_CASE = true WHEN ISSUE_CATEGORY = DATA_FIX   # routes to §3.6 instead of a code change
CHANGED_OBJECTS = <every SQL logic object (SP/view/function/trigger) or code artifact whose definition the CHANGESET alters — see §3.7>
DEPENDENTS = <everything that consumes a CHANGED_OBJECT: repo-wide references + `sys.sql_expression_dependencies` when a DB is available — see §3.7 tier 1>
GOLDEN_SET = <the reported document(s) PLUS N sampled rows that exercise the same code path and are NOT the reported defect — see §3.7 tier 2>
REGRESSION_VERDICT = CLEAN | UNEXPECTED-DELTAS | CONTRACT-FAIL | NOT-RUN   # §3.7
DEFECT_ORIGIN = <the change that introduced the defect: `<JIRA key> | <summary> | <commit> | <date> | <author>`, or `not determinable` — see §3.8>
FIX_COVERAGE = <per active version line: DEFECT | PARTIAL | FIXED | N/A — established by CONTENT and proven with a counterexample; see §3.8>
COVERAGE_GAPS = <lines still DEFECT/PARTIAL that this run does not fix — reported, never acted on (§3.8 step 6)>
PROPERTY_TEST = <§3.9 result: inputs/evaluations, failures OLD→NEW, subset check, fixed, changed, unwanted drift, accuracy regressions, residual classes — or NOT-RUN with the reason>
OBJECT_OWNER = <the module/project that OWNS the changed object, decided from file location + caller distribution + the project keys on every prior commit — NOT from the JIRA's own project key; see §3.8 step 5 (R-OBJECT-OWNERSHIP)>
DATAFIX_FILE = `<JIRA>DataFix.sql`   # the delivered data-fix artifact — see §3.6
CHANGESET = <the files changed while applying the acceptance criteria — see §3>
IS_LIQUIBASE_STANDARD_CASE = true WHEN any file in CHANGESET is a SQL-script file (i21_Liquibase `.sql`/`.xml`, or i21_sqlscripts/SqlScripts `.sql`)
TARGET_VERSION = <the numeric version prefix of TARGET_BRANCH, e.g. `22.1` from `22.1ProdWaMa`, `26.3` from `26.3Prod`>
IS_PRE_LIQUIBASE_BRANCH = true WHEN TARGET_VERSION < 24.1   # Liquibase exists only for i21 versions >= 24.1 — see R-LB-24.1-TARGET

# Mandatory policy sources

- Code fix changes management guidelines:
  https://irely.atlassian.net/wiki/spaces/AP/pages/578519663/Code+fix+changes+management+guidelines
- Team Liquibase Standards:
  `TEAM_LIQUIBASE_STANDARDS.md`
- Liquibase SQL beautify rules:
  `beautify 3.md`
- Liquibase: Development Standard (iNet):
  https://irely.atlassian.net/wiki/spaces/FRM/pages/62014463/Liquibase+Development+Standard
- Liquibase: Core Concepts and subpages (Changelog, Schema, Logic, Schema vs. Logic, Execution Order, Dependencies):
  https://irely.atlassian.net/wiki/spaces/FRM/pages/457247257/Core+Concepts
- SQL Performance Pitfalls and Best Practices (iNet):
  https://irely.atlassian.net/wiki/spaces/ID/pages/75700433/SQL+Performance+Pitfalls+and+Best+Practices
- **JIRA Datafix Template** (the base script EVERY data fix must derive from — mandatory when ISSUE_CATEGORY = DATA_FIX):
  https://irely.atlassian.net/wiki/spaces/AP/pages/434602044/JIRA+Datafix+Template
- **Data Fix Guidelines** (Foundational Guidelines + Standards 1–4 + review workflow — mandatory when ISSUE_CATEGORY = DATA_FIX):
  https://irely.atlassian.net/wiki/spaces/AP/pages/503382346/Data+Fix+Guidelines

Before validating any `i21_Liquibase` changes, read and apply `TEAM_LIQUIBASE_STANDARDS.md`. Before completing validation on changes that touch Liquibase SQL files, read and apply `beautify 3.md` together with `TEAM_LIQUIBASE_STANDARDS.md`.

**When `IS_LIQUIBASE_STANDARD_CASE = true` (the change touches SQL scripts), the Liquibase standard compliance rules (§A–§J of `JIRA-PR-Automation.md`) are MANDATORY.** The applied change must be a valid, standard-compliant Liquibase changeset before the feature branch is pushed: fresh 14-digit **timestamp IDs** (`YYYYMMDDHHmmss`) for every new changeset, correct folder/file placement, `--comment: <JIRA>`, preconditions where the object may already exist, a valid rollback, `endDelimiter:GO` where required, immutability of deployed changesets, and column/identifier binding against the defining UDT/table.

**R-LB-24.1-TARGET — pre-Liquibase target branch (Liquibase exists only for i21 versions ≥ 24.1).** When `IS_PRE_LIQUIBASE_BRANCH = true` (TARGET_VERSION < 24.1, i.e. any 22.x/23.x branch):
- SQL changes are authored **directly in the i21_sqlscripts SSDT file** (`i21Database/dbo/...`) — a raw `.sql` edit is the CORRECT mechanism there, not a standards violation.
- `i21_Liquibase` is NOT a valid repo for that branch: its sparse sub-24.1 branches (e.g. `22.1Prod_CM-7311`, `23.2Dev_MDM`) are ad-hoc special-purpose branches, never a deployment channel — never create a sub-24.1 Liquibase branch.
- The Liquibase changeset mechanics (§A–§I: timestamp IDs, `--comment`, preconditions, rollback, `endDelimiter:GO`, changeset immutability) do NOT apply.
- The **§J column/identifier-binding check still applies unchanged** (it is SQL correctness, not Liquibase), and remains the fail-closed gate.
- The schema-change confirmation runs as the **§3.5 case C execute-then-restore** (confirm the changed script executes successfully on the JIRA's DB, then leave the DB unfixed) instead of `liquibase update`/rollback.

# Azure DevOps MCP preflight (mandatory)

Before any Azure DevOps repository, commit, or branch operation, verify that the Azure DevOps MCP server (`azure-devops`) is functional. Run one read-only MCP check against the current project/repo context, for example:
- `repo_get_repo_by_name_or_id` for `ADO_REPO` in `ADO_PROJECT`, or
- `repo_search_commits` once `ADO_REPO` is known.

MCP is functional only when the tool call returns a successful Azure DevOps response for the intended project/repo. If the MCP call fails because the server is unavailable, Azure authentication is missing, Azure CLI / Az.Accounts cannot be found, credentials are expired, or authorization is denied -> STOP execution. Do not bypass this gate with raw REST calls, PATs, cached state, or guessed branch state.

ADO_ORG: irely
ADO_PROJECT: i21

# ==================================================================
# STEPS
# ==================================================================

## §1 Analyze the JIRA

PRE-REQ:
- Jira integration tool available and cloudId resolved (e.g. `getAccessibleAtlassianResources`).

1. Read the issue with `getJiraIssue` for `<JIRA>`. Cache: summary/title, issue type, priority, status, description, customer, **fix version**, **reported version/build**, and all comments. (The last three feed the §1.5 branch check.)
2. Confirm PARENT_ISSUE_TYPE against the **Issue type gate** and ISSUE_STATUS against the **Issue status gate** (`Open` / `Reopened` only). STOP if either is out of scope.
3. Summarize the reported problem / requested behavior (symptom, expected behavior, affected area/module). This summary feeds the RCA in §6.
4. Identify the affected code area in `REPO_PATH` from the Jira description and any linked technical evidence (files, objects, screens, procedures, columns). PRE-REQ: the repository was already loaded/cloned and fetched per **Repository scope** — the analysis MUST read the actual current code in `<REPO_PATH>`, not assumptions about it.
5. **Attachment evidence (screenshots / PDFs) — do NOT stop on "screenshot-only" evidence.** When the load-bearing evidence (an error message, measured values, a failing document) lives in image/PDF attachments, download and read them:
   - Attachment ids and filenames come from the §1 issue read (`fields=["attachment"]` → each entry has `id` and a `content` URL).
   - The Atlassian MCP has **no** attachment tool, and its OAuth token is scope-blocked (HTTP 403) on `/rest/api/3/attachment/content/<id>` — do not retry through the MCP.
   - Download with the user's Atlassian **API token** (basic auth):
     `curl -sL -u "<ATLASSIAN_EMAIL>:<ATLASSIAN_API_TOKEN>" -o <file> "https://irely.atlassian.net/rest/api/3/attachment/content/<id>"`
     Credentials come from the `atlassian` section of `JIRA_AI_CONFIG` (`email`+`apiToken`, else its `tokenFile` pointer), falling back to `~/.atlassian-token` (`email:token` on one line) or the environment (`ATLASSIAN_EMAIL` / `ATLASSIAN_API_TOKEN`). A token is created at https://id.atlassian.com/manage-profile/security/api-tokens.
   - Read the downloaded image/PDF directly (vision) and extract the exact error text / values into the analysis. Never guess at unread screenshot content.
   - **Order matters:** attachment download + read MUST complete BEFORE the §1.6 feasibility classification and before §1.5 finalizes `JIRA_BUILD`. On QC-reported tickets the description is often 1–3 lines and every load-bearing number lives in the PNGs — classifying first mis-verdicts the issue (refs: AP-24557 — the screenshots carry the exact documents and the −0.06 delta, so only the DB is genuinely missing; AP-24784/LB-139 — the error text exists ONLY in screenshots; AP-24785 — the real build stamp exists only in a screenshot).
   - **Credentials found in ticket content (description/comments/environment field) are never echoed** into any Jira comment, RCA, PR, log, or run output — quote the error/evidence, not the login (refs: AP-24793 env credentials in description; LB-139 logins in the environment field).
   - If no API token is configured and the attachment is load-bearing -> STOP and ask the operator for the token (one-time setup) or for the attachment's text.
6. **Help Desk (HDTN) evidence enrichment — OPTIONAL, supplementary (operator 2026-08-07).** An HD ticket is **never required** by this runbook. Many JIRAs have none, and that is not a gap, not an information request, and never a STOP. When one IS referenced (`HDTN-…` in the summary/description/comments, or a `helpdesk.irely.com` URL embedded anywhere), read it for **additional information only** — chiefly:
   - **WHERE THE DATABASE WAS RESTORED — the primary reason to open an HDTN.** IT records the restore location on the ticket's **`Database Copy` tab**, and/or posts it as a **comment or screenshot** on the HD ticket: the server and the restored database name. Harvest that pair and feed it straight into the **§1.7 step 0** `knownServers` match — this is the single highest-value item on the HD ticket, and it is often the only place the restore location exists (refs: AP-22155/HDTN-511903, AP-24801/HDTN-511883, AP-24771/HDTN-511632).
   - Supporting repro detail from the discussion thread and helpdesk-hosted screenshots.

   Mechanics:
   - Config: the `helpdesk` section of `JIRA_AI_CONFIG` → `{ "baseUrl": "https://helpdesk.irely.com/irelyi21Live", "cookie": "<session cookie header value>", "obtainedAt": "<date>" }`. The helpdesk has no API token — auth is the **user's browser session cookie**. Obtain it by logging into the helpdesk in a browser and exporting the session cookie, or let the runbook drive it: open a browser (Playwright) at the helpdesk, the user logs in, the run captures the cookie and saves it to the config. **This applies to every user of this runbook** — each user provides their own session cookie once, and refreshes it the same way when it expires.
   - With a cookie configured: fetch the HDTN ticket and read into the analysis: the **`Database Copy` tab** (server + restored database name — the primary target), the **discussion thread** (often contains the real repro, expected values, and dev/QA exchanges), **screenshots/attachments** (download with the same cookie, read directly — same never-guess rule as Jira attachments), and any **DB-restore note** posted as a comment or screenshot (server + database name → feeds the §1.7 step-0 `knownServers` match). All of it feeds the §1.6 EVIDENCE_SET.
   - **Retrieval mechanics (pinned 2026-08-06):** the ticket URL `…/#/HD/Ticket/?ticket=HDTN-…` is an SPA hash route — a plain cookie GET returns the app shell, NOT the thread (verified: probed REST routes 404). What works: (a) **direct image/attachment GETs** with the cookie (helpdesk-hosted image URLs embedded in a Jira description ARE fetchable this way — refs: AP-24771, AP-24802, whose Jira attachment fields are empty and every screenshot is helpdesk-hosted); (b) for the **thread and restore notes**, drive the SPA with Playwright using the saved cookie/storageState (same recapture pattern as the SharePoint config), then read the rendered page — ref: AP-22155, whose DB-restore screenshot exists ONLY on HDTN-511903 (the Jira has zero attachments).
   - **Helpdesk-embedded images in the Jira description are attachments in substance:** scan the description/comments for `helpdesk.irely.com` image URLs and fetch them with the cookie in the same pass as §1 step 5 — the empty Jira attachment field does not mean "no screenshots".
   - **No HDTN referenced at all → skip this step silently and continue.** Never treat a missing HD ticket as missing evidence, never ask the reporter for one, and never search the helpdesk for a ticket the JIRA does not name.
   - Cookie missing or **expired** (HTTP 401 / redirect to the login page) → **record the gap and CONTINUE on the evidence the JIRA itself carries** (operator 2026-08-07 — supersedes the 2026-08-06 STOP; the HD ticket is supplementary, so its unavailability must never halt an otherwise-analyzable JIRA). Report `helpdesk cookie expired — HDTN evidence not read; refresh required for fuller evidence` in the run output, and where the unread HDTN would have supplied the restore location, fall through to the normal §1.7 acquisition path (registry sweep → ticket backup/link → §1.6 DB information request). Never guess or brute-force a login; never store the helpdesk password anywhere.

7. **Sibling sweep (mandatory — the decisive evidence often lives on a sibling ticket):** run it as **two sweeps with different scopes**, because the things harvested here are not scoped alike (operator 2026-08-10). A restored database is a **customer-scoped** resource; a prior fix is a **defect-scoped** one. Keying both off one customer-wide JQL is what produced the AP-23288 failure mode: the WAMA 22.1 cohort returns 60+ tickets (page cap — the true cohort is larger), of which exactly ONE sits in the reported component (the subject ticket itself), leaving 59 "prior fixes" with no bearing on the defect.

   **7a. Customer sweep — DB and branch evidence ONLY.** One JQL over the cohort: same project + same customer + same fixVersion, plus any shared campaign label (e.g. `26.2AgrowstarIssue`). **No recency filter** — a restore note's usefulness tracks the freshness of the DB copy, not how recently the ticket moved (ref AP-22786: created 2026-01-26, but its `AP5 / WAMA01_0803DAN` note was posted 2026-08-05; any window keyed on ticket age would have hidden it). When the customer field is EMPTY (ref AP-24784), key the cohort on the environment URL host / campaign label instead; if neither exists, record `sibling sweep: no cohort key` and continue. Harvest ONLY:
   - **dedicated branch names** announced in comments (ref: AP-24727 — the correct branch `26.3DevCTRMFeatures_Sucden` is named only in sibling AP-24511's comment);
   - **DB restore notes / HDTN restore requests** and **backup links** (ref: AP-24802 — the restored Agrowstar DB is documented only on sibling AP-24801's HDTN-511883; ref: AP-23288/AP-24557/AP-24669 — the WAMA DB on AP5 is named only on sibling AP-22786). Request the DB on ONE ticket of the cohort, never per-ticket.

   Everything 7a produces is a **CANDIDATE only**. A DB harvested here was restored for a DIFFERENT ticket and must clear the §1.7 step 0 acceptance gate before the run treats it as this JIRA's database.

   **7b. Defect sweep — prior fixes ONLY.** Scope by DEFECT, not by customer: same project + the subject ticket's **component(s)** (for AP-23288: `VendorStatement*`), resolved within the last **12 months**, **any customer**. Harvest prior fixes of the same defect family and link them in the analysis. A customer-cohort ticket in an unrelated component is **not** a prior fix and must never be cited as one — a plausible-looking wrong precedent is worse than no precedent, because §1.5 and §1.6 build on whatever this step hands them. Subject ticket has no component → defer 7b until §1.6 has named the defective object, then key on that object name; if neither exists, record `defect sweep: no defect key` and continue.

   7a feeds §1.5 (branch) and §1.7 (DB acquisition/reuse); 7b feeds §1.6 (evidence).

STOP conditions:
- Jira issue cannot be read, or cloudId cannot be resolved -> STOP.
- Issue type is out of scope -> STOP.
- Issue status is not `Open` or `Reopened` -> STOP (no comment; report `OUT-OF-STATUS (<status>)`).
- (A missing HD ticket, or an unreadable one, is **NOT** a STOP condition — see step 6.)

## §1.5 Branch/Jira consistency check (mandatory gate — auto-aligning)

Runs immediately after §1, before §2 — this is the first point at which the Jira's version data is available to test the branch against. Its purpose is to catch the common failure where the repository is sitting on a branch left over from unrelated work — and to put the runbook on the **right** branch automatically, so the root-cause analysis reads the code the bug was reported against instead of stopping for an operator round-trip.

1. From the §1 Jira read, cache:
   - `JIRA_FIX_VERSION` = the `fixVersions` value (e.g. `26.3`).
   - `JIRA_BUILD` = the reported version/build — **harvested from ALL sources**, not only the build custom field: the field itself, the description, comments (QC retest env strings like `22.2.0709.1875 - 22.2Prod`), the **environment field** (env URLs such as `…/2710DEV`, `…/PROD2210` name the family), and build stamps read from screenshots (§1 step 5 runs first). The field alone is unreliable — in the 2026-08-06 dry run it lacked a parseable family token on the majority of the queue (refs: AP-24785 build only in a screenshot; AP-24412/AP-24683 build only in the description; LB-136 field malformed `24.21.…`; LB-139/AP-24784 family only in the environment URL).
   - `JIRA_CUSTOMER` = the customer field (e.g. `Sucafina`).
2. **Derive `EXPECTED_BRANCH` — Dev-first (operator rule 2026-08-06).** We fix on the **Dev** branch of the fix version; the reported (often Prod) build tells us where the bug was seen, not where the fix lands. Evaluate in order; every candidate must exist on origin **with an exact-case match** (`git -C <REPO_PATH> ls-remote --heads origin "<JIRA_FIX_VERSION>*"` — scan the list, never test one guessed name):
   1. **Customer-dedicated branch:** the customer has a dedicated branch for the fix version — `<fixVersion>Dev<CustomerToken>` (e.g. `24.2DevDnD`, `22.1DevWaMa` for Walter Matter) or a dedicated feature-family branch (e.g. `26.3DevCTRMFeatures_Sucden`) -> use it. `CustomerToken` comes from the **CUSTOMER_BRANCH_ALIASES** table below, else from fuzzy-matching the customer name against the ls-remote scan (ref: AP-23443 "Nutrition Services Tri-Co" → `22.2DevNutriServ`; AP-24446 "Victron" → `24.3DevVictronEnergy`; AP-24414 "Robson Oil" → `24.3DevRobsonOil`).
   2. **Mainline Dev:** else `EXPECTED_BRANCH = <fixVersion>Dev` (e.g. `26.2Dev`). **Sibling-family tiebreak (regression finding, ref LB-136):** before committing here, check whether the harvested JIRA_BUILD family token (or summary/env evidence) names an EXISTING sibling Dev-family branch of the same version (e.g. `24.2DevRC`, `24.2DevPreSales`) — if it does, run the artifact-presence check between `<fixVersion>Dev` and that sibling and prefer the branch that carries the defective artifact (equal content on both → mainline Dev is fine); rule 2 must not blind-commit while a more specific family is named in the evidence.
   3. **Prod exception:** the ONLY Prod branch this runbook works on is the Sunshine Gas customer branch `<ver>ProdSunshineGas` (operator 2026-08-06; verified 2026-08-06 the live branch is `24.3ProdSunshineGas` — the 24.2 name no longer exists on origin, so resolve the version from the ls-remote scan, never hardcode it). A Prod-stamped reported build does NOT move the fix to a Prod branch.
   4. **Reported-build fallback:** `JIRA_FIX_VERSION` is missing/TBD, or no rule-1/2 branch exists on origin -> parse `JIRA_BUILD`: strip the trailing `.<MMDD>.<seq>`; if the remaining family string is itself a branch on origin (exact case), use it.
   5. **Build-stamp → branch resolution:** the family string matches NO branch (e.g. `26.3FeatSucden`) -> resolve it instead of giving up: extract `<version>` + the customer/LOB token (drop the `Feat|Prod|Dev` marker), score the tokens against the `ls-remote --heads origin "<version>*"` list — a unique hit wins (`26.3FeatSucden` → `26.3DevCTRMFeatures_Sucden`, ref AP-24727). Cross-check via Azure DevOps **pipeline definition names** (`pipelines_get_build_definitions`, name `*<customer>*`): definitions are named `<branch>_<component>` and their builds carry the real `sourceBranch` (verified 2026-08-06: `26.3DevCTRMFeatures_Sucden_GCE` → `refs/heads/26.3DevCTRMFeatures_Sucden`). NOTE: app build stamps are NOT ADO build numbers — a `pipelines_get_builds buildNumber` lookup returns nothing (verified 2026-08-06); resolve by name as above.
   6. None of these resolves to a branch on origin -> **STOP** and report: the base cannot be derived from the Jira; the operator must supply TARGET_BRANCH explicitly (BLOCKED-BRANCH → §1.6 Information Request asks for the Fix Version).

   **Guards (2026-08-06 dry run + same-day regression):**
   - **Case-twin guard:** if the ls-remote scan shows branches differing ONLY by case (real example: AP repo `22.1ProdWaMa` vs `22.1ProdWama` — different heads; SqlScripts `22.1DevWAMA` vs `22.1DevWama`), never guess a casing — use the alias-table canonical name **for the repo being targeted**; alias casings are per-repo (the canonical `22.1DevWaMa` exists only in the AP repo — SqlScripts has ONLY the case-twins), so a canonical name absent from the owning repo's scan is the same STOP as no table entry: report the twins to the operator (refs: AP-22786, AP-23288, AP-24557, AP-24669).
   - **Artifact-presence corroboration:** when two candidates survive, prefer the one whose tree actually contains the defective artifact (`git ls-tree` / `git grep` on each candidate). Test ONLY branches present in the FRESH ls-remote scan — stale local remote-tracking refs (e.g. a deleted `origin/22.1ProdWama` still resolving locally) give outdated evidence.
   - **Artifact absent from every Dev candidate:** when the defective artifact exists ONLY on a branch rule 3 forbids (real case: `uspAPClearingDetailsWAMA.sql` lives only on `22.1ProdWaMa` — no Dev variant has it; refs AP-24557, AP-24669), do NOT silently fix on Prod and do NOT create the object on Dev — STOP and escalate as a §1.6 Information Request/operator decision naming the conflict (Dev-first rule vs artifact location).

   **CUSTOMER_BRANCH_ALIASES (customer field → branch token; extend as new customers appear):**

   | Customer field | Branch token / dedicated branch | Note |
   |---|---|---|
   | Walter Matter | `WaMa` → `22.1DevWaMa` | canonical casing exists in the AP repo ONLY; SqlScripts has only case-twins `22.1DevWAMA`/`22.1DevWama` → case-twin STOP there |
   | D&D / DnD | `DnD` (e.g. `24.2DevDnD`) | |
   | Sucden (26.3) | `26.3DevCTRMFeatures_Sucden` | Feat-stamped builds (`26.3FeatSucden.*`) map here |
   | Sucafina | `Sucafina` → `26.3DevSucafina` | `26.3DevCTRMFeatures_Sucafina` ALSO exists — fuzzy "unique hit" fails; this alias row pins the plain customer branch |
   | Nutrition Services Tri-Co | `NutriServ` | |
   | Victron | `VictronEnergy` | near-names `24.3DevVictron_AP-24103`, `24.3_Victron` are suffixed work branches, not candidates |
   | Robson Oil | `RobsonOil` | |
   | Sunshine Gas | `SunshineGas` → `<ver>ProdSunshineGas` | the ONLY Prod branch we work; live today: `24.3ProdSunshineGas` (24.2 name gone — resolve version from the scan) |
   | ECOM, Global Grain, NKG, Agrowstar, iRely | (no dedicated branch) | mainline `<fixVersion>Dev`; NKG demo tickets labeled `CTRMPreSales` → `<ver>DevPreSales` when it exists (ref AP-23349) |
3. Verdict:
   - TARGET_BRANCH was **explicitly provided**: on mismatch with `EXPECTED_BRANCH`, report a warning and keep the explicit parameter — it is a deliberate operator decision.
   - TARGET_BRANCH was **auto-detected** and equals `EXPECTED_BRANCH` -> continue to §2.
   - TARGET_BRANCH was **auto-detected** and mismatches -> **AUTO-SWITCH (not a STOP):** `git -C <REPO_PATH> fetch origin <EXPECTED_BRANCH>` → `git -C <REPO_PATH> checkout <EXPECTED_BRANCH>` → `git -C <REPO_PATH> pull --ff-only origin <EXPECTED_BRANCH>`; set `TARGET_BRANCH = EXPECTED_BRANCH`, recompute `FEATURE_BRANCH = <TARGET_BRANCH>_<JIRA>`, and report the switch (`<old branch> → <EXPECTED_BRANCH>`) in the run output. The dirty-tree handling from **Repository scope** still applies — unrelated edits are auto-stashed (labeled `JIRA-AI auto-stash …`, recorded in the run output, never popped automatically) before the checkout; only a failed stash remains a STOP.
4. Never create the target branch: the auto-switch only checks out a branch that already exists on origin. After this gate, §2/§3 analyze and edit the Jira's own branch, so the root cause is established against the code the bug was reported on.

## §1.6 Resolution feasibility gate (mandatory — classify BEFORE implementing)

Runs after §1.5, before §2. Its purpose is to stop the two dominant failure modes of automated runs measured on the live open queue (2026-08-04 audit of 65 open Bug-QC issues): **duplicating work that is already fixed** (25/65) and **attempting a static fix for a data/environment-dependent symptom** that can only be proven on the reported database (28/65). Every run MUST record its `FEASIBILITY` verdict in the run output.

**Step 0 — ALREADY-RESOLVED check (do this first):**
Re-read all §1 comments and linked PRs. The issue is **already resolved in substance** ONLY when ALL of these hold:
- (a) a Root Cause Analysis is on the ticket, AND
- (b) a fix exists — merged/active PR link, attached patch `.sql`, or a named fix commit, AND
- (c) **the LATEST dev/QA evidence passes** — a later FAIL, retest-failed comment, or a `Reopened` status voids an earlier PASS (recency rule; ref AP-24412: fix merged 07-09, QA FAILED 07-21 → still in scope), AND
- (d) **the fix content is still present on BOTH `EXPECTED_BRANCH` AND the branch family the latest QA evidence was produced on** (they can differ under Dev-first and sit in opposite states — AP-22099: Dev keeps the substance in rewritten form while Prod is reverted) — verify by CONTENT (diff/blob check of the changed objects), never by `git log --grep <JIRA>` alone: a revert commit also matches the grep and reads as "fix landed" (revert-detection rule; ref AP-22099: fix cherry-picked to 22.2Prod in PR 154760 on 07-09 and REVERTED in PR 155000 on 07-10 after a QC FAIL — the literal triple (a)+(b)+old-PASS matches, yet the issue is definitively unresolved and MUST be analyzed).
→ Only then report `ALREADY-RESOLVED (evidence: <comment/PR refs>)` and **STOP. Do not re-implement, do not create a branch, do not post any comment.** Duplicating an existing fix creates conflicting PRs and misattributes the work.
→ A `Reopened` issue is NEVER ALREADY-RESOLVED: reopening is itself the statement that the delivered fix did not hold — proceed to Step 0.5.

**Step 0.5 — FIX-DELIVERY CHECK (Reopened issues with a merged fix; ref AP-24412):**
When the ticket carries a merged fix PR but QA reports the symptom again, determine **whether the fix was actually in the build the tester used** before re-analyzing:
1. Resolve the fix commit(s): merge date/time and the branch they landed on (Azure DevOps PR data / `git log`).
2. Parse the tester's failing build stamp `<family>.<MMDD>.<seq>` (from the QA comment/screenshot): the build's branch family and cut date.
3. **Ancestry test, not branch-name match (regression finding, ref AP-24412):** the fix is in the build iff its commit is an **ancestor of the build's branch as of the cut date** — `git merge-base --is-ancestor <fix-commit> origin/<family>` — and the operative arrival date is the **earliest ancestry-path merge into the family branch**, NOT the PR's own merge date (AP-24412: PRs merged to `26.3Prod`/`26.3DevSucafina` on 07-06/07-09, but the content reached `26.3ProdSucafina` via the sync merge PR 155484 on **07-14**, before the 07-19 cut → fix WAS in build 0719.211). Transitive arrival through sync/CP merges counts; test content ancestry, never assume from the PR's target branch. Fix in build → **residual defect**; continue the analysis with the merged diff as the baseline (the residual cause must be sought beyond it; per-requirement verdicts from Step 1.5 sharpen this — requirements already passing confirm delivery, the still-failing one is the residual scope).
4. Fix NOT in the tested build (not an ancestor as of the cut) → the retest was premature. **Post ONE informational comment** stating: the fix was merged in PR `<id>` on `<date>` and reaches `<family>` via `<the sync path>`; the failing build `<stamp>` predates it; please retest on the first `<family>` build cut AFTER the **arrival-on-family** date (never the PR merge date). **This runbook creates NO PR and re-implements nothing in this case — provide the information only** (operator 2026-08-06).

**Step 1 — build the EVIDENCE_SET** from §1: exact error text, failing document numbers, expected-vs-actual values, repro steps — from the description, comments, downloaded/read attachments (§1 attachment step), helpdesk-hosted images, the environment field, and the §1 step-7 sibling sweep. Screenshots referenced but unreadable/absent count as MISSING evidence, not as evidence.

**Step 1.5 — enumerate ALL requirements (multi-requirement rule; ref AP-24801, AP-24802):**
A ticket often carries more than one distinct reported defect/requirement — one in the description and more in comments or screenshots (e.g. AP-24802: duplicated SQL charge lines AND a duplicated UI grid column). List every distinct requirement, analyze EACH, and fix as many as feasible in this run; give each its own verdict line in the run output and its own row in the §6 Developer's Testing block.
- **Cross-team routing comments are judged on evidence, not taken as a gate** (operator 2026-08-06; ref AP-24801: an RM comment says "Moving Jira to AR Team", but the screenshot shows an AP screen/flow): when the artifact/screenshot evidence sits in AP, proceed with the AP analysis and note the routing dispute in the RCA — do not silently drop the issue because a comment reassigned it.
- If a comment reports a **genuinely different issue** than the description, analyze what is in scope and apply Reporter Rule R1 (§6.5): a different issue belongs on a separate JIRA.

**Step 2 — STATIC-PROOF test.** Attempt to pin the root cause by reading the actual code on `TARGET_BRANCH`:
1. Locate the code path the EVIDENCE_SET implicates (screen → controller/store → SP/view/function). **Screen-first tracing (ref AP-24669):** identify the actual screen from the screenshot, then trace how that screen loads its data (view/store → SP) AND how the transaction writes its data (posting path/GL generation) — when the report and the writer disagree (e.g. AP Clearing Details shows a row the GL never got), reconcile BOTH code paths against the description before concluding a DB is needed; the DB request may still be valid, but the code validation comes first and sharpens what to ask for.
2. **Cross-object error attribution (ref AP-24784):** never confine the search to the object named in the error/stack — search the exact error message string REPO-WIDE (triggers, functions, CATCH-rethrow wrappers included). AP-24784's "cannot delete posted voucher" names `uspAPDeleteVoucher` line 347, but the RAISERROR lives in the `trg_tblAPBill` INSTEAD-OF-DELETE trigger re-raised by the proc's CATCH.
3. **Cross-module handoff check (ref AP-24802):** when the defective artifact is fed by another module (e.g. the SC/Scale module creates the voucher payables that AP displays), verify the upstream module's handoff (what it actually sends — e.g. the number of payable rows) before assuming the defect is on the consuming side; name the owning module in the analysis.
4. The root cause is **statically proven** ONLY when a concrete defect is identified in the code AND that defect deterministically produces the reported symptom for *any* data satisfying the repro preconditions — e.g. wrong column referenced, missing join/filter predicate, inverted guard, wrong format string/date write-format, missing field in an entity↔view mapping, error-207 bind mismatch. **This includes deterministic aggregation/sign/filter defects that happen to be reported against specific documents** — "wrong for the reported documents" does not force DB_REQUIRED when the arithmetic/filter error is fully visible in code and holds for any conforming row (refs: AP-23443 — sign/netting bug in `uspAPRptOpenClearing` doubles the receipt amount for any negative settle-storage row; AP-23288 — missing Cash Refund branch + a `ysnCancelledPayable != 1` NULL-killing predicate). In such cases classify STATIC and use the DB (when obtainable) only as the validation vehicle.
5. The root cause is **NOT statically provable** when the symptom genuinely depends on data state: rounding at specific quantities/amounts, posted/unposted transaction sequences, records created by older builds, upgrade failures on a particular database, "cannot reproduce on standard data", or the affected object exists in no repo copy that is both **current and on the valid deployment channel** for TARGET_VERSION (a stale copy in a non-deployed channel does not count — ref AP-24446: a pre-multi-company `uspAPRpt1096.sql` exists in SqlScripts, but SSDT is not the 24.3 channel and the deployed body must be scripted from the customer DB).

**Step 2.9 — DATA_FIX routing (R-DATAFIX-DB; applies when `ISSUE_CATEGORY = DATA_FIX`):**
The STATIC-PROOF test of Step 2 does not apply — a data fix is not a code defect, so there is no code path to pin. What replaces it:
1. Confirm the ticket really is a data correction: the current code produces correct results going forward, and the defect is the **rows already written** (typically by a bug since fixed — the issue type's own definition). If the code is still defective, this is a BUG in a Data Fix ticket: analyze the code defect, say so in the analysis, and apply **Reporter Rule R1** (§6.5) — the program fix belongs on its own JIRA, linked (Data Fix Guidelines, Foundational Guideline #5).
2. **Locate the linked program JIRA** (the root-cause code fix). Missing → do not stop; note it as a required link in the delivery comment and in the run output.
3. `FEASIBILITY` is **never `STATIC`** here: resolve to `DB_REQUIRED-ACTIONABLE` when a DB of the reported environment is reachable, else `DB_REQUIRED-BLOCKED` → ONE information request for the backup → STOP. The affected row set, its count, and every Standard 1–4 assertion in §3.6 can only be established on the real data.

**Step 3 — classify FEASIBILITY and act:**

| FEASIBILITY | When | Action |
|---|---|---|
| `STATIC` | Root cause statically proven AND the fix is verifiable without a database (or a reachable dev DB covers §3) | Continue to §2. |
| `DB_REQUIRED-ACTIONABLE` | Root cause is data/environment-dependent (Step 2.5), OR the fix touches SQL logic that writes into a UDT/table, OR the deployed object must be scripted from the reported DB — AND **the REPORTED environment's database** is reachable from the evidence: a `.bak` attachment, a download link (description, comments, or **environment field** — ref AP-23349), a `knownServers` match, or a sibling-ticket/HDTN restore note (§1 step 7a — a **candidate** only until it clears the §1.7 step-0 acceptance gate). A reachable backup of a DIFFERENT company/environment does NOT qualify (ref AP-24402: sibling TE2 backups exist but the symptom lives on ECOMProdCompany → BLOCKED); that is the same test the step-0 gate applies, so a candidate the gate rejects leaves the verdict at BLOCKED. A raised-but-unconfirmed restore request (e.g. "HDTN raised, will investigate when done") is **provisionally** actionable: if the §1.7 step-0 lookup (incl. the unnamed-server registry sweep) dead-ends, downgrade the recorded verdict to BLOCKED and note the pending request. | Run **§1.7** immediately — no information request. Restore/connect, reproduce, prove (BEFORE/AFTER), then continue to §2 using that DB as the §3 validation DB. (2026-08-06 dry run: 6 of 20 DB_REQUIRED issues were actionable — AP-23349, AP-24785, AP-24793, AP-22786, AP-24771, AP-24412.) |
| `DB_REQUIRED-BLOCKED` | Same root-cause classes, but no backup/DB of the reported environment is reachable from the ticket, its siblings, or the registry | Post the **INFORMATION REQUEST** comment asking for the DB backup (template below), then STOP. Ask on ONE ticket per customer cohort (§1 step 7), not per ticket; a **pending human request for the same customer DB** (even raised for a sibling's symptom) counts — report "awaiting DB since <date> (requested by <who> via <ref>)" instead of asking again. |
| `INFO_REQUIRED` | EVIDENCE_SET is insufficient to even locate the defect (no repro steps, no exact error text, referenced-but-missing attachments, no expected behavior) and cannot be derived from code | Post the **INFORMATION REQUEST** comment listing exactly the missing items (template below), then STOP. |
| `CANNOT-FIX` | The analysis concludes this run cannot deliver the fix: the defect is owned by another module's code (and the evidence supports that ownership), a won't-fix/by-design candidate, or blocked by a cross-team dependency. **Precedence:** when ownership evidence points elsewhere BUT a reachable DB could adjudicate it, `DB_REQUIRED-ACTIONABLE` wins — prove first on the DB, and post CANNOT-FIX only from the captured evidence (ref AP-22786: posting CANNOT-FIX on the AP-vs-IC assertion alone would repeat the won't-fix→reopen loop already on the thread). | Post ONE **CANNOT-FIX comment** (§6.5): the full analysis details, why it cannot be fixed here, and a concrete suggestion/recommendation (owning module + the exact artifact, or the dependency to resolve). Then STOP. (Operator 2026-08-06 — replaces the former silent skip.) |

**R-NOFIX-COMMENT — every run that does not deliver a fix leaves a comment (operator 2026-08-07).**
A run must never end silently on the ticket. Exactly ONE comment is posted per run, chosen by outcome:

| Run outcome | Comment posted |
|---|---|
| Fix delivered (branch pushed, or data fix delivered per §3.6) | **§6 RCA / Developer's Testing** — the RCA comment is reserved for a *successful* fix and is posted nowhere else |
| Needs information (`INFO_REQUIRED`, `BLOCKED-BRANCH`, missing/untestable acceptance criteria per §2) | **INFORMATION REQUEST** (template below) + `AP-AI-NeedInfo` label |
| Needs the database (`DB_REQUIRED-BLOCKED`, incl. every blocked `DATA_FIX`) | **INFORMATION REQUEST** scoped to the DB backup + `AP-AI-NeedInfo` label — one per customer cohort |
| Cannot be fixed here (`CANNOT-FIX`) | **CANNOT-FIX** comment with details + recommendation (§6.5 A) |
| Fix was already delivered but the tester's build predates it (Step 0.5) | **fix-delivery informational** comment (§1.6 Step 0.5.4) |
| Analysis completed but the run stopped for any OTHER reason — §3 validation FAIL, DB restore failure, unresolvable branch, an aborted implementation | **TRIAGE comment** (§6.5 D) — so the ticket carries what was learned instead of nothing |
| `ALREADY-RESOLVED` (§1.6 Step 0) | **nothing** — posting here would only add noise to a ticket that already has its RCA and fix |
| Out-of-type / out-of-status gate | **nothing** — the issue belongs to someone else's workflow |

Dedupe applies to every row above: re-read the comments first, and do not repost an unanswered equivalent (see the rules below).

**INFORMATION REQUEST comment (template + rules):**

Post ONE comment via `addCommentToJiraIssue` (contentFormat markdown) and add the label **`AP-AI-NeedInfo`** (additively — re-send existing labels alongside it, never overwrite):

```
# Information Request — automated analysis (JIRA-AI)

Automated analysis on branch `<TARGET_BRANCH>` could not <establish the root cause / verify the fix> from the evidence currently on this ticket.

**What was analyzed:** <1–2 lines: the code path read and what was ruled out.>

**Missing — please provide (only the items that apply):**
- [ ] Exact error message text (copy-paste, not a cropped screenshot)
- [ ] Step-by-step reproduction, including the specific document numbers (Voucher/IR/Contract/Load)
- [ ] Expected vs actual behavior/values
- [ ] Browser console (F12) / network trace at the moment of failure (for UI errors)
- [ ] **Database backup (`.bak`, compressed) of the reported environment** — or a restore-point/location we can pull — required because the symptom is data-dependent and does not reproduce on a standard database
- [ ] Fix Version (the field is currently empty/TBD — the target branch cannot be derived without it)

Once provided, re-run JIRA-AI on this issue; the analysis resumes from the new evidence.
```

Rules:
- **Dedupe guard (JIRA-AI's own requests only):** before posting, re-read the comments and labels. If an unanswered **JIRA-AI** information request for the SAME missing items already exists (or the `AP-AI-NeedInfo` label is present with no new evidence since), do NOT post again — report "awaiting info since <date>" and STOP. A **human** request for the same item (e.g. a dev's DB request via HDTN — ref AP-22155 / HDTN-511903) also counts: report "awaiting <item> since <date> (requested by <who>)" instead of re-asking.
- **Third-party analysis comments are last-resort input, not a gate (operator 2026-08-06; ref AP-24683):** a prior analyzer's comment (human or bot, e.g. a "Bug Analyzer Report") neither blocks this run nor substitutes for it — JIRA-AI performs its OWN independent analysis first and consults such comments only afterwards, to cross-check or to harvest facts it could not reach. Their unanswered info request does not trigger the dedupe guard; but before asking, re-verify each item against the ticket's own attachments — do not ask for evidence already visible in an unread screenshot (ref AP-24683: the sample voucher PIDE-80 was in the ticket's own screenshot all along). **Attachment unreadable to the automation account** (attachment-level permission denial, distinct from the MCP-403 the token workaround fixes — seen on AP-24683 att 1840317): treat it as MISSING for the analysis, and word the request as an ACCESS/re-upload ask ("attachment <id> is not readable by the automation account — please re-attach or paste the content"), never as an accusation that the evidence wasn't provided.
- Ask ONLY for items that are genuinely missing; pre-check each candidate item against the ticket (including read screenshots and the sibling sweep) first — ref AP-24557: the screenshots already named the documents and the measured delta, so the only missing item was the database.
- A `BLOCKED-BRANCH` case (missing/TBD fixVersion so §1.5 cannot derive a base) uses this same protocol — the missing item is the Fix Version.
- Every §1.6 STOP verdict (`ALREADY-RESOLVED`, awaiting-info, info-request-posted, `CANNOT-FIX`) MUST be recorded in the run output and, when a tracking file is in use (e.g. `jira-ai-open-resolution-tracking.md`), as a row/update there.
- Append the **Reporter Rules note** (§6.5) to any comment posted here when one of its rules applies.

## §1.7 Database acquisition & local restore (SQL Server) — run when FEASIBILITY = DB_REQUIRED-ACTIONABLE (or -BLOCKED once a backup arrives)

Purpose: get a restorable copy of the **reported** database onto the local SQL Server, bring it to the branch's schema level, and use it to (a) reproduce the symptom, (b) prove the root cause, and (c) satisfy §3's dev-DB validation mandate.

**Configuration — `SQLSERVER_CONFIG` (the `sqlServer` section of `JIRA_AI_CONFIG` = `%USERPROFILE%\.jira-ai-config.json`):**

**Purpose:** the SQL Server instance is needed ONLY when the JIRA carries an attached DB backup or a link to one — the config exists to define **where the AI restores that database** (and where the §3.5 `liquibase update`/rollback confirmation runs against it). It is never consulted otherwise.

All restore parameters come from the `sqlServer` section of the consolidated config file (user profile; NEVER stored in a repo, never committed, never pasted into Jira/Confluence). Section schema:

```json
{
  "server": "<machine>",
  "instance": "<instance, e.g. SQL2022>",
  "auth": "sql",
  "user": "<sql login>",
  "password": "<optional — stored here per operator choice; wins when non-empty>",
  "passwordEnvVar": "I21_SQL_PASSWORD",
  "backupStageDir": "C:\\i21DB\\backups",
  "dataDir": "C:\\i21DB\\data",
  "logDir": "C:\\i21DB\\log",
  "liquibaseLogDir": "C:\\i21DB\\logs",
  "dbNamePattern": "i21_{JIRA}_{CUSTOMER}",
  "postRestoreSafetyScript": "C:\\i21DB\\post-restore-safety.sql",
  "knownServers": [
    {
      "name": "<ticket name, e.g. ap3-sql>",
      "aliases": ["<other names/IPs tickets use>"],
      "server": "localhost",
      "port": 14333,
      "auth": "sql",
      "user": "",
      "password": "",
      "passwordEnvVar": "",
      "ssh": {
        "sshConfigAlias": "<Host alias in ~/.ssh/config, e.g. ap3-sql>",
        "host": "<gateway, e.g. rdg host>",
        "port": 22,
        "user": "<gateway login>",
        "keyPath": "",
        "localForward": { "localPort": 14333, "remoteHost": "<sql server ip>", "remotePort": 1433 }
      },
      "notes": "tunnel-first entry: SQL reachable only through the gateway"
    }
  ]
}
```

- Credentials: `auth` = `windows` (integrated) or `sql` (SQL Server Authentication). For `sql`, the login comes from `user` + `password` — the `password` field in this file **wins when non-empty** (operator choice 2026-08-05; acceptable because the file lives in the user profile, outside every repo); otherwise the environment variable named by `passwordEnvVar` is read. Never copy credentials from this file into a repo, Jira, Confluence, PR, or log.
- The **default local instance and the six default gateway-tunneled known servers (rdg gateway → wamahypercare, ap2-sql…ap5-sql, lesliefleet-sql) are pre-configured in the workstation file** — real hostnames/IPs/ports live ONLY there (and in `~/.ssh/config`), never in this runbook.

- `knownServers` (**known DB servers registry** — optional accuracy booster): the servers the AI is allowed to **look into when the JIRA says the DB was already restored somewhere** — an HDTN restore note, a description `DB-` line, or a comment naming a server and database (e.g. "restored on QA-SQL01 as `ECOMCompany_0731`"). Each entry maps a name (plus aliases) mentioned in tickets to real connection details, and may carry an optional `ssh` block: with `localForward` it is a **tunnel-first** entry (the SQL server is reachable only through the gateway — connect via `localhost,<localPort>`, starting `ssh -N <sshConfigAlias>` when needed); without it, SSH is the fallback transport when the SQL port is unreachable. SSH auth is key/agent-based (`keyPath` optional) — the gateway password is never stored in the file or prompted for inside a run; SQL credentials per entry follow the same `password`-field-wins rule as the main config. The registry is match-only: the AI never connects to (or SSHes into) a server that is not in this list.

- `server`/`instance`: connect to `server` or `server\instance` when instance is non-empty.
- `auth`: `windows` (integrated, default) or `sql` (`user` + password read from the environment variable named by `passwordEnvVar` — the password itself is NEVER stored in the file).
- `dbNamePattern`: restored DB name, e.g. `i21_AP-24754_ECOM` → `RESTORE_DB_NAME`. One restored DB per JIRA; if it already exists, REUSE it (do not re-restore unless the operator asks for a refresh).
- If `JIRA_AI_CONFIG` has no `sqlServer` section (and no legacy `.i21-sqlserver.json` exists) → STOP and ask the operator to fill it (one-time setup); do not guess server names or paths.

**R-DB-LEDGER-REUSE — reuse an existing restore before restoring anything (operator 2026-08-07).** Restoring a multi-gigabyte customer database that already exists somewhere is the most expensive avoidable step in a run. Before any download or restore, exhaust the reuse sources in step 0 below. Two hard constraints on this rule:
- **No ledger, no registry file, no DB log is maintained.** This runbook writes NO tracking file, index, or log of databases, restores, or servers. Reuse is discovered **fresh each run from live evidence** — the ticket, its siblings, the HD ticket's `Database Copy` tab, and a live `sys.databases` query against the configured `knownServers`. The `knownServers` entries in `%USERPROFILE%\.jira-ai-config.json` are operator-maintained connection details, not a run-written ledger; the runbook never appends to them.
- **Never publish local restore details to Jira.** A database restored on the **local workstation / local (Philippines) server** is a private working copy that nobody else can reach — its server name, database name, path, and connection details MUST NOT appear in any Jira comment, RCA, PR, or Confluence page. Record it in the **run output only**. Only a DB on a **shared** server that the team already knows about may be referenced in a comment, and then only by the server/database name the ticket or HD ticket already uses.

**R-DB-SLOT-LIMIT — at most TWO locally restored databases may exist at any time (operator 2026-08-11).** A restored customer database is multi-gigabyte and the workstation's disk is the binding constraint on a batch run, so local restores are a **pool of exactly 2 slots**. A third DB_REQUIRED JIRA does not restore, does not fail, and does not get an information request — it **waits**, and is picked up after a slot is released.

- **What occupies a slot:** an ONLINE database on the **local** instance (`server`/`instance` of `SQLSERVER_CONFIG`) whose name matches `dbNamePattern` — **the database alone**. Its retained backup archive in `backupStageDir` does NOT occupy a slot and is never counted against the pool (R-DB-KEEP-ARCHIVE): a compressed archive costs a fraction of the restored database's footprint, and keeping it is what makes a re-restore free instead of a multi-hour re-download. A database on a `knownServers` entry occupies **no slot** — it is a shared copy this runbook neither restored nor may drop, so §1.7 step 0 reuse is never blocked by a full pool (and is the reason to try step 0 first).
- **One slot per COHORT, not per JIRA.** One restore serves every ticket of a customer/environment cohort (§1 step 7a), so the whole cohort is analyzed against that single database before its slot is released. Never release a slot mid-cohort and re-restore the same backup for the next ticket in it.
- **Before any restore:** count occupied slots (`SELECT name FROM sys.databases` filtered to the `dbNamePattern` shape). Two occupied → set the run state `DB_QUEUED (waiting for a restore slot)` for that JIRA/cohort, record it in the run output, and move to the next JIRA. `DB_QUEUED` is an internal **scheduling** state, not a §1.6 verdict: `FEASIBILITY` stays `DB_REQUIRED-ACTIONABLE`, and **no Jira comment and no label is posted for it** — a queued ticket is not a blocked ticket, and an information request there would be false.
- **Release procedure (in this order — a slot is freed only when its work is genuinely finished):**
  1. **Completion check.** The cohort holding the slot has reached its terminal artifact — the §6 RCA comment, or the §6.5 triage/information-request/cannot-fix comment — for **every** ticket in it. Never drop a database whose ticket is still mid-analysis. Disk pressure is never a reason to cut an analysis short.
  2. **Harvest before dropping.** Write into the run output everything the database proved and nothing else records: the §1.7 step 3 BEFORE/AFTER queries with their result sets/row counts, the §3.7 tier-2 golden-set deltas, the §3.9 grid outcomes, and `DB_BUILD_VERSION`. After the drop none of it is re-derivable without re-downloading and re-restoring.
  3. **Rollback first, drop second.** Where §3.5 (`liquibase update` → rollback) or §3.6 (data fix → rollback) applies, the rollback must already have run and been verified, leaving the DB unfixed. **Dropping the database is NOT a substitute for the rollback proof** — the rollback is the evidence that the change is reversible, and a dropped DB proves nothing.
  4. **Drop:** `ALTER DATABASE [<db>] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;` then `DROP DATABASE [<db>];` and verify it is gone from `sys.databases`.
  5. **KEEP the backup archive — delete nothing in `backupStageDir` (R-DB-KEEP-ARCHIVE, operator 2026-08-11).** Releasing a slot drops the **database only**. The compressed archive stays exactly where it is, so the same cohort can be re-restored later without re-downloading multi-gigabyte customer data (a re-download costs hours and frequently needs a human to re-fetch an expired link — the very thing this rule exists to avoid). Assert only that the loose `.bak` is already gone, per the step-3a compaction; if one is still present, compress-and-delete it now. Record the archive that was retained and its path in the run output.
  6. Record `slot released: <db> (+<n> GB free)` in the run output.
- **Never drop what this runbook did not restore:** a database whose name does not match `dbNamePattern`, or one living on a `knownServers` entry, is out of bounds — no `DROP`, no file deletion, regardless of disk pressure. Same for a staged backup that does not belong to a slot this run owns.
- **The runbook never deletes a backup archive at all (R-DB-KEEP-ARCHIVE).** The ONLY file this runbook is permitted to delete in `backupStageDir` is a **loose `.bak` whose compressed archive it has just verified** (step 3a). Reclaiming archive space is an operator decision, taken outside a run — if disk is genuinely exhausted, that is reported in the run output as `backupStageDir at <n> GB — operator cleanup required`, never resolved by deleting evidence a future run may need.
- **Batch consequence:** `DB_REQUIRED` cohorts are processed **two at a time**; `STATIC`, `INFO_REQUIRED` and `CANNOT-FIX` tickets never wait on a slot and continue in parallel. Order the DB queue by yield — largest cohort and already-acquirable backups first — so each of the two slots covers the most tickets per restore.

**0. Already-restored database on a KNOWN SERVER (check FIRST — skips download and restore):**
Scan the §1 description, comments, **environment field**, **sibling tickets (§1 step 7)**, and — when an HD ticket is referenced — its **`Database Copy` tab, restore comment, or restore screenshot (§1 step 6)** for evidence that the reported DB was **already restored somewhere**: an HDTN restore-completion note, a `DB-` line, or any comment naming a server and/or database (patterns like "restored on/to `<server>` as `<dbname>`", "available on `<server>`", a `server\instance` + DB pair). A restore note on a SIBLING of the same customer cohort (§1 step 7a) counts as a **candidate** — one restored DB *can* serve the whole cohort, but only after the acceptance gate below confirms it holds this ticket's data (refs: AP-22786's `AP5 / WAMA01_0803DAN` note is the candidate for AP-23288/AP-24557/AP-24669; AP-24801's HDTN-511883 restore is the candidate for AP-24802).
- Match the named server against the `knownServers` registry (by `name` or `aliases`). On a match, verify the database exists there (`SELECT name FROM sys.databases WHERE name = '<dbname>'`; when only the customer is known, search `sys.databases` for a name containing the customer/JIRA). If found → it is a **CANDIDATE**; run the acceptance gate below before using it. **NOT found is the EXPECTED outcome for an older restore note (operator 2026-08-10)** — shared restore servers have finite disk and the restoring team reclaims space by dropping old copies, so a note more than a few weeks old usually points at a database that no longer exists. Record `step-0: <dbname> no longer on <server>` and fall through to step 1 without further investigation: this is routine housekeeping, not an anomaly, and it is exactly why the live `sys.databases` check — never the age of the ticket carrying the note — is the authority on whether a restore is still reusable (a January ticket can hold a note for an August restore, ref AP-22786).
- **Restore known to exist but server unnamed** (e.g. only "database restored" on the HDTN): sweep the `knownServers` registry itself — run the `sys.databases` name search (customer/JIRA pattern) on each registered server before falling through to acquisition (operator 2026-08-06). Record which server matched in the run output. Same acceptance gate applies.
- **ACCEPTANCE GATE — a candidate is not this JIRA's database until ALL THREE checks pass (operator 2026-08-10).** `sys.databases` name-existence proves *a* database is there, not that **this ticket's data** is in it. Every candidate reached through §1 step 7a was restored for a DIFFERENT ticket, frequently from a different environment and months apart (ref AP-23288: candidate `WAMA01_0803DAN`, an Aug-3 snapshot harvested from AP-22786 whose environment field reads `Hypercare01` / `Prod01`, while AP-23288's own environment field is EMPTY and its defect was reported 2026-03-12).
  1. **Environment agreement** — the sibling's environment must match the subject ticket's. This is the §1.6 `DB_REQUIRED-ACTIONABLE` test ("a reachable backup of a DIFFERENT company/environment does NOT qualify", ref AP-24402) made operative at the point of reuse; a candidate rejected here leaves the §1.6 verdict at `DB_REQUIRED-BLOCKED`. Subject environment EMPTY and the customer has exactly ONE known environment → accept. Subject EMPTY and the customer has MORE THAN ONE → do **not** guess: record `step-0 DB rejected: environment ambiguous (<list>)` and fall through to step 1.
  2. **Snapshot age vs the reported defect** — when the database NAME encodes a date (the `WAMA01_0803DAN` = 2026-08-03 pattern is common; also `_MMDD`, `_YYYYMMDD`, and `_<initials>` suffixes), compare it against the date the defect was reported. **Snapshot predates the report → reject on that basis:** record `step-0 DB rejected: snapshot <date> predates reported defect <date>` and fall through to step 1. The transaction that demonstrates the bug cannot be in a copy taken before the bug was reported, so letting check 3 discover this instead yields a bare `repro data absent` that hides the real reason. Name carries no parseable date → skip to check 3 and let the query decide.
  3. **Repro-data presence** — run ONE query proving the subject ticket's *own* reported artifact is present (for AP-23288: a posted Cash Refund inside the reported window). Present → accept, recording the query and its row count in the run output. Absent → record `step-0 DB rejected: repro data absent` and fall through to step 1. Never carry an ungated candidate into the step 3 BEFORE run, where a non-reproduction gets misread as "the hypothesis is disproven" when the truth is "wrong database".
  All three pass → set `RESTORE_DB_NAME` = that DB on that server and skip steps 1–2 entirely. A rejection is not a dead end: it only means this candidate is unproven, so the run continues down the normal acquisition path.
- **Tunnel-first entries (`ssh.localForward` present):** these servers are reachable ONLY through an SSH gateway — the tunnel is the primary transport, not a fallback. Connection order:
  1. Try `localhost,<localPort>` first — the tunnel may already be open from a previous run or a manually started session.
  2. Not open → start it: `ssh -N <sshConfigAlias>` in the background when the alias exists in `~/.ssh/config` (the `LocalForward` applies automatically), else the explicit form `ssh -N -L <localPort>:<remoteHost>:<remotePort> <user>@<host>`. Then connect via `localhost,<localPort>`.
  3. Starting the tunnel needs interactive authentication (no key/agent available) → ask the operator to open the tunnel (`ssh -N <alias>`) and retry `localhost,<localPort>`; do not embed or prompt for the gateway password in the run.
- **Unreachable known server → try SSH.** When the direct SQL connection to a matched `knownServers` entry (non-tunnel, or a tunnel that won't open) fails AND the entry has an `ssh` block:
  1. Test SSH connectivity (`ssh -i <keyPath> -p <port> <user>@<host> "echo ok"`, short timeout, key/agent auth — never an interactive password prompt inside the run).
  2. Preferred: open an **SSH tunnel** to the SQL port (`-L <localPort>:<remoteHost|localhost>:1433`) and connect through `localhost,<localPort>` — all §1.7/§3 queries then run through normal tooling unchanged. Fallback when tunneling is blocked: execute the queries **remotely** via `ssh … "sqlcmd -Q \"<query>\""` and capture the output.
  3. Record in the run output which transport was used (`direct` / `ssh-tunnel` / `ssh-remote-sqlcmd`); close tunnels the run itself opened when the run ends (leave pre-existing/operator-opened tunnels alone).
  4. SSH also fails (or the entry has no `ssh` block) → the server is unreachable: record it in the run output and fall through to step 1 (normal acquisition) — never guess alternate hosts/ports beyond what the registry entry defines.
- **Shared-server care:** a `knownServers` database is a shared environment, not a private copy. Reproduction/read queries are fine; the §1.7 safety script is NOT run there (assume the restoring team handled it — verify before any posting test), and **§3.5 update/rollback must not run against a shared server** (see §3.5) — restore a local copy instead when the confirmation is needed.
- Server named in the JIRA but **not** in the registry → do NOT guess a connection; record the unmatched server name in the run output (so the operator can add it to `knownServers`) and fall through to step 1.

**1. Acquire the backup (in priority order):**
1. **Jira attachment** — a `.bak` / `.zip` / `.7z` / `.rar` attachment on the issue. Download exactly like §1 image attachments: the Atlassian MCP is 403-blocked on attachment content, so use the API token from `~/.atlassian-token` (`curl -sL -u "<email>:<token>" -o <file> "https://irely.atlassian.net/rest/api/3/attachment/content/<id>"`). Stage into `backupStageDir`.
2. **Link in the ticket** — a SharePoint/network-share/Azure-blob/helpdesk (HDTN) URL in the description, comments, or the **environment field** (ref AP-23349: a `.bak` Azure-blob link with a long-lived SAS token sat in the environment field — common pattern otherwise: a `DB-` line in the description). Download to `backupStageDir`; if the link needs interactive auth, ask the operator to fetch it.
3. **Already staged locally — check this BEFORE downloading anything (R-DB-KEEP-ARCHIVE).** An archive in `backupStageDir` whose name matches the customer/JIRA/cohort (record which file + its date in the run output). Because slot release now keeps every archive, a cohort processed earlier in the same batch — or in any earlier run — has usually left its archive here, making a re-restore a local extract instead of a multi-gigabyte download. Treat a retained archive exactly like a freshly downloaded one: it still faces the §1.7 step 0 acceptance gate on environment agreement, snapshot age, and repro-data presence, and the step 2.6 version check. A stale archive is a candidate, never an authority.
4. **None obtainable** → §1.6 INFORMATION REQUEST comment asking for the DB backup → STOP.

Extract archives (`.zip`/`.7z`/`.rar`) in `backupStageDir` until a `.bak` is available. **Never delete the source archive after extracting it** — it is the retained copy (R-DB-KEEP-ARCHIVE); only the extracted `.bak` is disposable, and step 3a disposes of it once the restore is verified `ONLINE`.

**2. Restore (PowerShell + `sqlcmd`/`Invoke-Sqlcmd`, all values from `SQLSERVER_CONFIG`):**
1. `RESTORE FILELISTONLY FROM DISK = N'<bak>'` → capture the logical data/log file names.
2. ```sql
   RESTORE DATABASE [<RESTORE_DB_NAME>] FROM DISK = N'<bak>'
   WITH MOVE N'<logicalData>' TO N'<dataDir>\<RESTORE_DB_NAME>.mdf',
        MOVE N'<logicalLog>'  TO N'<logDir>\<RESTORE_DB_NAME>_log.ldf',
        STATS = 5;
   ```
   (Multiple data files → one MOVE per logical file. Never use REPLACE against an existing unrelated DB; the pattern-named DB is always a fresh or same-JIRA name.)
3. `ALTER DATABASE [<RESTORE_DB_NAME>] SET RECOVERY SIMPLE;` and verify `SELECT state_desc FROM sys.databases WHERE name = '<RESTORE_DB_NAME>'` = `ONLINE`.

**3a. Compact the backup artifact — zip the `.bak`, then delete the `.bak` (R-DB-KEEP-ARCHIVE, operator 2026-08-11).**
Runs immediately after step 3 confirms `ONLINE`, and ONLY then: the database is proven restorable, so the loose `.bak` has no further use, while the archive remains the cheap path back. An uncompressed `.bak` is typically 5–10× the size of its archive, and it is the single largest avoidable consumer of `backupStageDir`.
- **Acquired artifact was a raw `.bak`** (attachment or link that was not already an archive): compress it in place to `<same base name>.zip` in `backupStageDir`, **verify the archive** (it opens and lists the expected `.bak` entry at a plausible size), then **delete the `.bak`**. Never delete before the archive is verified — an unverified archive plus a deleted `.bak` is a lost database.
- **Acquired artifact was already an archive** (`.zip`/`.7z`/`.rar`) that step 1 extracted: keep the ORIGINAL archive untouched and delete only the **extracted** `.bak`. Do not re-compress what is already compressed, and never delete the archive the ticket supplied.
- **Restore FAILED or the DB is not `ONLINE`:** do not compact and do not delete anything — the `.bak` is still needed for a retry or for diagnosing the failure.
- Record in the run output: the archive path retained, the `.bak` deleted, and the space reclaimed.
- The archive is retained indefinitely from here on: it survives the §3.5/§3.6 rollback, the slot release, and the end of the run (R-DB-KEEP-ARCHIVE).

4. **Post-restore safety (MANDATORY before any test):** run `postRestoreSafetyScript` against the restored DB. A restored customer database contains live integration endpoints and credentials; the script MUST neutralize outbound side effects — disable/blank SAP & API interface endpoints, SMTP/email settings, scheduled-job triggers, and payment/EFT export targets. Never run posting tests against a restored DB whose integrations have not been neutralized, and never expose restored customer data outside the local machine.
5. **Schema alignment:** run `liquibase update` against `<RESTORE_DB_NAME>` using the `TARGET_BRANCH` changelog so the database is at the code branch's schema level. A failing update here is itself evidence (upgrade-defect tickets typically fail exactly here — capture the failing changeset ID and error).

**2.6 DB version check — `tblSMBuildNumber` vs TARGET_BRANCH (mandatory for every DB this runbook uses, restored or `knownServers`):**

```sql
SELECT TOP 1 strVersionNo FROM tblSMBuildNumber ORDER BY intVersionID DESC;
```
- `DB_BUILD_VERSION` = that value (e.g. `24.2.0803.1622`). Take its **main and major** components only — `24.2`.
- Compare against `TARGET_VERSION` (the numeric prefix of TARGET_BRANCH — `24.2` from `24.2Prod`, `26.3` from `26.3DevCTRMFeatures_Sucden`). **Match on `<main>.<major>` ONLY** — build and revision (`.0803.1622`) are expected to differ and are never compared. A customer DB is always some builds behind the branch; that is normal.
- **Match** → continue; record `DB version <DB_BUILD_VERSION> ≈ branch <TARGET_VERSION> (main.major match)` in the run output.
- **Mismatch** (e.g. DB `22.1.…` against branch `24.2Dev`) → **STOP** and report `DB-VERSION-MISMATCH (db <main.major> vs branch <main.major>)`. Do not analyze, do not fix, do not run a data fix against it: the schema and the code disagree, so every BEFORE/AFTER result would be meaningless and any data fix would be written against the wrong shape. Post the §6.5 D triage comment naming both versions, so the operator can request the right backup or correct TARGET_BRANCH.
- `tblSMBuildNumber` missing/empty → record `DB build version not determinable` and continue for a read-only reproduction, but treat it as a **hard STOP for `ISSUE_CATEGORY = DATA_FIX`** (§3.6 requires the build stamp for the template's `@strCurrentBuildNo` compatibility guard).

**3. Root-cause PROOF algorithm (BEFORE/AFTER — this is what turns "plausible" into "proven"):**
1. Script the reproduction from the EVIDENCE_SET — the exact documents/values named in the ticket (e.g. `EXEC uspAPPostBill @billId = <the reported voucher>`, or the report view filtered to the reported document numbers).
2. **BEFORE:** run the reproduction on the restored DB with the pre-fix code/objects → capture the output. It MUST show the reported symptom. If it does NOT reproduce → the hypothesis is disproven; return to §1.6 (possibly INFO_REQUIRED — the ticket's evidence was insufficient or the environment differs).
3. Apply the code fix (§3) and deploy it to the restored DB (`liquibase update` for SQL objects).
4. **AFTER:** re-run the *identical* reproduction → capture the corrected output.
5. The BEFORE/AFTER pair is the proof: BEFORE = Root Cause evidence, AFTER = Developer's Testing evidence (§6). Include the concrete query + both result sets (or row counts/values) in the §6 comment.

STOP conditions:
- `SQLSERVER_CONFIG` missing → STOP (one-time operator setup).
- Restore fails (disk space, corrupt backup, version mismatch — e.g. backup from a newer SQL Server than local) → STOP and report the exact restore error; ask the operator whether to upgrade the local instance or request a compatible backup.
- Backup unobtainable → INFORMATION REQUEST comment (§1.6) → STOP.
- `DB-VERSION-MISMATCH` at step 2.6 (main.major differ) → STOP with the §6.5 D triage comment.

## §1.7a Runtime reproduction on a provided app environment (R-RUNTIME-REPRO) — OPTIONAL, only when APP_ENV was provided

**This runbook never provisions, builds, deploys, or configures an i21 application environment.** §1.7a runs only when the operator passed an existing `APP_ENV`, and it exists for one purpose: to reach the symptoms SQL alone cannot prove — screen behavior and field state, ExtJS/UI defects, document/PDF rendering, and the exact client-side error text.

**TRIGGER:** `APP_ENV` provided AND the EVIDENCE_SET contains a UI-level, render-level, or HTTP-level symptom. Otherwise skip.

1. **Version validation (fail-closed on the evidence, not on the run).** Resolve `APP_ENV_VERSION` from the running app (login/about page, or the version stamp the environment exposes). It MUST match, on **main.major only**:
   - `TARGET_VERSION` (the branch being fixed), AND
   - `DB_BUILD_VERSION` from §1.7 step 2.6 (the database the app is pointed at), when a DB is in play.
   Mismatch → **discard everything observed on that environment**, report `APP_ENV version <x> ≠ DB <y> / branch <z> — runtime evidence discarded`, and continue the run on code + DB evidence alone. An environment on the wrong build reproduces (or fails to reproduce) somebody else's bug.
2. **Reproduce** with Playwright driving `APP_ENV`: follow the ticket's repro steps to the failing action. Capture the **browser console (F12)**, the **network trace** of the failing request/response, the rendered screen state, and a screenshot at the moment of failure.
3. **Correlate with the database** when one is connected: run an Extended Events / Profiler capture scoped to that database across the failing action, so the client error can be tied to the actual statement and parameters that produced it.
4. Fold the captured error text, payload, and screen state into the `EVIDENCE_SET`, then re-enter §1.6 — a symptom that was `INFO_REQUIRED` because "the error exists only in a screenshot" frequently becomes `STATIC` once the real error text and stack are captured here.
5. **Read-only discipline:** never post, save, approve, delete, or otherwise mutate data on an environment that is not a restored copy under the operator's control. If reproducing genuinely requires a write, do it only against a local restore, and say so in the run output.
6. Any failure of §1.7a — environment unreachable, login fails, version mismatch, repro not reachable — is **never a STOP**. Record it, disclose it in the §6 RCA, and continue.

## §2 Check the acceptance criteria

Extract and cache `ACCEPTANCE_CRITERIA` from the Jira issue.

1. Read the **Acceptance Criteria** from the Jira (a dedicated field, a section in the description, or an explicit checklist in the comments). Capture each criterion as a discrete, testable item.
2. IF no acceptance criteria are present or they are ambiguous/untestable:
   - Derive candidate acceptance criteria from the issue description and expected behavior, and record that they were **derived** (not authored on the ticket).
   - If the intent still cannot be determined well enough to implement and test -> this is `FEASIBILITY = INFO_REQUIRED`: post the §1.6 **INFORMATION REQUEST** comment (dedupe guard applies) listing the missing items, then STOP and report that acceptance criteria are missing/insufficient.
3. Normalize `ACCEPTANCE_CRITERIA` into a numbered checklist. Each item MUST be verifiable by a concrete developer test (a query result, a screen behavior, a value, a log line, a `liquibase update` result).

4. **DATA_FIX form (ISSUE_CATEGORY = DATA_FIX).** The acceptance criteria of a data fix are always at least these, derived even when the ticket states none — each is verifiable by a query result in the §3.6 dry run:
   1. The rows the ticket reports are corrected (name the documents).
   2. The number of rows changed equals the number of rows the analysis identified as having the issue — no more (Standard 1).
   3. Voucher / payment / GL integrity still holds for every affected record (Standards 2–4, whichever apply).
   4. The script is idempotent and non-committing as delivered (`@ysnCommit = 0`, `tblAPDataFixLog` guard intact).

RESULT OF §2:
- `ACCEPTANCE_CRITERIA` = numbered, testable checklist. This drives both the implementation (§3, or §3.6 for a data fix) and the **Developer's Testing** block (§6).

## §3 Apply the acceptance criteria (implement + validate) — BEFORE the branch push

Implement the change in `REPO_PATH` so that every item in `ACCEPTANCE_CRITERIA` is satisfied. Then validate. **Only if every applicable check passes with no issue** does the runbook continue to §4.

**ROUTING — `IS_DATAFIX_CASE = true` (ISSUE_CATEGORY = DATA_FIX):** this section's code-change path does NOT apply. There is no repository edit, no CHANGESET, no Liquibase changeset, and no §3.5 confirmation. Go to **§3.6**, which authors, validates, tests and rolls back the data-fix script, and is terminal for the run (§4/§5 are skipped — see §3.6 step 7).

1. **Implement** the minimum change that satisfies each acceptance criterion. Do not introduce unrelated edits. Trace every edit to a specific acceptance-criteria item.
2. **Collect CHANGESET** = the set of changed files (working tree + staged) and their effective diffs (`git status --porcelain`, `git diff`, `git diff --cached`). Set `IS_LIQUIBASE_STANDARD_CASE = true` if any changed file is a SQL-script file.

VALIDATION GATE (MANDATORY):

- Run repository-appropriate static validation for changed files.
- For application code (any `.cs`, `.js`, `.ts`, `.tsx` changed): run IDE lints / the project linter for the changed files; run a fast targeted build/test for the changed project when one exists.
- For Liquibase/SQL (`IS_LIQUIBASE_STANDARD_CASE = true`): apply the full Liquibase standard compliance rules (§A–§J of `JIRA-PR-Automation.md`). **EXCEPTION — `IS_PRE_LIQUIBASE_BRANCH = true` (R-LB-24.1-TARGET):** on a < 24.1 target branch only the conflict-marker scan and the §J binding check below apply; the changeset mechanics (§A–§I) are skipped because the change is a direct SqlScripts SSDT edit, and the schema-change confirmation is the §3.5 case C execute-then-restore. All other bullets:
  - Search changed SQL for unresolved conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
  - Fail if any **new** changeset (schema OR `runOnChange` logic) uses a version-style ID matching `:[0-9]+\.[0-9]+(\.[0-9]+)?` — re-ID to a fresh timestamp before commit.
  - Confirm correct folder/file placement, `--comment: <JIRA>`, `endDelimiter:GO` where required, preconditions where the object may already exist, and a valid rollback.
  - Confirm no deployed one-time DDL changeset was modified in a way that changes its checksum.
  - **Column/identifier-binding check (mandatory):** for every changed SP/function/view, resolve each column referenced against a UDT/table/table-variable (INSERT column lists, `INSERT … EXEC` targets, SELECT-list aliases consumed downstream, `@var` of a UDT type) back to its `CREATE TYPE` / `CREATE TABLE` definition and confirm the name exists **exactly**. Fail on any unresolved name.
  - Apply `beautify 3.md` checkpoints to touched Liquibase SQL files.
  - **Schema-change confirmation (`liquibase update`) is governed by §3.5** (operator direction 2026-08-05): when a database for this JIRA is known (a §1.7 restored DB exists), the confirmation runs **asynchronously on a separate agent** (update → rollback verification, DB left rolled back, logs tracked, result commented on the PR) while this run continues; when NO database is known, the update is **skipped without stopping** and the §6 RCA comment MUST disclose it. In both cases the **§J static column/identifier-binding resolution remains the enforced fail-closed gate** for any changed logic object that writes into a UDT/table (bind-time error 207 class) — a §J failure is still a hard §3 FAIL.
  - When `FEASIBILITY = DB_REQUIRED-ACTIONABLE` (or -BLOCKED with a backup since obtained): complete the §1.7 BEFORE/AFTER proof — the AFTER run on the restored DB is the acceptance evidence; a fix whose AFTER run still shows the symptom FAILS this gate.
- **Regression impact (§3.7) — mandatory when CHANGESET contains a SQL logic object or a code artifact with resolvable callers.** The §3 proof above establishes that the *reported* case is now correct; it says nothing about every other row the same object serves. §3.7 closes that: tier 1 (static caller graph + contract gate) is fail-closed and always runs; tier 2 (golden-set differential) runs when a §1.7 database is available and produces a review-blocking finding on any unexpected delta. **§3.7 requires no application environment** — see below.
- **Acceptance verification:** confirm each `ACCEPTANCE_CRITERIA` item is satisfied by the implemented change. Record the concrete evidence (query result, screen behavior, value) that will populate the **Developer's Testing** block in §6.

TECHNICAL DEBT GATE (when ISSUE_CATEGORY = TECHNICAL_DEBT):
1. Linter pre-check: run static validation for all changed files; record output.
2. Dependency check: identify every dependency the change requires (types, base classes, interfaces, endpoints, routes, ExtJS classes/components, stored procedures, views, Liquibase tables/columns/changesets, config keys) and verify each exists in the repo or is part of CHANGESET. For UDT/table/column dependencies apply the exact-binding check — a renamed-but-self-consistent identifier is a MISSING DEPENDENCY.
3. Continue only if there are **no new linter errors** AND **all dependencies resolve**; otherwise STOP.

RESULT OF §3:
- **PASS (no issue):** continue to §4.
- **FAIL:** STOP. Report the failing check(s) / unsatisfied acceptance item(s) and the offending file(s)/identifier(s). Do not create the feature branch or push.

## §3.5 Schema-change confirmation — async `liquibase update` + rollback verification

**Purpose:** `liquibase update` is used ONLY to **confirm that the schema/logic changes applied in §3 deploy successfully** (and roll back cleanly) — it is a confirmation function, not a general gate, and it must never block the main run.

**TRIGGER:** `IS_LIQUIBASE_STANDARD_CASE = true` (the CHANGESET contains a Liquibase schema or logic fix). **Routing:** `IS_PRE_LIQUIBASE_BRANCH = true` (TARGET_VERSION < 24.1 — no Liquibase on that branch) → go directly to **case C** (execute-then-restore); otherwise cases A/B below.

**Decision — is a database KNOWN for this JIRA?** A DB is known when `RESTORE_DB_NAME` already exists on the configured instance (`SQLSERVER_CONFIG`), or the JIRA carries an attached/linked backup that §1.7 restored (or can restore now).

**Shared-server guard:** when the JIRA's DB lives on a `knownServers` shared server (§1.7 step 0) rather than the local instance, **do NOT run the update/rollback confirmation against it** — mutating a shared restore server invalidates other people's testing. Either restore a local copy from the same backup for the confirmation, or record `liquibase update NOT run — JIRA DB is on shared server <name>` in the §6 RCA (same disclosure path as case B) and let the reviewer decide.

**A. Database KNOWN → run the confirmation on a SEPARATE AGENT (async):**

Launch a background agent with the parameters below and **continue the main run immediately** (§4–§6, and the next JIRA when running a batch — the main flow never waits for the confirmation).

Agent procedure (all logs under `<liquibaseLogDir>\<JIRA>\`, timestamps UTC):
1. **Update:** run `liquibase update` for the `TARGET_BRANCH` changelog against the JIRA's DB — point at it with a command-line `--url "jdbc:sqlserver://<server[\instance]>;databaseName=<RESTORE_DB_NAME>;…"` (or a local, uncommitted properties override); NEVER edit the repo's `liquibase.properties`. Capture the full console output to `update-<UTC timestamp>.log`. Record: changesets executed, duration, SUCCESS/FAIL, and on failure the failing changeset ID + error text.
2. **Rollback verification (only when the update SUCCEEDED):** run `liquibase rollback-count <N>` where `<N>` = the number of changesets this JIRA added, so the rollback path written in §3 is proven to actually work. Capture to `rollback-<UTC timestamp>.log`.
3. **Leave the DB rolled back — do NOT re-apply.** After a successful rollback the database stays in the pre-fix (rolled-back) state; the runbook never runs `liquibase update` again to restore the fix. The §1.7 BEFORE/AFTER evidence was already captured in §3, and the actual deployment happens through the PR/release pipeline — a later re-test simply re-runs the update.
4. **Comment the result on the PR:** find the PR whose source branch is `<FEATURE_BRANCH>` (Azure DevOps MCP, e.g. `repo_list_pull_requests_by_repo_or_project` filtered by source branch) and post ONE PR thread comment containing: ✅/❌ update result (changesets executed, duration), ✅/❌ rollback result, a note that the DB was left rolled back, the log file paths, and — on any failure — the failing changeset ID plus a short error excerpt from the log. (JIRA-AI itself creates no PR; the PR is normally created afterwards by the PR/propagation runbook. **If no PR exists yet when the agent finishes**, post the same result block as a follow-up comment on `<JIRA>` instead and note in the run output that the PR comment is still owed.)
5. **Any failure is a review-blocking finding, not a silent pass:** the ❌ comment names the failing changeset and error; the operator/reviewer decides the follow-up. The agent never deletes the pushed branch and never edits code.

**B. Database NOT known (no restored DB, no attachment/link):**
- Do NOT run `liquibase update`, and do NOT stop.
- The §6 RCA comment MUST include the disclosure line: `Schema validation: liquibase update NOT run — no database is known/available for this JIRA.` (§J static binding remains the enforced fail-closed check from §3.)

**C. Pre-Liquibase target branch (`IS_PRE_LIQUIBASE_BRANCH = true`, TARGET_VERSION < 24.1) — execute-then-restore confirmation (R-LB-24.1-TARGET):**

There is no changelog to `liquibase update` on a < 24.1 branch — the confirmation instead proves that the changed script **executes successfully on the JIRA's database**, then leaves that database **unfixed** (deployment happens through the release pipeline, exactly as case A leaves the DB rolled back).

- **DB known** (a §1.7 restored DB, or a `knownServers` DB named on the JIRA):
  1. **Save the pre-fix state:** script out the current definition of every object the CHANGESET alters (`sp_helptext` / `OBJECT_DEFINITION()` / SSMS-equivalent scripting) to `<liquibaseLogDir>\<JIRA>\prefix-<object>-<UTC timestamp>.sql` BEFORE executing anything.
  2. **Execute the changed script(s)** against the JIRA's DB and confirm success — no compile/bind errors (the error-207 class §J guards against), object created/altered cleanly. Capture the console output to `<liquibaseLogDir>\<JIRA>\execute-<UTC timestamp>.log`.
  3. Run the AFTER verification (the §1.7 BEFORE/AFTER reproduction) while the fix is applied, if not already captured in §3.
  4. **Restore the saved pre-fix definitions** so the DB is left unfixed. Verify the restore executed cleanly. A failed restore is a review-blocking finding reported immediately (the DB was left in a fixed/partial state — say so explicitly, never silently).
  5. Report the result like case A: ✅/❌ execute result, ✅/❌ restore result, log paths — as a PR comment when a PR exists, else as a follow-up comment on `<JIRA>`. This sequence IS permitted on a shared `knownServers` DB precisely because the object is restored to its pre-fix state in the same session (the case-A shared-server guard exists to prevent leaving a shared DB mutated — the restore step removes that risk); still record `shared server — executed and restored` in the run output.
- **DB NOT known:** skip without stopping; the §6 RCA MUST disclose: `Schema validation: script execution NOT confirmed — no database is known/available for this JIRA (pre-24.1 branch, no Liquibase).` §J static binding remains the enforced fail-closed check.

## §3.6 Data fix authoring, validation, test and rollback (R-DATAFIX) — when ISSUE_CATEGORY = DATA_FIX

**Purpose:** produce a data-fix script that corrects the reported rows, prove on the real database that it corrects exactly those rows and nothing else, and **leave the database unfixed** — the same discipline §3.5 applies to schema changes. Deployment to the customer is a separate, human-owned act.

**PRE-REQ (all mandatory — any miss is a STOP):**
- `FEASIBILITY = DB_REQUIRED-ACTIONABLE` and §1.7 has produced a usable database (R-DATAFIX-DB — a data fix is never authored without the data).
- §1.7 step 2.6 passed: `DB_BUILD_VERSION` is known and its `<main>.<major>` matches `TARGET_VERSION`.
- The two policy sources have been read and are applied in full: the **JIRA Datafix Template** (page 434602044) and the **Data Fix Guidelines** (page 503382346).

### 1. Author from the template — never from scratch

The script MUST be the JIRA Datafix Template verbatim, with only the designated regions filled in. The template supplies, and the delivered script must retain unmodified:
- the `tblAPDataFixLog` create/alter block (audit trail),
- `BEGIN TRY / BEGIN TRANSACTION … END TRY / BEGIN CATCH … ROLLBACK` (automatic rollback on any error),
- the **idempotency guard** — an existing `tblAPDataFixLog` row for this `@fileName` raises and aborts, so the fix cannot be applied twice,
- the log INSERT capturing `strJIRAId`, `strAuthor`, `strRemarks`, `strBuildNumber`, `dtmDateExecuted`, `strFileName`,
- the **build-compatibility CATCH message** comparing the executing DB's build to `@strCurrentBuildNo`,
- the `@ysnCommit` switch and its COMMIT/ROLLBACK tail.

Header values:

| Variable | Value |
|---|---|
| `@strJiraKey` | `<JIRA>` |
| `@strAuthor` | the run operator's name (never a bot name — a person owns every data fix) |
| `@strRemarks` | one line: what the fix corrects |
| `@fileName` | `<JIRA>DataFix.sql` (= `DATAFIX_FILE`) |
| `@strCurrentBuildNo` | **`DB_BUILD_VERSION` from §1.7 step 2.6** — populated, never left `''`. An empty value makes the template's compatibility guard inert (it would compare against a blank), which is a §3.6 FAIL |

Everything the fix does goes inside the template's `BEGIN DATA FIX HERE` region, in this order (Data Fix Guidelines, "Putting it together"):

### 2. Standards 1–4 (mandatory, from the Data Fix Guidelines)

- **Standard 1 — row-count validation.** The **first result set** is the analysis script: it identifies the rows with the issue, captures `@numberOfRecordsWithIssues = @@ROWCOUNT`, prints the count, and **prints the identifiers** of every affected record (`strBillId`, `strPaymentRecordNum`, …) so QC can spot-check them against the reported transactions. Every DML then captures `@@ROWCOUNT` immediately, and a mismatch against the analysis count `RAISERROR`s and rolls back.
- **Standard 2 — voucher total integrity.** If the fix touches any quantity/amount column on `tblAPBill` / `tblAPBillDetail`, verify **before commit** that the header total still equals `SUM(detail total + tax)` for every affected voucher, tolerance `0.01` (all financial columns are `NUMERIC(18,6)`). Any variance → `RAISERROR` + rollback.
- **Standard 3 — payment total integrity.** If the fix touches any quantity/amount column on `tblAPPayment` / `tblAPPaymentDetail`, verify `dblAmountPaid = SUM(dblPayment + dblInterest - dblDiscount)` across the payment's details, tolerance `0.01`. Any variance → `RAISERROR` + rollback.
- **Standard 4 — GL integrity for posted transactions.** If any affected row is posted (`ysnPosted = 1`) and the fix changes a quantity/amount, verify for each affected `strTransactionId` that `SUM(dblDebit) = SUM(dblCredit)` over active entries (`ysnIsUnposted = 0`, `strModuleName = 'Accounts Payable'`), tolerance `0.01`, and that the AP-side GL total reconciles to the new header total. Any variance → `RAISERROR` + rollback.
  **Preferred approach for posted records:** unpost → fix → repost **through the same stored procedures the application uses**, rather than writing to `tblGLDetail` directly. Only fall back to a direct GL update when unpost/repost is genuinely not feasible; state that reason in the delivery comment, and Standard 4 then becomes non-waivable.

### 3. Additional fail-checks (R-DATAFIX extensions — validated statically on the authored script before it is ever executed)

Each is a hard FAIL: fix the script and re-validate. These exist because an automated author needs guardrails a human reviewer would otherwise supply by eye.

| # | Check | Rule |
|---|---|---|
| S5 | **No unbounded DML** | Every `UPDATE`/`DELETE`/`INSERT…SELECT` must be keyed to the analysis result set (a `#tmpDataWithIssues`-style temp table of primary keys, joined explicitly). A DML with no key-bound `JOIN`/`WHERE` is an automatic FAIL, however correct its intent looks |
| S6 | **Single scope resolution** | The analysis SELECT and the DML must resolve the **same key set** — the DML joins the temp table the analysis populated. Two independently-written predicates that "should" match are a FAIL (they drift, and Standard 1's count assertion then passes on the wrong rows) |
| S7 | **No schema DDL** | No `CREATE`/`ALTER`/`DROP` against business objects. The ONLY DDL permitted is the template's own `tblAPDataFixLog` block. Schema change belongs in Liquibase (§3.5), never in a data fix |
| S8 | **No mass-destructive constructs** | No `TRUNCATE`, no `DELETE FROM <table>` without a key predicate, no `UPDATE` without a `FROM`/`WHERE` binding, no writes across a linked server or another database, no `sp_MSforeachtable`, no dynamic SQL that builds a DML statement from unvalidated input |
| S9 | **Pre-image capture** | Before the DML, `SELECT` the full pre-image of every row about to change into a printed result set (keys + every column the fix will modify, old value labelled). This is the human's undo path and QC's before/after reference; a fix that cannot show what it overwrote is not deliverable |
| S10 | **Posted-record guard** | If any affected row has `ysnPosted = 1` and the fix touches an amount/quantity, Standard 4 verification MUST be present in the script. Its absence is a FAIL — not a warning |
| S11 | **Build stamp populated** | `@strCurrentBuildNo` = `DB_BUILD_VERSION` (§3.6 step 1). Blank or hardcoded-to-something-else is a FAIL |
| S12 | **Ships with `@ysnCommit = 0`** | The delivered artifact MUST have `@ysnCommit = 0`. Never hand over a script that commits on first execution — the person applying it to the customer database makes that decision, deliberately, after their own dry run |
| S13 | **§J binding still applies** | Every column/identifier the script references resolves exactly against the live `CREATE TABLE` / `CREATE TYPE` definition on the connected DB (the §3 fail-closed rule, unchanged). A data fix authored against a column that does not exist on this customer's build fails here, not at the customer |
| S14 | **No credentials, no customer PII beyond keys** | Printed result sets carry document identifiers and the amounts under repair — never passwords, tokens, or bulk personal data |

### 4. Test the data fix on the restored database, then roll back (mandatory)

The proof runs on the §1.7 database. The template's own transaction is the rollback mechanism — the fix is exercised in full and then undone.

1. **Dry run (`@ysnCommit = 0`) — the primary test.** Execute the complete script. Inside the transaction, before the template's tail rolls it back, capture:
   - the analysis result set — the affected-row count and the printed identifiers,
   - the S9 pre-image,
   - each DML's `@@ROWCOUNT` and the Standard 1 assertion result,
   - the Standard 2 / 3 / 4 verification result sets (each must return zero imbalance rows),
   - the **AFTER state of the reported documents** — re-run the §1.7 BEFORE reproduction *inside the open transaction* so the corrected values are observed on the very rows the ticket names. This is the acceptance evidence.
   Then let the template `ROLLBACK`. Confirm `PRINT 'ROLLBACK TRANSACTION'` appeared, and **verify the rollback actually took**: re-run the analysis query after the script ends — the same rows must still be reported as having the issue, and `tblAPDataFixLog` must contain no row for `@fileName`. A dry run that left data changed is a critical failure: report it immediately and explicitly (never silently).
2. **Scope proof.** Assert `rows affected == rows with issues` (Standard 1) AND that the affected key set equals the analysis key set exactly. A fix that corrects the reported document but touches N other rows is a FAIL, no matter how plausible those N look.
3. **Idempotency check (local restores only, optional).** The `tblAPDataFixLog` guard only engages when `@ysnCommit = 1`. To prove it, on a **local** restored copy only: run once with `@ysnCommit = 1`, then run a second time and confirm it aborts with `DataFix already applied …`. Then **drop or re-restore that local copy** so no fixed state survives. **Never on a shared `knownServers` database** — the §1.7 shared-server rule stands: a committed data fix on a shared restore corrupts other people's testing.
4. **Failure handling.** Any assertion that raises, any imbalance row, any count mismatch → the script is not deliverable. Revise and re-run from step 1. Do not deliver a data fix whose own assertions have not been observed passing on real data.
5. **The database is left unfixed.** After §3.6 the restored/connected DB is in its pre-fix state, exactly as §3.5 leaves a Liquibase DB rolled back. The actual correction happens when a human applies the script to the customer database.

### 5. Impact analysis and QC briefing (Foundational Guidelines #5–#8)

Assemble, from what the run actually established:
- **Linked program JIRA** — the code fix that stops the defect recurring (§1.6 Step 2.9.2). If none exists, say so explicitly and state that one is required.
- **Impact Analysis** — which tables/columns change, how many rows, which modules consume them (APC, Valuation, In-Transit, GL, AR…), and what was verified to be unaffected. Ground every claim in a query result from step 4.
- **Cross-module owners** — when the affected data is consumed by another module, name the owning team as a required reviewer/approver.
- **QC test pointers** — the areas to test, *not just the symptom column*. If the fix changed amounts and removed/added GL entries, the briefing must tell QC to check the payment GL entries and prepayment balance, not merely the field the customer reported.

### 6. Senior BA review is the gate — this runbook does not self-approve

Per the Data Fix Guidelines review workflow, a **Senior BA** reviews the script against Standards 1–4 and posts PASS / NEEDS REWORK / FAIL on the JIRA, and **QC does not begin testing until that sign-off exists**. This runbook delivers the artifact and the evidence into that workflow; it never records a verdict on its own behalf, and never states or implies that the data fix is approved.

### 7. Deliver — terminal for the run

1. Save the script to `<liquibaseLogDir>\<JIRA>\<JIRA>DataFix.sql`, with the dry-run console output alongside it as `datafix-dryrun-<UTC timestamp>.log`.
2. Post the **§6 RCA comment in its DATA_FIX form** (see §6) — including the full script in a fenced block, the affected-row count, the identifiers, the Standard 1–4 results, the impact analysis, and the QC test pointers.
3. **Attachment:** the script is posted in full in the comment (that is the deliverable of record). Additionally attach the `.sql` to the JIRA — the Atlassian **MCP** has no attachment tool, but the **Jira REST API does**: `POST /rest/api/3/attachment` with `X-Atlassian-Token: no-check` (multipart), using the same `atlassian` credentials §1 step 5 uses for downloads. If that upload fails for any reason, do not retry blindly — state in the run output: `<JIRA>DataFix.sql at <path> — attach to the JIRA manually`.
4. **No branch, no commit, no push, no PR.** §4 and §5 are skipped for a data fix: the artifact is delivered on the ticket, not through the code branch. If your team's process additionally requires the script committed to a repository, the operator supplies the repository and path explicitly — this runbook never guesses a location for it.
5. Then run **§6.6 (status handoff)** and **§6.7 (PR handoff — data-fix form)**.

## §3.7 Regression impact — dependents + golden-set differential (R-REGRESSION-IMPACT)

**Purpose:** answer the one question §3's targeted BEFORE/AFTER proof cannot — *did this change anything for rows nobody complained about?* The BEFORE/AFTER pair proves the reported document is now right; it is silent on every other row, company, and document type the same object serves. §3.7 is that check.

**SCOPE — no application environment is required, provisioned, or used by this section (operator 2026-08-07).** §3.7 operates at the **repository and database layer only**. UI, rendering, and HTTP-level behaviour are explicitly OUT of scope and remain the job of **§1.7a**, which is optional, runs only on an operator-supplied `APP_ENV`, and is unchanged by this section. §3.7 never triggers §1.7a, never depends on it, and never justifies provisioning an environment.

**TRIGGER:** §3's implementation passed AND `CHANGED_OBJECTS` is non-empty — i.e. the CHANGESET alters at least one SQL logic object (stored procedure / view / function / trigger) or a code artifact with resolvable callers. **Skipped for `IS_DATAFIX_CASE = true`**: a data fix changes rows, not object definitions, and §3.6's Standards 1–4 already carry its collateral-damage checks.

### Tier 1 — Static caller graph + contract gate (ALWAYS runs; no database needed)

1. `CHANGED_OBJECTS` = every object whose *definition* the CHANGESET alters (ignore pure formatting/comment edits).
2. `DEPENDENTS` = everything that consumes them:
   - **Repo-wide:** `git -C <repo> grep -il "<object>" <TARGET_BRANCH>` across every repo under `<REPO_ROOT>` that could consume it — SQL, C# (`web-api`, `server/BLL`), and ExtJS/JS. Not just the repo being changed: an AP view is routinely consumed by a report or another module.
   - **As deployed:** when a §1.7 database is available, `sys.sql_expression_dependencies` — this catches callers that exist in the customer database but in no repo copy (the AP-24446 class, where the deployed body itself only lives in the customer DB).
3. **Contract-change gate (fail-closed).** If the change alters any of:
   - a **parameter list** (added/removed/renamed/retyped/reordered parameter, or a changed default),
   - a **result-set shape** (added/removed/renamed/retyped output column, or a changed column order that positional consumers rely on),
   - a **column type** on a table/UDT that dependents read or write,
   …AND at least one dependent is **not** in the CHANGESET → **§3 FAIL** (no branch, no push), unless the RCA explicitly waives it with a named reason and the affected dependents listed. This is the §J bind-time defect class one level up: §J catches a column that does not resolve inside the changed object; the contract gate catches a changed object that breaks somebody else's resolution.
4. Record the dependent count and the objects examined.

### Tier 2 — Golden-set differential (runs when a §1.7 database is available)

1. **Build `GOLDEN_SET`:** the reported document(s) **plus N other keys (default 20) that exercise the same code path and are NOT the reported defect** — stratified across company, date range, and posted/unposted state. Sampling from rows that are *not* the complaint is the whole point: anything that moves in that group is, by construction, collateral. Record how the sample was drawn (the query), so the evidence is reproducible.
2. **Capture BEFORE** with the pre-fix definition, deterministic ordering:
   - **view / function** → `SELECT` over the sampled keys.
   - **stored procedure** → reuse the **§3.6 harness**: `BEGIN TRAN` → `EXEC` with the sampled inputs → capture the affected tables' row deltas → `ROLLBACK`, then **verify the rollback took**. A procedure differential must never leave the database mutated.
3. Apply the fix; **capture AFTER** with the identical procedure, sample, and ordering.
4. **Diff.** The expected outcome is that **only the reported defect class differs**.
   - Any row outside the defect class whose output changed → **review-blocking finding**: list it by key in the RCA with the before/after values.
   - No unexpected deltas → record the counts as corroboration (it is positive evidence, not proof).
5. **Determinism discipline — without this the check cries wolf and gets ignored, which is worse than not running it.** Impose a stable `ORDER BY` on a key; exclude volatile columns (`GETDATE()`/`SYSDATETIME()` outputs, identity/sequence values, `NEWID()`, `rowversion`, last-modified stamps); run both passes with the same session settings. **Every excluded column is disclosed in the RCA, never silently dropped** — an exclusion list is where a real regression can hide.
6. **Side-effect safety:** the §1.7 post-restore safety script MUST already have neutralized outbound integrations (SAP/API endpoints, SMTP, job triggers, EFT export) before any `EXEC` — that is what makes executing a procedure against a restored copy safe. **Never run tier 2 against a shared `knownServers` database** (same guard as §3.5): restore a local copy for the differential, or skip tier 2 and disclose it.

### Verdict, disclosure and limits

| `REGRESSION_VERDICT` | When | Action |
|---|---|---|
| `CONTRACT-FAIL` | Tier 1: a contract change with an unhandled dependent | **§3 FAIL** — STOP, no branch, no push. Report the object, the contract change, and every unhandled dependent |
| `UNEXPECTED-DELTAS` | Tier 2: rows outside the defect class changed | **Not a §3 FAIL** — the fix stands, but this is a **review-blocking finding**: named in the RCA with keys and values, label `AP-AI-RegressionFlag`, and carried on the §6.7 handoff line so the PR is not auto-completed blind |
| `CLEAN` | Tier 1 passed; tier 2 ran with no unexpected delta | Record the counts as corroboration and continue |
| `NOT-RUN` | No database available (the dominant case on a blocked queue), or tier 2 declined for the shared-server guard | Tier 1 still runs. Skip tier 2 **without stopping** and disclose it |

**Mandatory RCA line** (§6) — one of:
```
Regression impact: <d> dependents analyzed · <n> golden rows compared · <k> unexpected deltas[ · excluded volatile columns: <list>]
Regression impact: dependents analyzed (<d>); golden-set differential NOT run — no database is known/available for this JIRA.
```

**Honest limits, stated in the RCA whenever they apply:**
- **Sampling is evidence, not coverage** — 20 clean rows do not prove the 21st. §3.7 raises confidence; it does not make a guarantee, and must never be described as one.
- **Nothing here checks UI, rendering, or end-to-end behaviour.** That gap is real and remains open until an operator supplies an `APP_ENV` for §1.7a.
- A dependent found only by text search may be a false positive (a same-named object in another module); resolve ambiguity by schema/repo before calling a contract failure.

## §3.8 Defect lineage & fix-coverage map (R-DEFECT-LINEAGE)

**Purpose:** answer two questions the root cause alone does not — **which change introduced this defect**, and **which version lines already carry a fix for it (and whether that fix is complete)**. Both are cheap to establish once the cause is pinned to a concrete construct, and both change what happens next: the introducing ticket names the regression for the RCA, and the coverage map tells the PR/propagation owner which branches still need this fix and which do not. Without it a run silently re-fixes something already fixed elsewhere, or fixes one line and leaves three others broken.

**TRIGGER:** §3 pinned the root cause to a **specific, greppable construct** — an expression, predicate, column reference, or condition — in an object whose history is in the repo. Skip (and say so) when the cause is data-shaped rather than code-shaped (§3.6 data fixes), or when the defective construct cannot be reduced to a searchable string.

### 1. Find the introducing change (`DEFECT_ORIGIN`)

1. Reduce the defect to the shortest string unique to it — the *defective* form, not the surrounding object. (Ref AP-22786: `FLOOR(@factor1)` inside the `@p1` assignment, not `fnMultiply`.)
2. Pickaxe the file's history on `TARGET_BRANCH`, oldest match last:
   `git -C <repo> log --oneline -S "<construct>" origin/<TARGET_BRANCH> -- <path>`
   Use `--follow` when the file may have been renamed. The **earliest** commit that added the construct is the introducing change.
3. Extract the JIRA key from that commit's message/PR and read it — cache `DEFECT_ORIGIN` = `<key> | <summary> | <commit> | <date> | <author>`.
4. **Confirm the origin actually reaches this branch:** `git merge-base --is-ancestor <commit> origin/<TARGET_BRANCH>`. A construct that merely *looks* like the one on another branch is not the origin of this one.
5. No JIRA key in the commit message, or the history predates the current repo → record `DEFECT_ORIGIN: not determinable` and continue. This section never stops a run.

### 2. Map existing fixes across the active lines (`FIX_COVERAGE`)

1. Pickaxe for the **corrected** forms as well as the defective one, across every repo/branch that could carry the object. **Mind the repo split (R-LB-24.1-TARGET):** the same logical object lives in `i21_sqlscripts` for < 24.1 and in `i21_Liquibase` for ≥ 24.1 — a lineage that stops at one repo will report a false gap.
2. For each active version line, classify: `DEFECT` (original form) · `PARTIAL` (a fix exists but does not close every failure mode — see step 3) · `FIXED` · `N/A`.
3. **Verify by CONTENT, never by commit-grep** (the §1.6 revert-detection rule applies here too): read the actual construct on each candidate branch. A `git log --grep` hit proves a commit mentioning the key exists, not that the fix is present — a revert matches too.

### 3. Never call a line "fixed" from source text alone — build a counterexample (fail-closed)

A fix that *looks* like it addresses the cause may close only part of it. Prove it empirically:

1. Derive the **failure condition** from the root cause (the exact operand range, data shape, or state that triggers it).
2. **Construct an input that actually satisfies that condition** and run it against the supposedly-fixed line. Do not reuse the reported case — the reported case is often *not* the boundary, and a well-chosen-looking example that misses the condition will falsely clear a still-broken line.
3. Only a counterexample that **passes** on that line justifies `FIXED`; one that still reproduces makes it `PARTIAL`, and that is a finding for the RCA.

> Ref AP-22786: the forward line's `LEN(REPLACE(CAST(FLOOR(@factor1) AS NVARCHAR(38)),'-',''))` strips the sign character but leaves the `FLOOR`-away-from-zero half open. A first counterexample (`−999999.5`) came out symmetric and would have wrongly cleared 26.x/27.1 — its product has too few decimals to reach the precision overflow. The operand that *does* satisfy the condition (`−999999.70166666670 × 0.799`, integer part just under a power of ten, ≥ 6 significant decimals) still reproduces the defect on 27.1. Same class of trap as testing a fix on the wrong branch.

### 4. The build-vintage caveat (report it whenever behaviour differs by line)

When the changed object behaves differently across lines, **a reviewer testing on their own database will get a different answer than the run did** and may conclude there is no defect. Whenever `FIX_COVERAGE` is not uniform, the RCA MUST carry a short "check which database/branch you are on first" table mapping vintage → observed behaviour, so a good-faith verification attempt does not produce a false negative. (Ref AP-22786: the same two `SELECT`s return a symmetric result on a 26.x database and an asymmetric one on every Walter Matter 22.1 database.)

### 5. Object ownership — is the defective object even ours? (R-OBJECT-OWNERSHIP)

A JIRA's project says where the **symptom** was reported; it does not say who owns the **object that must change**. Shared framework/utility objects are routinely consumed by a module that does not maintain them, and a fix pushed on a `<module>_<JIRA>` branch silently asserts ownership the module may not have. Establish it from evidence, not from the project key:

1. **Location** — is the file under a module-owned path, or a shared one (e.g. `i21Database/dbo/Functions`, `logic/functions`)? A shared path is the first signal.
2. **Caller distribution** — count referencing objects by module prefix (`uspAP*`/`fnIC*`/…). The module owning the clear majority is the de-facto owner.
3. **Change history** — read the JIRA key on every prior commit to the file (§3.8 step 1 already has this history). **A file only ever changed under one project's keys belongs to that project**, whatever project is reporting now.
4. **Who writes the bad rows** — the object that actually produces the defective data, which may be a different module from the one that surfaces it.
5. Record `OBJECT_OWNER` and, when it is **not** the JIRA's own project, say so plainly in the RCA with the counts and the history behind it, and offer the routing options (raise the fix under the owning project's key and link back · keep the branch but let the owner review · route the whole ticket). **The runbook does not decide this and does not re-home anything itself** — it creates no ticket in another project (§3.8 step 6) and never silently drops the analysis. The fix stays validated and pushed; only its ownership is open.

> This is NOT a route back to `CANNOT-FIX`. Ownership is raised **after** the defect is reproduced and fixed, with evidence attached — never as an assertion that substitutes for the analysis (the failure mode §1.6 guards against; ref AP-22786, where an early "not an AP issue" verdict produced a won't-fix → reopen loop, and where the eventual fix landed in a function whose 214 callers are 143 IC / 9 AP and whose every prior change was an IC ticket).

### 6. Report — and stop at the repo boundary

- Put the lineage table and the coverage map in the §6 RCA (see the **Defect lineage** block there).
- A line classified `DEFECT` or `PARTIAL` that this run does not fix is a **coverage gap**: name it explicitly, and carry it on the §6.7 handoff so the PR/propagation owner sees it. It is information, not a task this runbook performs.
- **This runbook never files a ticket in another team's project**, never widens the CHANGESET to other lines, and never propagates (that boundary is unchanged). Fixing a gap on another line is an operator decision.

**Mandatory RCA line** (§6) — one of:
```
Defect lineage: introduced by <KEY> (<commit>, <date>) · coverage: <line>=<state>, … · gaps not fixed here: <list or none>
Defect lineage: not determinable (<why>).
```

## §3.9 Property & invariant test of the changed object (R-PROPERTY-TEST)

**Purpose:** §3 proves the reported case is fixed and §3.7 samples other rows — neither proves the change **cannot drift**. When the changed object is deterministic, its correctness is expressible as *invariants that must hold for every input*, and those can be tested exhaustively over the decision boundaries rather than sampled. This is the difference between "the reported document is right now" and "this fix does not quietly move anything else."

**TRIGGER:** the CHANGESET alters a **pure, deterministic** artifact — a scalar/table function, converter, rounding or precision helper, formatter, parser, or any computation whose output depends only on its inputs. **Skip** (and say so) for stateful procedures that read/write tables — §3.7 tier 2 is the right instrument there — and for changes with no computable contract.

### 1. Old and new, side by side, on a LOCAL scratch database

1. Script the **deployed** (pre-fix) body from the object as it exists today, and take the **new** body from the working tree.
2. Deploy BOTH into a **throwaway local database** under distinct names (`fn_old` / `fn_new`). Assert before running that the two bodies actually differ in the intended way — a test that silently compares a function against itself passes perfectly and proves nothing.
3. **Never run this against the reported, shared, or customer database, and never `ALTER` the real object for it.** §3.5's execute-then-restore exists to prove deployment; this section exists to explore behaviour, which means thousands of calls and no business reason to touch a shared server. Drop the scratch database when finished.

### 2. Build the grid from the MECHANISM, not from random numbers

Enumerate the change's own **decision boundaries** from the code and cross them:
- every threshold and bucket edge the logic branches on (digit counts, magnitude tiers, length limits, type precision/scale limits),
- the values that sit **just under and just over** each boundary — including carry points (`9`, `99`, `999`, `999999`) where an operation can push a value across a tier,
- all **sign combinations** of every operand,
- degenerate inputs the code special-cases (`0`, `1`, `-1`, NULL, empty),
- plus real values harvested from the §1.7 database, so the grid is anchored in data the customer actually has.

A grid drawn from the mechanism finds what a grid of arbitrary numbers will not: it targets exactly the branches the fix moved.

### 3. Assert invariants — and always these five

Beyond the defect's own invariant (e.g. `f(-x,y) = -f(x,y)`), assert the contract the object claims (identity element, zero, commutativity, round-trip, monotonicity, idempotence — whichever apply), and **always** these:

| # | Invariant | Verdict if violated |
|---|---|---|
| V1 | **New failures ⊆ old failures** — the set of inputs failing under NEW must be a subset of those failing under OLD | **§3 FAIL.** The fix introduces a new defect, however small |
| V2 | **No drift** — for every input where OLD was already correct, `NEW == OLD` exactly | **§3 FAIL** unless each difference is explained and intended |
| V3 | **Accuracy never worse** — `abs(NEW - exact) <= abs(OLD - exact)` for every input | **§3 FAIL** |
| V4 | **The oracle is independent** — `exact` is computed OUTSIDE the system under test (arbitrary-precision arithmetic in the harness), never by the engine or object being tested | Test is invalid; rebuild it |
| V5 | **Residual failures are characterised, not ignored** — any input still failing under NEW is classified (what class, what causes it, is it reachable on the affected code path) | Not a FAIL when pre-existing and disclosed; **a FAIL if left unexplained** |

### 4. Report

Record: inputs tested, evaluations performed, failures under OLD, failures under NEW, inputs fixed, inputs changed, of-which-unwanted-drift, accuracy regressions, and each residual class. **A residual pre-existing defect discovered here is a finding, not a licence to widen the CHANGESET** — name it in the RCA, and if it warrants its own ticket say so and leave it to the operator (§3.8 step 6 boundary, unchanged).

**Mandatory RCA line** (§6) — one of:
```
Property test: <n> inputs / <e> evaluations · failures OLD <a> → NEW <b> (new ⊆ old: yes) · <f> fixed · <c> changed, <d> unwanted drift · <r> accuracy regressions[ · residual: <class>]
Property test: NOT run — the changed artifact is not a deterministic computation (<what it is>).
```

## §4 Create the feature branch and commit

Only reached when §3 passed. **Skipped entirely when `IS_DATAFIX_CASE = true`** (§3.6 step 7 is terminal).

1. Put the validated changes on the feature branch:
   - IF the current branch is **already** `<FEATURE_BRANCH>` (the feature-branch-detection case from Input parameters — you are on `<base>_<JIRA>`): you are already on the correct branch; **do nothing here** (no checkout, no double-suffix). Proceed to step 2.
   - ELSE: `git checkout -B <FEATURE_BRANCH>`.

   Do **not** commit directly to `<TARGET_BRANCH>`.

2. Stage and commit the validated changes:
   - `git add -A` (or stage only the intended files if there are unrelated local edits — never commit validation artifacts or unrelated changes).
   - Commit message MUST include `<JIRA>` and briefly describe the change intent.

3. After committing, re-inspect the diff before pushing:
   - Confirm only the JIRA / acceptance-criteria intent is present.
   - Confirm no duplicate properties/columns/routes/methods were introduced.
   - Confirm no unrelated target-only fields, procedures, filters, or endpoints were removed.
   - For Liquibase schema files, confirm no deployed changeset was modified (unless it is a `runOnChange:true` logic object where the standards allow it).
   - For all Liquibase files, confirm every new changeset uses a timestamp ID and does not duplicate an existing `author:id` pair.

## §5 Push the feature branch (single connection)

`cd <REPO_PATH>`

`git push origin <FEATURE_BRANCH>`

- Use the Azure DevOps MCP / `az`-authenticated git; do not use a PAT from this prompt.
- After the push succeeds, continue to §6.

STOP if the push fails; report the error. Do not post the Jira comment for a change that was not pushed.

## §6 Comment on JIRA — Root Cause Analysis / Developer's Testing (MANDATORY on a successful fix)

**Voice (all Jira comments this runbook posts):** short, direct, and professional. Keep every required block and honesty rule; compress the prose *inside* each block. Prefer short sentences and tight bullets. No filler, hedging, narration, casual tone, emoji, or marketing language.

**The RCA comment means "FIXED".** It is posted ONLY when this run delivered a fix — a validated change pushed on `<FEATURE_BRANCH>` (§5), or a data fix authored, tested and rolled back per §3.6. A run that ends any other way posts the matching §1.6 / §6.5 comment instead (see **R-NOFIX-COMMENT** in §1.6) and never an RCA. Never post an RCA describing a fix that was not delivered.

Post ONE comment on the parent `<JIRA>` combining the **Root Cause Analysis** with a **Developer's Testing** block that maps each acceptance criterion to the evidence gathered in §3 (or §3.6).

PRE-REQ:
- §3 validation passed and §5 push succeeded — OR, for `ISSUE_CATEGORY = DATA_FIX`, §3.6 completed with all assertions observed passing and the database left rolled back.
- Jira integration tool available and cloudId resolved.
- The JIRA issue (§1), `ACCEPTANCE_CRITERIA` (§2), and the CHANGESET diff (§3) are available.

**FORMAT (mandatory — match this structure).** Build `JIRA_RCA_BODY` from the Jira (symptom / expected behavior / acceptance criteria) + the CHANGESET diff (root cause, evidence, fix), traceable to evidence only — no invented work. The RCA opens with a **Summary (non-technical)** block so non-technical readers (customer, support, consultants, PM) understand the ticket without reading the technical sections. Omit the **Proof of testing** block if no screenshots/output are available; never fabricate proof.

```
# Root Cause Analysis

**Summary (non-technical):**

<2–4 plain-language sentences for a non-technical reader: what the user experienced in day-to-day terms, why it happened (in business terms, not code), and what the fix changes for them. No file names, no code objects, no SQL/branch/repo jargon. This block restates the technical findings below — it must not introduce any claim that is not covered by them.>

**Issue:**

<What the user/QA observed — the reported symptom(s). Use a short numbered list when there are multiple distinct failures.>

**Root Cause:**

<The underlying cause. When the failure spans layers (DB / BL / UI / config), break it down per layer. Name the specific defect.>

**Investigation:**

<How the cause was confirmed — what was validated and in what order; what evidence pinned it down.>

**Technical evidence (for dev/QA):**

<Bulleted, grouped by area. Name the actual files/objects changed and what changed in each, drawn from the CHANGESET diff.>
* **<Area, e.g. Logic / SP fix>**
    * `<repo/path/to/file.sql>`
    * <what changed and why>

**Proposed Solution:**

<The fix delivered (1–2 lines) + a short prevention/regression checklist for this area.>

**Regression impact:** <MANDATORY whenever §3.7 ran (any CHANGESET with a SQL logic object or a code artifact with callers). One line: "`<d>` dependents analyzed · `<n>` golden rows compared · `<k>` unexpected deltas" plus the excluded volatile columns when tier 2 ran, OR the not-run disclosure "dependents analyzed (`<d>`); golden-set differential NOT run — no database is known/available for this JIRA." When `<k>` > 0, list the affected keys with before/after values — it is a review-blocking finding, not a footnote. Never present a clean differential as proof of no regression; it is sampled evidence. Omit this line entirely for a data fix (§3.6 carries its own Standards 1–4 collateral checks).>

**Property test:** <MANDATORY whenever §3.9 ran. One line with the counts: inputs / evaluations · failures OLD → NEW and whether the new failure set is a SUBSET of the old · fixed · changed and how many of those were unwanted drift · accuracy regressions · each residual class. State plainly that a residual is a pre-existing defect left unfixed (and whether it is reachable on the affected path), never bury it. OR the not-run disclosure naming what the artifact is. Omit for a data fix.>

**Defect lineage:** <MANDATORY whenever §3.8 ran. One line: "introduced by `<KEY>` (`<commit>`, `<date>`) · coverage: `<line>`=`<state>`, … · gaps not fixed here: `<list or none>`", OR the not-determinable disclosure. When `FIX_COVERAGE` is NOT uniform across lines, ALSO include the short vintage → observed-behaviour table required by §3.8 step 4, so a reviewer testing on a different database does not get a false negative. A line marked `PARTIAL` must say what the existing fix does NOT close, backed by the counterexample from §3.8 step 3 — never assert completeness from source text. Omit this block entirely for a data fix.>

**Schema validation:** <ONLY when CHANGESET contains a Liquibase change. DB known: "`liquibase update` + rollback verification running asynchronously (§3.5) — result will be commented on the PR." DB not known: "`liquibase update` NOT run — no database is known/available for this JIRA." Omit this line entirely for non-SQL changes.>

----------------------------------------------
**Developer's Testing-**

<One line per acceptance criterion: the criterion, the developer test performed, and the observed result (PASS/FAIL with the concrete evidence). Every item in ACCEPTANCE_CRITERIA must appear here.>
1. <acceptance criterion 1> — <test performed> — Result: PASS (<evidence>)
2. <acceptance criterion 2> — <test performed> — Result: PASS (<evidence>)

----------------------------------------------
**Proof of testing-**

<Optional — attach/reference test screenshots or output if available; otherwise omit this block entirely.>
```

**DATA_FIX form (ISSUE_CATEGORY = DATA_FIX).** Same comment, same Summary/Issue/Root Cause/Investigation opening — the "root cause" here is *why the rows are wrong*, and it names the linked program JIRA where the code defect lives. Replace **Technical evidence** / **Schema validation** with the blocks below, and keep Developer's Testing:

```
**Data fix delivered:** `<JIRA>DataFix.sql` — derived from the JIRA Datafix Template (page 434602044), ships with `@ysnCommit = 0`.
**Linked program JIRA:** <key, or "NONE — a program JIRA is required for the code-level root cause">
**Coded against build:** <DB_BUILD_VERSION>   **Target branch:** <TARGET_BRANCH>

**Records affected:** <n> — identifiers: <the printed list>

**Validation results (dry run on a restored copy of the reported database):**
* Standard 1 — rows with issue <n> = rows affected <n> — PASS
* Standard 2 — voucher header/detail integrity — PASS / N/A
* Standard 3 — payment Amount Paid vs applications — PASS / N/A
* Standard 4 — GL debit/credit balance for posted transactions — PASS / N/A
* Additional checks S5–S14 — PASS
* Transaction rolled back; re-run of the analysis query still reports the same <n> rows; no `tblAPDataFixLog` entry written.

**Impact analysis:** <tables/columns changed, row counts, consuming modules (APC / Valuation / In-Transit / GL / AR), and what was verified unaffected — each grounded in a query result>
**Cross-module approvers required:** <team(s), or None>
**Test pointers for QC:** <the areas to test beyond the reported symptom — e.g. payment GL entries and prepayment balance when amounts and GL entries changed>

**Review:** pending Senior BA sign-off per the Data Fix Guidelines (page 503382346). QC to begin only after that verdict is posted.

<the full script in a fenced ```sql block>
```

Rules specific to the DATA_FIX form: the script is posted **in full** (it is the deliverable); `@ysnCommit` in the posted script is `0`; the comment states that the database used for testing was left unfixed; and **no local/Philippines restore details are named** (R-DB-LEDGER-REUSE) — say "a restored copy of the reported database", not the server or database name.

Call `addCommentToJiraIssue`:
- issueKey: `<JIRA>`
- cloudId: resolved
- commentBody: `JIRA_RCA_BODY`
- contentFormat: markdown

Rules:
- **ONE** `addCommentToJiraIssue` call.
- **Mention the people who need to see it (R-COMMENT-MENTIONS, operator 2026-08-08).** Every comment this runbook posts @-mentions the issue's **current assignee**. In addition, the comment that **first establishes a §3.8 lineage** mentions the **assignee and commit author of each related JIRA** it names — they know the object and the comment discusses their earlier work, and naming a ticket without notifying its developer buries the finding. On **subsequent** comments in the same run, mention only the people the *new* information actually concerns: re-mentioning the same group on consecutive comments is noise, and an automation that spams gets muted, which costs more than the notification gains. Use `contentFormat: adf` with real `mention` nodes (`{"type":"mention","attrs":{"id":"<accountId>","text":"@Name"}}`) — markdown renders `@Name` as inert text and notifies nobody. Resolve account ids with `lookupJiraAccountId`; when one cannot be resolved, name the person in plain text and say the mention could not be resolved. Never mention someone merely to escalate, and never mention a customer-facing account.
- Every **Root Cause** / **Technical evidence** / **Developer's Testing** claim must be traceable to the CHANGESET diff, the acceptance criteria, or the Jira description; do not invent symptoms, layers, fixes, or test results.
- The **Summary (non-technical)** block is mandatory and jargon-free: it translates the Issue/Root Cause/Proposed Solution into plain language a non-developer can act on, and may not add facts beyond the technical sections it summarizes.
- Every `ACCEPTANCE_CRITERIA` item MUST appear in the **Developer's Testing** block. An empty or partial Developer's Testing block -> STOP and re-derive from §2/§3.
- Do NOT use the Jira REST API directly.
- FAIL (STOP) if the tool is unavailable.

## §6.5 Additional comment protocols (operator 2026-08-06)

**A. CANNOT-FIX comment (FEASIBILITY = CANNOT-FIX, §1.6).** When the run concludes the issue cannot be fixed by this runbook (module ownership elsewhere, won't-fix/by-design candidate, cross-team dependency), post ONE comment — never skip silently:

```
# Automated analysis (JIRA-AI) — cannot deliver a fix on this ticket

**What was analyzed:** <code paths read, evidence used — the full detail, so nobody repeats the work.>
**Why not fixable here:** <owning module + the exact artifact / the dependency / the by-design behavior, with evidence.>
**Suggestion / recommendation:** <the concrete next step: which team/module should own it, the specific object to change, or the dependency to resolve first.>
```

**B. Reporter Rules note.** Append to ANY JIRA-AI comment (info request, cannot-fix, fix-delivery info, RCA) each rule that applies — reference examples from the 2026-08-06 queue in parentheses:

```
**Note for the reporter/commenters (for smooth automated analysis):**
1. A new issue different from the one reported here belongs on a SEPARATE JIRA. (e.g. AP-24801 — a second defect arrived in comments)
2. Include step-by-step reproduction with the specific document numbers. (e.g. AP-24683 — no steps/voucher named in text)
3. Include the acceptance criteria / expected behavior.
4. Attach the screenshot, the EXACT error message text, and the browser console (F12) for UI errors. (e.g. AP-24683)
5. Provide the database info: backup link, or the server + database name where it is restored. (e.g. AP-24402, AP-22155)
6. Keep the JIRA title consistent with the description details.
```
Include ONLY the numbered rules that actually apply to the ticket; renumber the shortlist.

**C. RESOLVED-BUT-UNDOCUMENTED note.** When the issue is (or becomes) resolved but the ticket's description lacks the information an automated analysis needed (build/family, repro documents, DB location, exact error), post a SHORT note listing exactly which of the six items above were missing — so the next ticket from the same reporter arrives analyzable. One comment, no label.

**D. TRIAGE comment (R-NOFIX-COMMENT fallback).** When a run analyzed the issue but ended WITHOUT delivering a fix and without falling into an information-request / cannot-fix / fix-delivery case — a §3 validation FAIL, a failed DB restore, a `DB-VERSION-MISMATCH`, an unresolvable branch, an implementation the run could not complete safely — post ONE comment so the ticket carries what the run learned. Label `AP-AI-Triaged`. Never leave a ticket with nothing after an analysis.

```
# Automated triage (JIRA-AI) — analyzed, not fixed

**Verdict:** <the classification and why the run stopped, in one line>
**Target branch:** `<TARGET_BRANCH>` (derived from <evidence>)  ·  **Module/repo:** <PRODUCT / repo>
**Requirements found:** <n — list each distinct reported defect when there is more than one>

**What was analyzed:** <the code paths read, the objects checked, what was ruled out — enough detail that the next person does not repeat it.>
**Findings so far:** <the suspected mechanism, named concretely, or "root cause not yet established".>
**Why no fix was delivered:** <the specific blocker: which validation failed, which check could not be run, what the mismatch was.>
**What would unblock it:** <the concrete next step.>
```

Rules: dedupe against an unanswered prior JIRA-AI triage comment for the same blocker (report "triage unchanged since `<date>`" and post nothing); never name a local restore's server/database (R-DB-LEDGER-REUSE); never state a root cause that was neither statically proven nor reproduced on a database; append the §6.5 B Reporter Rules note where a rule applies.

## §6.6 Status handoff (R-STATUS-HANDOFF)

Runs after the §6 / §6.5 comment. Purpose: make the ticket's state reflect what the run did, so the next batch pass does not re-pick its own in-flight work and humans can see at a glance which tickets are waiting on them.

**Config gate:** enabled by default; the operator can disable it for a run (`statusHandoff = off`), in which case the intended transition is reported in the run output but not applied.

1. **Resolve the transition by name, never by id:** `getTransitionsForJiraIssue` on `<JIRA>`, then match the target status name case-insensitively against the available transitions. **No matching transition available → do not force anything:** report `status handoff skipped — no transition to <target> from <current>` and continue. A workflow that does not permit the move is the workflow's decision, not an error.
2. **Target status by outcome:**

| Run outcome | Transition | Label |
|---|---|---|
| Fix delivered — branch pushed (§5) | → `Coding` (the fix exists but no PR has been raised; the PR runbook or a human owns the next move) | `AP-AI-Fixed` |
| Data fix delivered (§3.6) | → `Coding` — and the comment states that Senior BA review is pending | `AP-AI-DataFix` |
| Information requested (§1.6) | **no transition** — the issue stays `Open`/`Reopened` because the reporter still owns it | `AP-AI-NeedInfo` (existing) |
| Database requested | **no transition** | `AP-AI-NeedInfo` (existing) |
| `CANNOT-FIX` | **no transition** — routing/ownership is an operator decision, not an automated status change | `AP-AI-CannotFix` |
| Triage only (§6.5 D) | **no transition** | `AP-AI-Triaged` |
| `ALREADY-RESOLVED` / out-of-status / out-of-type | **no transition, no label** | — |

3. **Assignment:** when the issue is **unassigned**, assign it to the run operator. **Never reassign an issue that already has an assignee** — that person owns it, and silently taking it is exactly the collision the status gate exists to prevent.
4. **Labels are additive, always** — re-send the issue's existing labels alongside the new one; never overwrite the label set (same rule as `AP-AI-NeedInfo`).
5. **Never** transition an issue to `Testing`, `Ready to Test`, `Closed`, or `Done`. This runbook does not certify delivery: a fix that is merely pushed is not testable, and closing is a human judgement.
6. Record the applied (or skipped) transition, assignment, and labels in the run output.

## §6.7 PR handoff (R-PR-HANDOFF)

This runbook creates no PR. It ends by stating, in a machine-readable form, that a branch is ready — so `JIRA-PR-Automation.md`, the propagation runbook, or a scheduled job can pick the work up without re-deriving any of it.

**On a delivered code fix**, emit this line BOTH as the last line of the run output AND as the closing line of the §6 RCA comment:

```
READY-FOR-PR: <PRODUCT> | <ADO_REPO> | <FEATURE_BRANCH> → <TARGET_BRANCH> | <JIRA> | <n> file(s)
```

- The values come from what was actually pushed in §5 — never from intent. If the push did not succeed, no handoff line is emitted (and no RCA comment exists to carry it).
- When §3.5 launched the async schema-change confirmation, append `| schema-confirmation: pending (result will be commented on the PR)` so the reviewer knows a ✅/❌ is still inbound.
- When §3.7 returned `UNEXPECTED-DELTAS`, append `| regression-flag: <k> unexpected delta(s) — DO NOT auto-complete` so the PR flow cannot merge it unreviewed. When §3.7 tier 2 was skipped, append `| regression: tier-2 not run (no DB)`.
- When §3.8 found `COVERAGE_GAPS`, append `| coverage-gap: <line>=<state>, …` so the PR/propagation owner sees which other lines still carry the defect. This is a marker only — this runbook never propagates and never files a ticket in another team's project.
- When the run touched more than one repository, emit one line per repository.

**On a delivered data fix** there is no branch and no PR. Emit instead:

```
READY-FOR-REVIEW (data fix): <JIRA> | <JIRA>DataFix.sql | records affected: <n> | Senior BA sign-off required
```

Nothing in this section creates, approves, or completes a pull request — that boundary is unchanged.

- JIRA_KEY is a required input parameter, validated against `[A-Z][A-Z0-9]+-\d+$`. It is used for the feature-branch name, the commit message, and the Jira comment only.
- **REPO_ROOT is the main folder where all i21 repositories reside (default `C:\i21Source`); REPO_PATH = `<REPO_ROOT>\<repo folder>` must be resolved and the repository loaded/cloned before any code analysis.** If the target repository (REPO) is not provided, AUTO-RESOLVE it from the Jira/module evidence + cross-repo code search under `<REPO_ROOT>`; ask the user only when that resolution stays ambiguous (never assume the opened workspace). If the repo is not present locally, clone it from Azure DevOps; if it is present, fetch (and checkout/pull TARGET_BRANCH when provided) so the code analysis in §1/§3 runs against real, current code. STOP if the repo cannot be cloned/loaded; a tree dirty with unrelated edits is **auto-stashed** (`git stash push -u -m "JIRA-AI auto-stash …"`, stash ref recorded in the run output, never popped/dropped automatically) and the run continues — only a failed stash is a STOP.
- **An auto-detected TARGET_BRANCH is provisional and is auto-aligned by §1.5 — Dev-first (operator 2026-08-06).** `EXPECTED_BRANCH` = the customer's dedicated Dev branch for the fix version when one exists (CUSTOMER_BRANCH_ALIASES, e.g. `22.1DevWaMa`, `24.2DevDnD`, `26.3DevCTRMFeatures_Sucden`), else mainline `<fixVersion>Dev`; the ONLY Prod branch we work is `24.2ProdSunshineGas`. Fallbacks: the Reported Build family as a branch, then build-stamp→branch resolution (token scoring against the `ls-remote "<version>*"` scan, cross-checked via ADO pipeline definition names — app build stamps are NOT ADO build numbers). JIRA_BUILD is harvested from all fields + description/comments/environment/screenshots, never the build field alone. Case-exact matching with the case-twin guard (`22.1ProdWaMa` ≠ `22.1ProdWama`); artifact-presence corroborates between surviving candidates. Only an underivable base is a STOP. Never adopt a leftover checked-out branch as the base without §1.5 clearance, and never create the target branch.
- **§1.6 feasibility gate runs before any implementation.** ALREADY-RESOLVED now requires the LATEST QA evidence to pass AND the fix content to still be present on the branch (revert detection by CONTENT diff, never commit-grep — ref AP-22099); a `Reopened` issue is never ALREADY-RESOLVED. Reopened-with-merged-PR runs the **Step 0.5 fix-delivery check** (was the fix in the tester's build? if not → ONE informational comment, NO PR, no re-implementation — ref AP-24412). ALL distinct requirements on the ticket (description + comments) are enumerated and analyzed; cross-team routing comments are judged on evidence (ref AP-24801). Third-party analyzer comments are last-resort input — JIRA-AI analyzes independently (ref AP-24683). Data/environment-dependent symptoms split into `DB_REQUIRED-ACTIONABLE` (DB reachable from ticket/sibling/registry → §1.7 immediately, no request) vs `DB_REQUIRED-BLOCKED` (ONE info request per customer cohort); insufficient evidence is `INFO_REQUIRED` → ONE deduped **INFORMATION REQUEST** comment (+ `AP-AI-NeedInfo` label, additively) and STOP; unfixable-here is `CANNOT-FIX` → ONE details+recommendation comment (§6.5), never a silent skip. Never post duplicate info requests; never claim a root cause that was neither statically proven nor reproduced on a restored DB.
- **§1.7 DB restore:** all SQL Server parameters come from the `sqlServer` section of `%USERPROFILE%\.jira-ai-config.json` (never in a repo; secrets stay in that file or env vars only). Check the `knownServers` registry FIRST when the JIRA says the DB was already restored on a server — matched by name/alias only, never a guessed connection; when the SQL port is unreachable, fall back to the entry's `ssh` block (key-based; tunnel preferred, remote `sqlcmd` fallback; transport recorded in the run output) before declaring the server unreachable; shared-server DBs are used for reproduction only (no safety-script assumption, no §3.5 update/rollback there). Otherwise restore locally per JIRA (`i21_<JIRA>_<CUSTOMER>`), post-restore safety script MUST neutralize outbound integrations before any test, `liquibase update` aligns it to the branch, and the BEFORE/AFTER reproduction pair is the required proof for DB-dependent root causes.
- **Optional configurations are accuracy boosters, never guessed around:** at run start check the ONE consolidated `%USERPROFILE%\.jira-ai-config.json` — sections `atlassian` (attachment downloads; falls back to `~/.atlassian-token`/env), `sqlServer` (+ its `knownServers` registry), and `helpdesk` (HDTN session cookie — per user, refreshed via browser login when expired); report missing/empty sections in the run output and disclose every capability skipped because of a gap (RCA line or Information Request) — see **Optional configurations** at the top of this runbook.
- **No PR, no propagation.** This runbook stops after pushing `<TARGET_BRANCH>_<JIRA>` and posting the RCA / Developer's Testing comment. It does not create or complete a Pull Request and does not fan out across branches.
- Parent Jira issue type must be one of `Bug`, `Bug-QC`, `Bug-UAP`, `Bug-Ongoing UAP`, `Technical Debt`, `Performance`, or `Data Fix`; STOP if the issue type is missing, inaccessible, or outside this list. (`Performance` → TECHNICAL_DEBT; `Data Fix` → DATA_FIX; everything else → BUG.) **`Feature`, `Gap`, `Paid`, `Suggestion` and `Config` are explicitly OUT OF SCOPE (operator 2026-08-11)** — there is no `FEATURE` category in this runbook; each is a silent STOP reported as `OUT-OF-TYPE (<issue type>)`, with no comment and no label.
- **`Data Fix` issues ALWAYS require the database (R-DATAFIX-DB)** — §1.6 can never classify one as `STATIC`; it is `DB_REQUIRED-ACTIONABLE` (→ §1.7 → §3.6) or `DB_REQUIRED-BLOCKED` (→ ONE information request → STOP). The delivery path is **§3.6**, not §3/§4/§5: author from the **JIRA Datafix Template** (page 434602044) keeping its log/idempotency/TRY-CATCH machinery intact, apply **Standards 1–4** of the **Data Fix Guidelines** (page 503382346) plus the additional fail-checks **S5–S14** (no unbounded DML, single scope resolution, no schema DDL, no mass-destructive constructs, pre-image capture, posted-record guard, build stamp populated, ships with `@ysnCommit = 0`, §J binding, no credentials), **test the fix on the restored DB inside the template's transaction and let it ROLL BACK** — then verify the rollback actually took (analysis query still reports the same rows, no `tblAPDataFixLog` entry) — and deliver the script + impact analysis + QC test pointers on the JIRA. The DB is always left unfixed. Senior BA sign-off is the gate; this runbook never self-approves a data fix, and creates no branch, commit, or PR for one.
- **An HD (HDTN) ticket is OPTIONAL and never required.** It is read for additional information only — above all the **`Database Copy` tab / restore comment / restore screenshot** naming the server + database IT restored the copy onto, which feeds §1.7 step 0. No HDTN referenced → skip silently. Cookie missing/expired → record the gap and CONTINUE on the JIRA's own evidence (operator 2026-08-07; supersedes the former STOP); never ask a reporter for an HD ticket.
- **R-NOFIX-COMMENT — every run leaves the right comment, and only one.** The §6 RCA is reserved for a **successful fix** (branch pushed, or data fix delivered). Needs-information and needs-database → INFORMATION REQUEST + `AP-AI-NeedInfo`; unfixable-here → CANNOT-FIX (§6.5 A); fix-not-in-tested-build → the Step 0.5 informational comment; analyzed-but-not-fixed for any other reason (§3 FAIL, restore failure, `DB-VERSION-MISMATCH`, unresolvable branch) → the **§6.5 D TRIAGE comment** + `AP-AI-Triaged`. Only `ALREADY-RESOLVED` and the out-of-type/out-of-status gates post nothing. Dedupe applies to all of them.
- **R-QUEUE-LABEL-STATE — batch/scheduled passes select by label, never by status (operator 2026-08-11).** Because no ledger is written, the §6.6 outcome labels are the durable state: the selector JQL excludes `AP-AI-NeedInfo` / `AP-AI-CannotFix` / `AP-AI-Triaged` / `AP-AI-Fixed` / `AP-AI-DataFix`, and MUST include `labels IS EMPTY OR …` (Jira's `NOT IN` drops unlabeled issues — the never-processed ones). Never filter on `AP-AI-RegressionFlag` / `AP-AI-FixPropagated` (ref AP-24523). Re-entry is evidence-driven (label cleared, or a comment newer than the runbook's own), and the §1.6 dedupe guard — not the filter — decides whether to comment again. An explicit `JIRA_KEY` always overrides the filter. Unattended runs must terminate every operator-decision STOP through the §6.5 D triage comment + `AP-AI-Triaged`, or the next pass re-derives the same stall forever. Batch statistics are then JQL label counts, not a tracking file.
- **R-DB-SLOT-LIMIT — at most TWO locally restored databases at once (operator 2026-08-11).** Local restores are a pool of 2 slots, keyed **per cohort** (one restore serves the whole customer/environment cohort); a `knownServers` database occupies no slot. A third DB_REQUIRED cohort is parked `DB_QUEUED` — `FEASIBILITY` stays `DB_REQUIRED-ACTIONABLE`, and **no comment and no label** is posted (a queued ticket is not a blocked one). Release order: completion check (every ticket in the cohort has its terminal comment — disk pressure never cuts an analysis short) → harvest all BEFORE/AFTER, §3.7 and §3.9 evidence into the run output → §3.5/§3.6 rollback already verified (**dropping the DB is not a substitute for the rollback proof**) → `SET SINGLE_USER WITH ROLLBACK IMMEDIATE` + `DROP DATABASE` → **KEEP the backup archive (R-DB-KEEP-ARCHIVE — the database is dropped, the archive is not)** → record `slot released` and the retained archive path. Never drop or delete anything this runbook did not restore. `STATIC` / `INFO_REQUIRED` / `CANNOT-FIX` tickets never wait on a slot.
- **R-DB-KEEP-ARCHIVE — drop databases, keep archives (operator 2026-08-11).** A slot is the **restored database alone**; the archive in `backupStageDir` occupies no slot and is never counted against the pool. After a restore is verified `ONLINE` (§1.7 step 3a), a raw `.bak` is **compressed to `.zip`, the archive verified, and only then the `.bak` deleted** — never the reverse order, because an unverified archive plus a deleted `.bak` is a lost database; an artifact that arrived already archived keeps its original archive and loses only the extracted `.bak`. A failed/non-`ONLINE` restore compacts nothing. The archive then survives the rollback, the slot release, and the run itself, so §1.7 step 1.3 (already-staged) makes a re-restore a local extract instead of a multi-gigabyte re-download — while still facing the step-0 acceptance gate and the step-2.6 version check, since a retained archive is a candidate and never an authority. The ONLY file this runbook may delete in `backupStageDir` is a loose `.bak` whose archive it just verified; genuine disk exhaustion is reported for operator cleanup, never resolved by deleting evidence.
- **R-DB-LEDGER-REUSE — reuse before restoring, and keep no records.** Exhaust §1.7 step 0 (ticket, siblings, HD `Database Copy` tab, live `sys.databases` sweep of the configured `knownServers`) before any download or restore. **No ledger, index, or DB log is ever written by this runbook** — reuse is rediscovered from live evidence each run. **Never publish local (Philippines/workstation) restore details** — server, database name, or path — in any Jira comment, RCA, PR, or Confluence page; those belong in the run output only. Only DBs on shared servers the team already references may be named.
- **DB version check (§1.7 step 2.6):** every database this runbook uses is checked with `SELECT TOP 1 strVersionNo FROM tblSMBuildNumber ORDER BY intVersionID DESC` and must match `TARGET_VERSION` on **main.major only** (`24.2` vs `24.2` — build/revision are expected to differ and are never compared). Mismatch → STOP with `DB-VERSION-MISMATCH` and the §6.5 D triage comment. Not determinable → continue read-only, but a hard STOP for `DATA_FIX`.
- **§3.7 regression impact (R-REGRESSION-IMPACT) — repo/DB layer only, NO app environment.** Runs after §3 whenever the CHANGESET alters a SQL logic object or a code artifact with callers (skipped for a data fix — §3.6 has its own collateral checks). **Tier 1 always runs, no DB needed:** build the caller graph (repo-wide `git grep` across every repo under `<REPO_ROOT>`, plus `sys.sql_expression_dependencies` when a DB is present) and apply the **fail-closed contract gate** — a changed parameter list, result-set shape, or column type with any dependent outside the CHANGESET is a **§3 FAIL** unless explicitly waived with the dependents named (this is the §J bind-error class one level up). **Tier 2 runs when a §1.7 DB is available:** build a `GOLDEN_SET` of the reported document(s) plus ~20 sampled keys that are NOT the defect (stratified by company/date/posted state), capture BEFORE/AFTER with deterministic ordering — views/functions by SELECT, procedures via the **§3.6 transaction harness** (`BEGIN TRAN` → EXEC → capture deltas → `ROLLBACK`, rollback verified, DB never left mutated) — and diff: only the reported defect class may differ. Unexpected deltas are a **review-blocking finding** (RCA + `AP-AI-RegressionFlag` + a `regression-flag:` marker on the §6.7 handoff so the PR is not auto-completed), **not** a §3 FAIL. Volatile columns (dates, identities, `NEWID()`, rowversion) are excluded for determinism and **every exclusion is disclosed**. Never run tier 2 against a shared `knownServers` DB (restore a local copy or disclose). No DB → tier 2 skipped without stopping, disclosed in the RCA. **Sampling is evidence, never proof — a clean differential must never be reported as "no regression".** UI/render/end-to-end behaviour is explicitly out of scope and stays with §1.7a.
- **§3.9 property & invariant test (R-PROPERTY-TEST) — proves the fix cannot drift.** Runs whenever the CHANGESET alters a **pure, deterministic** artifact (scalar/table function, converter, rounding/precision helper, formatter, parser); skipped with a disclosure for stateful procedures (§3.7 tier 2 covers those) and for changes with no computable contract. Deploy the **deployed pre-fix body and the working-tree body side by side under distinct names on a THROWAWAY LOCAL database** — never against the reported/shared/customer DB, and never by `ALTER`ing the real object — asserting first that the two bodies actually differ (a test comparing a function with itself passes and proves nothing); drop the scratch DB after. Build the grid from the **code's own decision boundaries** (thresholds, bucket edges, type precision/scale limits, values just under/over each carry point, every sign combination, the special-cased degenerates `0`/`1`/`-1`/NULL) crossed with real values from the §1.7 DB — a mechanism-derived grid finds what arbitrary numbers will not. Assert the defect's own invariant plus the object's claimed contract, and **always** V1 **new failures ⊆ old failures**, V2 **no drift** (`NEW == OLD` wherever OLD was already correct), V3 **accuracy never worse**, V4 **the oracle is computed OUTSIDE the system under test** (arbitrary precision in the harness — never by the engine being tested), V5 **every residual failure is characterised** (class, cause, reachability). V1–V4 violations are a **§3 FAIL**; a *pre-existing* residual is a finding to disclose, **never a licence to widen the CHANGESET** — name it in the RCA and leave any follow-up ticket to the operator. Report the counts on the mandatory RCA **Property test** line. (Ref AP-22786: 1,030 inputs / 10,300 evaluations reduced sign-asymmetry 129 → 32 with new ⊆ old, 0 unwanted drift and 0 accuracy regressions — and surfaced an unrelated pre-existing asymmetry in the `= 1` early-return shortcut that the fix deliberately does not touch.)
- **§3.8 defect lineage & fix-coverage map (R-DEFECT-LINEAGE) — who introduced it, and who already fixed it.** Runs after §3.7 whenever the root cause reduces to a **greppable construct** (skipped for data fixes and for causes that cannot be reduced to a searchable string; never a STOP). Pickaxe the *defective* construct (`git log -S "<construct>" origin/<TARGET_BRANCH> -- <path>`, `--follow` for renames) to name `DEFECT_ORIGIN` — the introducing commit + its JIRA — and confirm it with `git merge-base --is-ancestor`, never by assumption. Then build `FIX_COVERAGE` across the active lines, **searching BOTH repos** (`i21_sqlscripts` < 24.1, `i21_Liquibase` ≥ 24.1 — R-LB-24.1-TARGET; a one-repo sweep reports a false gap) and classifying by **CONTENT**, never by `git log --grep` (a revert matches the grep too). **A line is `FIXED` only when a counterexample that genuinely satisfies the failure condition passes on it** — an existing-looking fix is `PARTIAL` until proven, and a poorly-chosen example that misses the condition will falsely clear a still-broken line (ref AP-22786: `−999999.5` wrongly cleared 26.x/27.1; `−999999.70166666670 × 0.799` still reproduces there). When coverage is not uniform, the RCA MUST carry the vintage → observed-behaviour table so a reviewer testing on a different database does not conclude "no defect". `COVERAGE_GAPS` are **reported only** — named in the RCA and marked on the §6.7 handoff (`| coverage-gap: …`); this runbook never widens the CHANGESET to another line, never propagates, and never files a ticket in another team's project. **§3.8 step 5 also settles `OBJECT_OWNER` (R-OBJECT-OWNERSHIP):** the JIRA's project says where the symptom was reported, not who owns the object that must change — decide it from the file's location, the caller distribution by module prefix, and the project keys on every prior commit to that file (a file only ever changed under one project's keys belongs to that project). When the owner is not the JIRA's own project, state it in the RCA with those counts and offer the routing options; the runbook never re-homes the branch, never raises the ticket elsewhere, and never lets ownership become a substitute for the analysis — it is raised only AFTER the defect is reproduced and fixed (ref AP-22786: `fnMultiply` has 214 callers — 143 IC, 9 AP — and every prior change to it was an IC ticket).
- **R-COMMENT-MENTIONS (operator 2026-08-08):** every comment this runbook posts @-mentions the issue's **current assignee** and, when §3.8 named related JIRAs, **their assignees and commit authors**. Use `contentFormat: adf` with real `mention` nodes — a markdown `@Name` is inert text that notifies nobody. Resolve ids with `lookupJiraAccountId`; state plainly when one cannot be resolved.
- **APP_ENV / §1.7a runtime reproduction (R-RUNTIME-REPRO):** OPTIONAL input, **never provisioned by this runbook** — no i21 app environment is built, deployed, or configured here. When provided, it is used only to reproduce UI/render/HTTP symptoms via Playwright (console + network + screenshot capture, optionally correlated with an Extended Events capture). Its version must match `TARGET_VERSION` and `DB_BUILD_VERSION` on **main.major**; on mismatch the runtime evidence is **discarded** and the mismatch reported. Read-only on any environment that is not a controlled restore. Never a STOP; when absent and the symptom is UI-level, disclose `runtime reproduction NOT run — no APP_ENV provided`.
- **§6.6 status handoff (R-STATUS-HANDOFF):** after the comment, resolve the transition **by name** via `getTransitionsForJiraIssue` and move a delivered fix (code or data) to `Coding` with `AP-AI-Fixed` / `AP-AI-DataFix`; every not-fixed outcome keeps its current status and takes only its label (`AP-AI-NeedInfo` / `AP-AI-CannotFix` / `AP-AI-Triaged`). Labels are always additive. Assign the operator only when the issue is **unassigned** — never reassign someone else's ticket. **Never** transition to `Testing`, `Ready to Test`, `Closed`, or `Done`. No available transition → skip and report, never force.
- **§6.7 PR handoff (R-PR-HANDOFF):** end a successful code-fix run by emitting `READY-FOR-PR: <PRODUCT> | <ADO_REPO> | <FEATURE_BRANCH> → <TARGET_BRANCH> | <JIRA> | <n> file(s)` as the last line of BOTH the run output and the §6 RCA comment (one line per repository; append `| schema-confirmation: pending` when §3.5 is still running). Values come from what was actually pushed — no push, no handoff line. A data fix emits `READY-FOR-REVIEW (data fix): …` instead. This creates no PR.
- **Issue status must be `Open` or `Reopened`** — any other status (`Coding`, `In Progress`, `Testing`, `Ready to Test`, `Investigating`, `Closed`, …) is a STOP with no comment, reported as `OUT-OF-STATUS (<status>)`: the issue is already being worked or verified, and an automated run would collide with or duplicate that work.
- Acceptance criteria drive both the implementation and the Developer's Testing block. If they are missing/insufficient and cannot be reliably derived -> STOP.
- **When the change touches SQL scripts (`IS_LIQUIBASE_STANDARD_CASE = true`): apply the Liquibase standard compliance rules (§A–§J of `JIRA-PR-Automation.md`).** Every new changeset uses a timestamp ID in the correct folder/file, with preconditions where it may already exist, a rollback, and `endDelimiter:GO` where required. Never commit a version-style changeset or a raw SSDT/`SqlScript` file. **EXCEPTION (R-LB-24.1-TARGET): Liquibase exists only for i21 versions ≥ 24.1.** On a < 24.1 target branch (22.x/23.x) the SQL fix is a direct **i21_sqlscripts SSDT edit** (raw `.sql` commit IS correct there), `i21_Liquibase` is not a valid repo for that branch, §A–§I changeset mechanics are skipped, and §J binding stays fully enforced.
- **§3.5 schema-change confirmation:** `liquibase update` is ONLY a confirmation function. DB known for the JIRA → run it on a **separate agent** (update → `rollback-count <N>` verification, DB left rolled back — never re-applied; full logs under `<liquibaseLogDir>\<JIRA>\`; ✅/❌ result posted as ONE PR comment on the `<FEATURE_BRANCH>` PR, or on the Jira when no PR exists yet) while the main run continues to the next step/JIRA. DB not known → skip WITHOUT stopping and disclose `liquibase update NOT run` in the §6 RCA. **Pre-24.1 branch → case C instead:** save the pre-fix object definitions, execute the changed script on the JIRA's DB to confirm it deploys cleanly, capture the AFTER evidence, then **restore the pre-fix definitions — the DB is always left unfixed** (allowed even on a shared `knownServers` DB because the restore removes the mutation; a failed restore is a review-blocking finding reported immediately). §J static object binding stays fail-closed in every case. Never edit the repo's `liquibase.properties`; the DB URL is passed per run.
- Validation runs **before** any branch/commit/push. Create and push the feature branch only if validation passes with no issue and every acceptance criterion is satisfied.
- For TECHNICAL_DEBT issues: before pushing, verify linter checks pass with no new errors and all dependencies resolve (including exact column/identifier binding); STOP if either fails.
- One push for the repository. STOP if: JIRA_KEY is missing/invalid; REPO_PATH cannot be resolved (auto-resolution ambiguous and the user did not answer), cloned, or loaded; `<REPO_PATH>` is the `<REPO_ROOT>` container folder rather than a repository, or is not a git repo; an explicitly provided TARGET_BRANCH does not exist on origin; §1.5 cannot derive an `EXPECTED_BRANCH` that exists on origin; the Azure DevOps MCP preflight fails; any required validation check fails or cannot be run and is not explicitly waived; the push fails; or the Jira tool is unavailable.
- Jira activity on the parent issue: **exactly ONE comment per run**, selected by outcome per R-NOFIX-COMMENT — the **RCA / Developer's Testing** comment (§6) after a successful fix (branch pushed, or data fix delivered per §3.6); else a deduped **INFORMATION REQUEST** (+ `AP-AI-NeedInfo`), a **CANNOT-FIX** (§6.5 A), a **fix-delivery informational** note (Step 0.5), or a **TRIAGE** comment (§6.5 D, + `AP-AI-Triaged`). Plus the §6.6 label/transition/assignment writes. An ALREADY-RESOLVED verdict and the out-of-type/out-of-status gates post nothing at all.
