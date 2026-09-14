# JIRA current-changes PR runbook (no propagation)

Execute this runbook **immediately and completely** in **Agent mode** for allowed bug, feature, and technical debt issue types. It works on the **current repository's own pending changes** (working-tree/staged edits and/or commits on the current branch that are not yet on the target branch), validates them with the existing validation rules, and — only if validation passes with no issue — creates **one** Azure DevOps PR and completes the required Jira follow-up. Do not summarize or ask for confirmation unless a mandatory STOP condition applies.

**This runbook does NOT propagate.** There is no JIRA-key commit discovery across branches, no `BRANCHES` routing, no cherry-pick onto multiple `<BRANCH>_<JIRA>` branches, and no merge-PR fan-out. It validates the changes already present in the working repository and opens a single PR from a work branch into the current (target) branch.

**Order:** Accept **JIRA_KEY** (and optional **TARGET_BRANCH** override) → confirm the current repo and resolve **TARGET_BRANCH** / **WORK_BRANCH** (default = current branch, with work-branch detection so an existing `<base>_<JIRA>` branch is reused and never double-suffixed) → collect and analyze **CHANGESET** (the repo's pending changes) → run the existing validation → **if and only if** validation passes with no issue, move the changes onto the `<TARGET_BRANCH>_<JIRA>` work branch, commit, push, **post the Root Cause Analysis (RCA) comment on the Jira**, create one PR, auto-approve/auto-complete, then post the Jira PR link and the technical changelog.

---

# Input parameters

JIRA_KEY = <provided issue key parameter>

Validation:
- JIRA_KEY MUST match regex: `[A-Z][A-Z0-9]+-\d+$`
- If JIRA_KEY is missing or invalid -> STOP execution (do not infer it from the current branch).
- JIRA_KEY is used only for PR title/description, the Jira comments, and the work-branch name. It is **not** used to search for or discover commits — the changes come from the working repository, not from a JIRA-key commit search.

TARGET_BRANCH = <optional target branch override parameter> (default: the current branch)

Validation:
- TARGET_BRANCH is OPTIONAL. If it is not provided, resolve it from the current branch (see "Work-branch detection" below — the current branch may already be a `<base>_<JIRA>` work branch).
- TARGET_BRANCH MUST be a single branch name. It MUST NOT be a comma-separated list and MUST NOT contain `{` or `}`.
- TARGET_BRANCH MUST exist on origin (`git ls-remote --heads origin <TARGET_BRANCH>`). If it does not exist on origin -> STOP execution (do not guess or create the target branch).
- The PR's source branch will be `<WORK_BRANCH>` (= `<TARGET_BRANCH>_<JIRA>`); the PR's target branch will be `<TARGET_BRANCH>`. A PR must never target its own source branch, so TARGET_BRANCH MUST NOT equal WORK_BRANCH.

**Work-branch detection (mandatory when TARGET_BRANCH is not provided):**
The current branch may itself already be a `<base>_<JIRA>` work branch (a previous run, or a manually created feature branch). Auto-detection MUST handle this so it never targets a work branch:
1. `CURRENT_BRANCH = git -C <REPO_ROOT> branch --show-current`.
2. IF `CURRENT_BRANCH` matches the pattern `^(?<base>.+)_(?<key>[A-Z][A-Z0-9]+-\d+)$` (i.e. it ends in `_<JIRA-KEY>`):
   - `TARGET_BRANCH = <base>` (the prefix with the `_<JIRA>` suffix stripped), and
   - `WORK_BRANCH = CURRENT_BRANCH` (reuse the existing work branch as-is — do NOT create `<base>_<JIRA>_<JIRA>`).
   - If the trailing key does not equal JIRA_KEY, prefer the provided JIRA_KEY for the new `WORK_BRANCH`/PR metadata but STOP and report the mismatch if `<base>_<JIRA_KEY>` would differ from `CURRENT_BRANCH` (the operator must confirm which branch to PR from).
3. ELSE (current branch is a plain branch, e.g. `26.2Dev`):
   - `TARGET_BRANCH = CURRENT_BRANCH`, and `WORK_BRANCH = <TARGET_BRANCH>_<JIRA>` (created in §4).
4. After resolution, assert `TARGET_BRANCH != WORK_BRANCH` and that `TARGET_BRANCH` exists on origin; otherwise STOP.

# Issue type gate (mandatory)

Before doing any work, read parent `<JIRA_KEY>` from Jira and cache:

PARENT_ISSUE_TYPE = <parent Jira issue type>

Allowed bug issue types:
- `Bug`
- `Bug-QC`
- `Bug-UAP`
- `Bug-Ongoing UAP`
- `Config`   (billable bugs — ISSUE_CATEGORY = BUG)

Allowed feature issue types (new features):
- `Feature`
- `Gap`
- `Paid`
- `Suggestion`

Allowed technical debt / performance issue types:
- `Technical Debt`
- `Performance`   (performance optimization — ISSUE_CATEGORY = TECHNICAL_DEBT)

IF PARENT_ISSUE_TYPE is not exactly one of the allowed bug, feature, or technical debt / performance issue types:
    STOP execution — this runbook applies only to allowed bug, feature, technical debt, and performance issue types. (Do NOT post any comment for an out-of-scope issue type.)

IF PARENT_ISSUE_TYPE is one of the allowed feature issue types:
    ISSUE_CATEGORY = FEATURE
ELSE IF PARENT_ISSUE_TYPE is one of the allowed technical debt / performance issue types (`Technical Debt`, `Performance`):
    ISSUE_CATEGORY = TECHNICAL_DEBT
ELSE:
    ISSUE_CATEGORY = BUG

# Repository scope (single repo — the current workspace)

REPO_ROOT = the current working directory / opened workspace repository.

- Confirm it is a git repository: `git -C <REPO_ROOT> rev-parse --is-inside-work-tree` returns `true`. If not -> STOP execution.
- Resolve `ADO_REPO` from the origin remote: `git -C <REPO_ROOT> remote get-url origin` -> the name after `/_git/`. Cache `ADO_REPO`.
- Resolve `PRODUCT` for display from the remote substring:

| PRODUCT | ADO_REPO | Typical remote substring |
|---------|----------|---------------------------|
| Accounts Payable | i21_accountspayable | AP or i21_accountspayable |
| Liquibase | i21_Liquibase | Liquibase |
| SQLScript | i21_sqlscripts | SQLScript, SqlScripts, or i21_sqlscripts |

There is **no** multi-repo discovery and **no** `ACTIVE_REPOS` set. Only the current repository is processed.

# Derived variables (must be resolved before execution)

JIRA = JIRA_KEY
PARENT_ISSUE_TYPE = <resolved from parent JIRA>
ISSUE_CATEGORY = BUG | FEATURE | TECHNICAL_DEBT   # from issue type gate (`Performance` maps to TECHNICAL_DEBT)
REPO_ROOT = <current workspace repo>
ADO_REPO = <resolved from origin remote `/_git/<name>`>
PRODUCT = <Accounts Payable | Liquibase | SQLScript, for display>
TARGET_BRANCH = <override parameter, else current branch>
WORK_BRANCH = `<TARGET_BRANCH>_<JIRA>`   # PR source branch carrying CHANGESET
CHANGESET = <the repo's pending changes — see §2>
IS_LIQUIBASE_STANDARD_CASE = true WHEN any file in CHANGESET is a SQL-script file (i21_Liquibase `.sql`/`.xml`, or i21_sqlscripts/SqlScripts `.sql`)   # see "Liquibase standard compliance"

# Mandatory policy sources

- Code fix changes management guidelines:
  https://irely.atlassian.net/wiki/spaces/AP/pages/578519663/Code+fix+changes+management+guidelines
- Pull Request Standard Format:
  https://irely.atlassian.net/wiki/spaces/FRM/pages/62009675/Pull+Request+Standard+Format
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

Before validating any `i21_Liquibase` changes, read and apply `TEAM_LIQUIBASE_STANDARDS.md`. These rules are mandatory for the validation pass.

Before completing validation on changes that touch Liquibase SQL files, read and apply `beautify 3.md` together with `TEAM_LIQUIBASE_STANDARDS.md`.

**When `IS_LIQUIBASE_STANDARD_CASE = true` (the change touches SQL scripts), the "Liquibase standard compliance" section below is MANDATORY.** The goal is that the SQL-script changes in the working repository are **valid, standard-compliant Liquibase changesets** before a PR is opened.

Before creating the PR, read the Pull Request Standard Format page and use it as the PR body structure. If the page cannot be accessed, STOP before PR creation; do not invent a replacement format.

# ==================================================================
# Liquibase standard compliance — MANDATORY when the change touches SQL scripts
# Source iNet pages:
#   - Liquibase: Development Standard  (62014463)
#   - Liquibase: Changelog             (62012979)
#   - Liquibase: Schema                (62011589)
#   - Liquibase: Logic                 (62012975)
#   - Liquibase: Schema vs. Logic      (62013267)
#   - Liquibase: Execution Order       (62015445)
#   - Liquibase: Dependencies          (62014339)
#   - SQL Performance Pitfalls         (75700433)
# ==================================================================

## When this section applies

Set `IS_LIQUIBASE_STANDARD_CASE = true` and apply ALL rules below whenever any file in CHANGESET is a SQL-script file, i.e.:
- `i21_Liquibase` `.sql` changelog files or `.xml` dependency files, OR
- `i21_sqlscripts` / `SqlScripts` `.sql` files.

The deliverable is a **standard-compliant Liquibase changeset** in the working repository — not a raw SSDT/`SqlScript` file and not a version-style changeset.

## A. Changeset ID standard (Jan 2026+) — hard requirement

- **All new changesets MUST use 14-digit Timestamp-Based IDs: `YYYYMMDDHHmmss`** (e.g. `20260101090000`). This applies to **every** new changeset type — schema (table/FK/index/UDT/statistics) AND `runOnChange` logic objects (functions, stored procedures, views, triggers).
- **Do NOT use Version-Based IDs** such as `24.1.1`, `25.1.3`, `26.1.1` for any new changeset.
- Author portion is the developer email: `author@irely.com:YYYYMMDDHHmmss`.
- Existing already-deployed changesets (e.g. `24.x` version-style IDs) are **NOT** renamed — leave them exactly as deployed. Only *new* changesets created for this change use the timestamp format.
- **Validation:** scan changed `.sql` for any NEW changeset header whose ID matches `:[0-9]+\.[0-9]+(\.[0-9]+)?` (version-style). Any new version-style changeset is a hard fail — re-ID it to a fresh timestamp ID and set `--comment:` to the JIRA before commit.

## B. Immutability & checksums (Development Standard Rule #1 & #2)

- **Never change DB schema manually** — express the change through Liquibase only.
- **Once a changeset has been deployed to ANY environment, it is IMMUTABLE.** Liquibase stores its checksum in `DATABASECHANGELOG`; changing even one character (whitespace, comment, or logic) causes a **Checksum Validation Error** and halts deployment.
- **Correct action to fix a deployed changeset: add a NEW timestamp changeset** — do not edit the old one.
- Treat deployed/shared one-time DDL changesets as immutable: do not edit their SQL, comments, rollback text, whitespace, author, or ID.
- **Exceptions where editing in place is allowed:**
  1. **`runOnChange:true` logic files** (stored procedures, views, functions, triggers) — these are meant to be edited; see section D.
  2. **Local-development-only** changesets that have run *only* on your local machine and have **not** been pushed to Git (you must `rollback` locally before editing).

## C. Schema changes (tables, foreign-keys, indexes, statistics, udt)

Source iNet: *Liquibase: Schema* and *Liquibase: Changelog*.

- **Folder/file layout — organize by type, one object per file:**
  - `schema/tables/` — create/alter/drop table, add/alter/drop columns, constraints **except** foreign keys.
  - `schema/foreign-key/` — foreign-key changes only.
  - `schema/indexes/` — index changes only.
  - `schema/statistics/` — statistics only (optional).
  - `schema/udt/` — user-defined types only.
  - File is named after the object (e.g. `schema/tables/tblSMCompany.sql`). Changes to `tblSMCompany` go **only** into `tblSMCompany.sql`. **Don't mix and match** objects in one file.
- **Schema files MAY contain multiple incremental changesets** (append a new timestamp changeset for each new change; never edit a deployed one).
- **Changeset anatomy** (top to bottom):
  ```sql
  --liquibase formatted sql

  --changeset author@irely.com:YYYYMMDDHHmmss
  --comment: <JIRA> - <short description>
  --preconditions onFail:MARK_RAN
  --precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '<table>' AND COLUMN_NAME = '<column>'
  ALTER TABLE [dbo].[<table>] ADD [<column>] <type> NULL
  --rollback EXEC uspSMLiquibaseDropColumn '<table>', '<column>'
  ```
- **Nullable column-add team pattern:** formatted SQL header, timestamp changeset, `--comment: <JIRA>`, `--preconditions onFail:MARK_RAN`, an `INFORMATION_SCHEMA.COLUMNS` existence check, `ALTER TABLE ... ADD`, and rollback via `uspSMLiquibaseDropColumn` (or `uspSMDropColumn`). The existence check is **mandatory on every column add** — a column already present on a target (via SSDT base schema, an earlier changeset, or an out-of-band hotfix) otherwise fails deployment with `Msg 2705 — Column names in each table must be unique`. See R-COL-EXISTS in the VALIDATION GATE for the pre-push repo check that detects the duplicate before the PR is opened.

## D. Logic changes (functions, stored procedures, views, triggers)

Source iNet: *Liquibase: Logic* and *Liquibase: Schema vs. Logic*.

- **Folder/file layout:** `logic/functions/`, `logic/views/`, `logic/stored-procedures/`, `logic/triggers/` — one object per file, named after the object (e.g. `logic/stored-procedures/uspSMSampleProcedure.sql`).
- **Logic files hold exactly ONE changeset per changelog** with `runOnChange:true`. Unlike schema, you do **not** append a second changeset — you **edit the same script** and **generate a NEW changeset ID** for every change. The `--comment:` may keep citing the originating/functional JIRA; updating it to the current work JIRA is optional, not required (the `runOnChange:true` re-applies regardless of the comment text).
- **Required structure for stored procedures / functions:**
  1. Header: `--changeset author@irely.com:YYYYMMDDHHmmss runOnChange:true endDelimiter:GO`
  2. `--comment: <JIRA>`
  3. Call `EXEC uspSMLiquibaseSaveLogic '<ObjectName>', '<TYPE>'` (TYPE = `VIEW` | `PROCEDURE` | `FUNCTION` | `TRIGGER`) followed by `GO` — this saves the previous content for rollback.
  4. Multi-line `/* ... */` header comment (Name / Description / Parameters).
  5. `CREATE OR ALTER PROCEDURE|FUNCTION|VIEW|TRIGGER ...`.
  6. For SPs/functions: `BEGIN ... END` then `GO`.
  7. Rollback: `--rollback EXEC uspSMLiquibaseRollbackLogic '<ObjectName>'`.
- **`endDelimiter:GO` is required for functions and stored procedures** (and any object using `;`, e.g. a CTE that must start with `;WITH`). By default Liquibase splits statements on `;`, which breaks these objects. Put `GO` at the end of the object definition, just before the `--rollback` line. Views may use `runOnChange:true` without `endDelimiter:GO` unless their body needs it.
- **Complete logic example:**
  ```sql
  --liquibase formatted sql

  --changeset author@irely.com:20260106085810 runOnChange:true endDelimiter:GO
  --comment: <JIRA>
  EXEC uspSMLiquibaseSaveLogic 'uspSMSampleProcedure', 'PROCEDURE'
  GO
  /*
  ==============================================================================
  -- Name: uspSMSampleProcedure
  -- Description:
  -- Parameters:
  ==============================================================================
  */
  CREATE OR ALTER PROCEDURE [dbo].[uspSMSampleProcedure]
      @paramA INT,
      @paramB NVARCHAR(MAX)
  AS
  BEGIN
      --codes omitted for simplicity
  END
  GO -- This is important
  --rollback EXEC uspSMLiquibaseRollbackLogic 'uspSMSampleProcedure'
  ```
- **Conflicting rollback comment (Development Standard Rule #5):** do **not** leave a bare `-- ROLLBACK` / `-- rollback` comment inside logic bodies (e.g. inside a `BEGIN CATCH ... GOTO ExitWithRollback`) when it is not meant as a Liquibase rollback. Liquibase will misread it as a rollback directive.
- **runOnChange edit rule:** a logic object with `runOnChange:true` is meant to be edited — update only the intended object content, then mint a new timestamp ID. If an existing logic changeset does **NOT** have `runOnChange:true`, do not edit its body for this fix — add a new timestamp changeset containing the `CREATE OR ALTER` object instead.

## E. Pre-conditions (Development Standard Rule #4)

- **Use `--preconditions` when the change may already exist** on the target environment. Guard schema additions with an `INFORMATION_SCHEMA` existence check and `onFail:MARK_RAN` so the changeset is safely skipped where the object already exists.
- **Don't over-use pre-conditions** — excessive precondition SQL can cause performance issues over time. Add them where existence is genuinely uncertain, not blindly. **Column additions are the standing exception:** the §C team pattern requires the `INFORMATION_SCHEMA.COLUMNS` guard on EVERY `ALTER TABLE ... ADD`, regardless of version or direction (R-COL-EXISTS) — "don't over-use" governs the other changeset types.

## F. Dependencies & execution order (Liquibase: Dependencies / Execution Order)

Liquibase has **no automatic dependency management** — within a folder scripts run in **alphabetical order**, and within a changelog file **top to bottom**. You must define dependencies explicitly.

- **Execution order across folders** (earlier runs first):
  `utilities (do not use)` → `data/pre-deployment` → `dependencies/schema` → `schema/tables` → `schema/foreign-keys` → `schema/indexes` → `schema/statistics` → `schema/udt` → `dependencies/logic` → `logic/functions` → `logic/views` → `logic/stored-procedures` → `logic/triggers` → `data/post-deployment`.
- **Schema dependency pattern** (e.g. altering a column blocked by an index): add a drop file under `dependencies/schema/tables/<table>.sql` to DROP the index *before* the breaking change, then re-create the index under `schema/indexes/<table>.sql`. Flow: DROP index → alter column → ADD index.
- **Logic dependency pattern** (e.g. `vyuAPVendorChild` needs `vyuAPVendorParent`): add `dependencies/logic/views/<child>.xml` with a `<changeSet>` whose `<sqlFile path="logic\views\<parent>.sql"/>` forces the parent to run first:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <databaseChangeLog xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
                     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                     xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
                     http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-3.10.xsd">
      <changeSet id="YYYYMMDDHHmmss" author="author@irely.com" runOnChange="true">
          <comment><JIRA></comment>
          <sqlFile path="logic\views\vyuAPVendorParent.sql"/>
      </changeSet>
  </databaseChangeLog>
  ```

## G. Validate before pushing (Development Standard Rule #3)

- Run `liquibase update` (and `liquibase validate`) against a **development database** to confirm the changesets actually apply before pushing. If DB credentials are unavailable, record that validation was not run and why — do not silently treat it as passed.
- **When a changed logic object writes into a UDT or table** (INSERT / INSERT … EXEC / MERGE / table-variable populate of a typed target): the dev-DB apply above must be **attempted**, and is **required whenever a database IS reachable** — a possible apply must never be skipped. A column/identifier mismatch against the UDT/table definition only surfaces at SQL bind time (error 207), so it is the authoritative check. **R-DBAPPLY-BESTEFFORT — an unreachable dev DB is NOT a stop:** if no dev DB is reachable (no active `liquibase.command.url` in `liquibase.properties`, no `--url` / `LIQUIBASE_COMMAND_URL` override, or the connection fails), do **not** stop and do **not** block the push/PR — fall back to the §J static column-binding check as the enforced fail-closed gate, record "dev-DB apply not run" + the reason in the PR description and Jira comment, and continue. Never word it as "validated on dev DB" when the apply did not run. See §J for the static check, which runs either way.
- Re-run the standard checks: no version-style IDs on new changesets, no edits to deployed changesets, correct folder/file placement, `endDelimiter:GO` present where required, rollback present, and `--comment: <JIRA>`.

## H. SQL performance best practices to preserve/apply (SQL Performance Pitfalls)

When editing SQL (especially views/SPs), do not regress performance. Watch for and prefer the fixes below:

1. **`ROW_NUMBER()` inside a subquery/view** scans the whole table before filtering. Move `ROW_NUMBER()` to the outermost query, drop the column, or use a **composite key** for the EF dummy-PK requirement.
2. **Joining to table-valued functions (TVFs)** in large queries is slow — inline the logic or rewrite the function as a single statement so the planner can optimize.
3. **Non-SARGable filters/joins** defeat indexes. Keep predicates SARGable; **avoid casting/converting the filtered column** (e.g. `CAST(datetime AS date)`).
4. **`COUNT()` over large views with complex joins** is slow — convert the complex join into an inline `SELECT` so it isn't evaluated during `COUNT()`.
5. **`UNION` with mismatched column data types** forces implicit conversion → non-SARGable. Align data types across all `SELECT`s, especially on filtered columns.
6. **Cannot index `NVARCHAR(MAX)`/LOB columns** — set a specific length where possible, otherwise avoid filtering on them.
7. **Add an index to foreign-key columns** to avoid table scans on cascading referential-integrity checks.
8. **`DISTINCT` in views** is costly — prefer the right filter, or `GROUP BY` when de-duplication is unavoidable.
9. **Avoid `DISABLE/ENABLE TRIGGER` and other DDL (`ALTER TABLE/INDEX`, `TRUNCATE`, `sp_recompile`, non-nullable column adds) inside commonly used SPs/APIs** — they take the most restrictive `Sch-M` lock and cause blocking/deadlocks. (Local temp tables are exempt.)

## I. Net result for this case

For `IS_LIQUIBASE_STANDARD_CASE = true`, the change in the working repository MUST be:
- a Liquibase changeset (not a raw SSDT/`SqlScript` file),
- with a fresh **timestamp ID** for every new changeset,
- in the **correct folder/file** for its type,
- **preconditioned** where it may already exist,
- with a valid **rollback**,
- **column/identifier-bound** — every UDT/table reference resolved against its defining object per §J,
- validated with `liquibase update` (attempted, and required whenever a DB is reachable, when the change writes into a UDT/table; §J static binding is the enforced gate when no DB is reachable — see §G/§J),
- and only then committed, pushed, and PR'd.

## J. Object-binding validation — column/identifier resolution against UDTs & tables (mandatory)

The text/regex and Liquibase-metadata checks (conflict markers, changeset IDs, folder placement, rollback presence) validate the *form* of a changeset, **not** the *SQL semantics*. They cannot detect a column or identifier name that is internally self-consistent but does not match the object it binds to. The classic miss: an SP `INSERT`s into a UDT-typed table variable using a column name that was renamed in the `CREATE TYPE`, e.g. the proc uses `intShipmentLoadCostId` while `ItemCostAdjustmentTableType` defines `intLoadShipmentCostId` (words transposed). Because the producing function aliased the column with the same wrong name and the proc referenced that alias, every text scan saw a matched producer/consumer pair — the mismatch existed only against the **third** artifact (the UDT), which no regex compared against. SQL Server would reject it at compile/bind time (error 207), but only an actual DB apply runs that binding.

Apply this check for **every changed function / stored procedure / view / trigger** (and any changed UDT/table they bind to), regardless of `ISSUE_CATEGORY`:

1. **Enumerate write/bind targets** in the changed object:
   - `INSERT INTO <target> ( <column-list> )` where `<target>` is a UDT-typed table variable, a temp table, or a base table.
   - `INSERT INTO <target> ( <column-list> ) EXEC <proc>` (the column list still binds to the target's definition).
   - SELECT-list aliases that are later consumed by name by a caller (e.g. a TVF/function whose output column is read as `B.<alias>` by the SP that `CROSS APPLY`s it).
   - `DECLARE @v AS <SomeTableType>` populated later.
2. **Resolve each referenced column name to its defining object** and confirm it exists **exactly** (case-insensitive match of the real SQL identifier, but the spelling/word-order must be identical):
   - For UDT targets: open the `schema/udt/<Type>.sql` `CREATE TYPE` and match every INSERT column against the type's columns.
   - For base-table / temp-table targets: match against the `CREATE TABLE` (or the in-proc `CREATE TABLE #tmp`).
   - For function/proc output consumed by alias: match the consumer's `<alias>` references against the producer's actual output column names.
3. **Cross-artifact rename awareness:** if the diff (or a recently merged changeset in `schema/udt/` or `schema/tables/`) **renamed** a column, grep the whole repo for the **old** name across `logic/**` and `schema/**`; every consumer must be updated together. A UDT/table rename with a stale consumer is a hard fail.
4. **Fail-closed:** any referenced identifier that does not resolve to its defining object → **STOP** (report the unresolved name and the object it should have matched). Do not commit, push, or PR.
5. **Authoritative confirmation:** the only check that fully proves binding is a real apply — run `liquibase update` against a dev DB (see §G and the VALIDATION GATE). When the changed object writes into a UDT/table, that DB apply must be **attempted** and is **required whenever a DB is reachable**. If no dev DB is reachable, **do not STOP** (R-DBAPPLY-BESTEFFORT): the static resolution in steps 1–4 becomes the enforced fail-closed gate and execution continues — report the evidence honestly as "static binding resolution only; dev-DB apply not run (no reachable DB)" rather than marking validation passed.

ADO_ORG: irely
ADO_PROJECT: i21

# Azure DevOps MCP preflight (mandatory)

Before any Azure DevOps repository, commit, branch, pull-request, or work-item operation, verify that the `user-azure-devops` MCP server is functional.

Run one read-only MCP check against the current project/repo context, for example:

- `repo_get_repo_by_name_or_id` for `ADO_REPO` in `ADO_PROJECT`, or
- `repo_get_pull_request_by_id` when a known reference PR ID is available, or
- `repo_search_commits` once `ADO_REPO` is known.

MCP is functional only when the tool call returns a successful Azure DevOps response for the intended project/repo. If the MCP call fails because the server is unavailable, Azure authentication is missing, Azure CLI / Az.Accounts cannot be found, credentials are expired, authorization is denied, or the result cannot be trusted -> STOP execution.

Do not continue to commit, push, create PRs, update PRs, link work items, or post Azure DevOps-derived Jira follow-ups while Azure DevOps MCP is not functional. Do not bypass this gate with raw REST calls, PATs, cached PR URLs, browser inspection, or guessed branch/PR state.

# Azure DevOps REST auth (NO GIT_TOKEN / NO PAT in prompt)
# Prerequisite: az login (no subscription required for token acquisition)

Run once before any ADO REST call:
az login

Obtain access token:
az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv

Cache token for this run only (single auth session).

This REST token is allowed only after the Azure DevOps MCP preflight above has passed. A working `az` token does not replace the MCP preflight.

ADO REST header:
Authorization: Bearer <access_token>
Content-Type: application/json

If az login or get-access-token fails -> STOP execution


# ==================================================================
# STEPS
# ==================================================================

## §1 Confirm repo, branch, and target

`cd <REPO_ROOT>`

1. Confirm git repo and resolve `ADO_REPO` / `PRODUCT` (see "Repository scope").
2. Resolve TARGET_BRANCH and WORK_BRANCH using the **Work-branch detection** rules in "Input parameters":
   - If the TARGET_BRANCH parameter was provided, use it; `WORK_BRANCH = <TARGET_BRANCH>_<JIRA>`.
   - Else read `CURRENT_BRANCH = git branch --show-current`. If `CURRENT_BRANCH` ends in `_<JIRA-KEY>`, set `TARGET_BRANCH = <base>` (suffix stripped) and `WORK_BRANCH = CURRENT_BRANCH` (reuse it; do not double-suffix). Otherwise `TARGET_BRANCH = CURRENT_BRANCH` and `WORK_BRANCH = <TARGET_BRANCH>_<JIRA>`.
   - Assert `TARGET_BRANCH != WORK_BRANCH`; if equal -> STOP.
3. Confirm TARGET_BRANCH exists on origin: `git ls-remote --heads origin <TARGET_BRANCH>`. If not -> STOP.
4. Fetch the target branch (one fetch): `git fetch origin <TARGET_BRANCH>`.
   - Ensure the remote-tracking ref exists: `git rev-parse --verify --quiet refs/remotes/origin/<TARGET_BRANCH> || git fetch origin <TARGET_BRANCH>`.
5. WORK_BRANCH must not contain `{` or `}`.


## §2 Collect & analyze the current changes (CHANGESET)

The changes to validate and ship come from the **working repository**, not from a JIRA-key commit search. Collect from both sources and union them:

A. **Uncommitted changes** (working tree + staged):
   - `git status --porcelain`
   - `git diff` (unstaged) and `git diff --cached` (staged)

B. **Committed changes ahead of the target** (commits on the current branch not yet on origin/TARGET_BRANCH):
   - `git log --reverse --oneline origin/<TARGET_BRANCH>..HEAD`
   - `git diff origin/<TARGET_BRANCH>...HEAD --stat` and per-file diff

CHANGESET = the set of changed files and their effective diffs from A ∪ B.

**Analyze** CHANGESET:
- Enumerate every changed file and classify it (Liquibase schema, Liquibase logic, dependency `.xml`, SQLScript, application code).
- Set `IS_LIQUIBASE_STANDARD_CASE = true` if any changed file is a SQL-script file (i21_Liquibase `.sql`/`.xml`, or i21_sqlscripts/SqlScripts `.sql`).
- Summarize the intent of the change (used later for the PR Change Log and the Jira technical changelog — traceable to the diff only, no invented work).

**NO-CHANGES OUTCOME:** if CHANGESET is empty (no uncommitted changes and no commits ahead of origin/TARGET_BRANCH, or the effective diff is empty/metadata-only) -> **STOP**. Report that there is nothing to PR for `<JIRA>` in this repository. Do not create a branch or PR, and do not post a Jira comment. (This runbook only acts on real pending changes.)


## §3 Validate the current changes (the existing validation) — BEFORE any PR

Run the validation against CHANGESET. **Only if every applicable check passes with no issue** does the runbook continue to §4. If any check fails, STOP and report the specific failure; do not create a branch, commit, push, or PR.

VALIDATION GATE (MANDATORY):

- Run repository-appropriate static validation for changed files.
- For application code (if any `.cs`, `.js`, `.ts`, `.tsx` changed):
  - Run IDE lints or project linter for the changed files when available.
  - If a fast targeted build/test command exists for the changed project, run it.
- For Liquibase/SQL (when `IS_LIQUIBASE_STANDARD_CASE = true`):
  - Apply the full **Liquibase standard compliance** section (§A–§J) to the changed `.sql`/`.xml` files.
  - Search changed SQL files for unresolved conflict markers: `<<<<<<<`, `=======`, `>>>>>>>`.
  - **COLUMN-ADD DUPLICATE GATE (fail-closed, MANDATORY) — R-COL-EXISTS.** For every column addition in the changeset (`ALTER TABLE [dbo].[<table>] ADD [<column>] ...`, plus any `CREATE TABLE` that re-declares an existing table), resolve `<table>` + `<column>` against `origin/<TARGET_BRANCH>` in **both** SQL repos before commit/push:
    1. `git -C <REPO_ROOT> grep -niE "\[?<column>\]?" origin/<TARGET_BRANCH> -- "schema/tables/<table>.sql"` (i21_Liquibase — the table file MAY hold many incremental changesets, so grep the whole file).
    2. The i21_sqlscripts base-schema table file `i21Database/dbo/Tables/<table>.sql` — **base-schema columns are deployed on ALL branches**, so a column present there already exists on the target even when i21_Liquibase has no changeset for it. Read it from a local clone (`git -C <SQLSCRIPTS_ROOT> grep -niE "\[?<column>\]?" origin/<TARGET_BRANCH> -- "i21Database/dbo/Tables/<table>.sql"`) or, when none is available, through the Azure DevOps REST file-content API — do not skip the check.
    - **Column FOUND in either repo** -> the column add is a no-op: drop that changeset and record it as ALREADY EXISTS / NO-OP with the grep output in the technical changelog. If it was the whole change, there is nothing to PR.
    - **Column NOT found** -> the changeset MUST carry the guard: `--preconditions onFail:MARK_RAN` plus `--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '<table>' AND COLUMN_NAME = '<column>'` (team pattern — `TEAM_LIQUIBASE_STANDARDS.md` §5 / Development Standard §C, §E). An unguarded `ALTER TABLE ... ADD` -> **STOP** (do not commit, push, create, approve, or auto-complete the PR): a repo grep cannot see environments that already carry the column out-of-band, and a duplicate add fails deployment with `Msg 2705 — Column names in each table must be unique`.
    - This gate is static and repo-only; the `liquibase update` dev-DB apply below is the authoritative runtime check. When no DB is reachable (R-DBAPPLY-BESTEFFORT), this gate plus the precondition are the enforced substitutes — state that in the PR and Jira comment; never word it as "verified on dev DB".
  - Check new changeset IDs against `TEAM_LIQUIBASE_STANDARDS.md` and Development Standard §A; fail validation if **any** new changeset — schema OR `runOnChange` logic object (function/SP/view/trigger) — uses a version-style ID. Scan changed `.sql` for headers matching `:[0-9]+\.[0-9]+(\.[0-9]+)? ` and re-ID them to timestamps before commit.
  - Confirm correct folder/file placement, presence of `endDelimiter:GO` where required, a `--comment:` line, preconditions where the object may already exist, and a valid rollback.
  - **`--comment:` JIRA value (advisory, not a hard fail for `runOnChange` logic):** for a `runOnChange:true` logic object (function/SP/view/trigger), the `--comment:` may legitimately cite the **originating** JIRA (the functional ticket the code change belongs to) rather than the current work JIRA — e.g. a compile-fix carried under `AP-24431` whose changesets still reference `AP-23712`. Because `runOnChange:true` re-applies the object on every change regardless of the comment text, this mismatch does **not** break deployment and is **acceptable**. Do not fail validation on it; note it as informational. (For non-`runOnChange` schema changesets, keep `--comment: <JIRA>` aligned to the work JIRA.)
  - Check that existing one-time DDL changesets were not modified in a way that can change deployed checksums (§B).
  - **Column/identifier-binding check (mandatory — see §J):** for every changed SP/function/view, resolve each column referenced against a UDT, table, or table variable (INSERT column lists, `INSERT … EXEC` target lists, SELECT-list aliases consumed downstream, `@var` of a UDT type) back to that object's `CREATE TYPE` / `CREATE TABLE` definition and confirm the name exists **exactly**. Fail validation on any unresolved name.
  - Apply `beautify 3.md` checkpoints for touched Liquibase SQL files.
  - Run `liquibase validate` / `liquibase update` against a development database (Development Standard §G / Rule #3). **This step must be ATTEMPTED, and is REQUIRED whenever a database is reachable, when a changed logic object writes into a UDT or table** (any `INSERT`, `INSERT … EXEC`, `MERGE`, or table-variable populate of a typed/`CREATE TYPE` target), because a column/identifier mismatch in that case only surfaces at SQL compile/bind time (SQL Server error 207 "Invalid column name"). **R-DBAPPLY-BESTEFFORT: an unreachable dev DB is NOT a hard STOP** — if no dev DB is reachable for such a change, fall back to the §J static object-binding check as the enforced fail-closed gate (an unresolved column still fails validation), record "dev-DB apply not run" + the reason, and continue; do **not** mark validation as dev-DB-passed. For changed files that do not write into a UDT/table, run it when credentials are available and record why if not.
- If validation cannot be run for a required check, record the reason and **do not** treat the validation as passed silently — STOP unless the team explicitly waives that check.

FEATURE / TECHNICAL DEBT GATE (MANDATORY when ISSUE_CATEGORY = FEATURE or TECHNICAL_DEBT):

1. **Linter pre-check:** run repository-appropriate static validation for all changed files; record output.
2. **Dependency check:** inspect the diff and identify all dependencies the change requires (referenced types, base classes, interfaces, API endpoints, routes, ExtJS classes/components, stored procedures, views, Liquibase tables/columns/changesets, configuration keys). For each, verify it exists in the repository (or is part of CHANGESET). For UDT/table/column dependencies, apply the §J exact-binding check — a renamed-but-self-consistent identifier is a **MISSING DEPENDENCY**.
3. **Continue / STOP rule:** continue only if there are **no new linter errors** AND **all dependencies resolve**. Otherwise STOP and report the linter failures and/or missing dependencies.

RESULT OF §3:
- **PASS (no issue):** continue to §4.
- **FAIL:** STOP. Report the failing check(s) and the offending file(s)/identifier(s). Do not create a branch, commit, push, or PR.


## §4 Move the validated changes onto the work branch and commit

Only reached when §3 passed.

1. Put the validated changes on the work branch (this preserves uncommitted working-tree changes and any local commits):
   - IF the current branch is **already** `<WORK_BRANCH>` (the work-branch-detection case from §1 — you are on `<base>_<JIRA>`): you are already on the correct branch; **do nothing here** (no checkout, no double-suffix). Proceed to step 2.
   - ELSE: `git checkout -B <WORK_BRANCH>`.

   Do **not** commit directly to `<TARGET_BRANCH>`.

2. Stage and commit the validated changes:
   - `git add -A` (or stage only the intended files if there are unrelated local edits — never commit validation artifacts or unrelated changes).
   - Commit message MUST include `<JIRA>` and briefly describe the fix intent.
   - If the changes were already committed on the current branch (source B in §2), they are already on `<WORK_BRANCH>` (carried by the `checkout -B`, or already present when the current branch *is* the work branch); only commit the remaining uncommitted changes.

3. After committing, re-inspect the diff before pushing:
   - Confirm only the JIRA intent is present.
   - Confirm no duplicate properties/columns/routes/methods were introduced.
   - Confirm no unrelated target-only fields, procedures, filters, or API endpoints were removed.
   - For Liquibase schema files, confirm no existing deployed changeset was modified unless it is a `runOnChange:true` logic object where the standards allow it.
   - For all Liquibase files, confirm every new changeset uses a timestamp ID and does not duplicate an existing `author:id` pair.


## §5 Push (single connection)

`cd <REPO_ROOT>`

`git push origin <WORK_BRANCH>`

After the push succeeds, continue to §6 (post the RCA), then §7 (create the PR).


## §6 Root Cause Analysis (RCA) — Jira comment (MANDATORY, post BEFORE the PR)

Post the RCA as a comment on the parent `<JIRA>` **before** creating the PR (§7). This documents the analysis while the change is fresh and gives reviewers the context before the PR opens.

PRE-REQ:
- §3 validation passed and §5 push succeeded.
- Jira integration tool available and cloudId resolved (e.g. getAccessibleAtlassianResources).
- The JIRA issue (`getJiraIssue` for `<JIRA>`) and the CHANGESET diff from §2 are available.

**RCA FORMAT (mandatory — match this structure).** This is the team RCA format used on the i21 AP project (e.g. AP-22872). Build `JIRA_RCA_BODY` from JIRA (symptom/expected behavior) + the CHANGESET diff (root cause, evidence, fix), traceable to evidence only — no invented work. Omit the optional **Proof of testing** block if no test screenshots/output are available; never fabricate proof.

```
# Root Cause Analysis

**Issue:**

<What the user/QA observed — the reported symptom(s). Use a short numbered list when there are multiple distinct failures.>

**Root Cause:**

<The underlying cause. When the failure spans layers (DB / BL / UI / config), break it down per layer. Name the specific defect — e.g. a column/identifier mismatch against a UDT, a non-SARGable filter, a missing menu entry.>

**Investigation:**

<How the cause was confirmed — what was validated and in what order; what evidence (logs, error 207, query result, grid behavior) pinned it down.>

**Technical evidence (for dev/QA):**

<Bulleted, grouped by area. Name the actual files/objects changed and what changed in each, drawn from the CHANGESET diff. Example grouping:>
* **<Area, e.g. Logic / SP fix>**
    * `<repo/path/to/file.sql>`
    * <what changed and why>

**Steps to Replicate:**

1. <step>
2. <step>
3. <observe prior failure>
4. <after fix, observe correct behavior>

**Proposed Solution:**

<The fix delivered (1–2 lines) + a short prevention/regression checklist for this area.>

----------------------------------------------
**Proof of testing-**

<Optional — attach/reference test screenshots or output if available; otherwise omit this block entirely.>
```

Call `addCommentToJiraIssue`:
- issueKey: <JIRA>
- cloudId: resolved
- commentBody: `JIRA_RCA_BODY`
- contentFormat: markdown

Rules:
- **ONE** `addCommentToJiraIssue` call for the RCA, posted **before** §7 (PR creation).
- The RCA is distinct from the §8 PR-link comment and the §8.1 technical changelog — do not merge them.
- Every **Root Cause** / **Technical evidence** claim must be traceable to the CHANGESET diff or the JIRA description; do not invent symptoms, layers, or fixes.
- Do NOT use the Jira REST API directly.
- FAIL (STOP before PR) if the tool is unavailable.


## §7 Create the Pull Request (Azure DevOps REST API) — single PR

Use `ADO_REPO` in every URL below.

Auth:
- Use Bearer token from `az account get-access-token` (see auth section).
- Do NOT use GIT_TOKEN or PAT from this prompt.
- Do NOT run git credential fill for ADO REST.

Header:
Authorization: Bearer <access_token>
Content-Type: application/json


### §7.1 PR Description Builder (MANDATORY)

DO NOT reuse any other PR description as-is.

Read the Pull Request Standard Format page before composing `BUILT_PR_DESCRIPTION`:
https://irely.atlassian.net/wiki/spaces/FRM/pages/62009675/Pull+Request+Standard+Format

The standard format controls the section layout. Field values come from the source priority below.

SOURCE PRIORITY:
1. JIRA (PRIMARY SOURCE OF TRUTH for title, priority, type, root cause, customer) — read issue `<JIRA>` (getJiraIssue).
2. CHANGESET diff (for Change Log).

RULES:
- Title inside description: `<JIRA> - <JIRA TITLE from Jira>`
- Priority / Type / Root Cause / Customer: from JIRA only (use `N/A` when the field is absent).
- Change Log bullets: prefer user-visible or data-change phrasing over vague "Updated configuration". Derive from the CHANGESET diff only.
- Notes: `N/A` unless explicitly required.

FINAL FORMAT:

```
<JIRA> - <JIRA TITLE>

Jira: https://irely.atlassian.net/browse/<JIRA>

Priority: <JIRA Priority>

Type: <JIRA Type>

Root Cause: <value or N/A>

Customer: <value or N/A>

Change Log:
- <short diff-based summary>

Notes:
- N/A
```

Cache result as `BUILT_PR_DESCRIPTION`.


### §7.2 Create the PR

TITLE RULE: `RESOLVED_TITLE = "<JIRA> to <TARGET_BRANCH>"` (e.g. `AP-22925 to 26.2Dev`).

POST:
https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_apis/git/repositories/<ADO_REPO>/pullrequests?api-version=7.0

Authorization: Bearer <access_token>
Content-Type: application/json

Body:

```json
{
  "sourceRefName": "refs/heads/<WORK_BRANCH>",
  "targetRefName": "refs/heads/<TARGET_BRANCH>",
  "title": "<RESOLVED_TITLE>",
  "description": "<BUILT_PR_DESCRIPTION>"
}
```

Cache:
PR_ID = response.pullRequestId
PR_URL = constructed PR web URL for this repo


### §7.3 Auto-approve + auto-complete (MANDATORY)

Resolve **YOUR_ID** once per run.

PRE-REQ:
- Resolve current user's identity GUID.
- ADO REST calls use Bearer token from az (same session as §7).

GET:
https://vssps.dev.azure.com/<ADO_ORG>/_apis/graph/users?api-version=7.0
Authorization: Bearer <access_token>

Find user where principalName or mailAddress matches current az account (az account show). Cache `YOUR_ID = matching user descriptor or originId as required by the reviewers API`.

FAIL if identity cannot be resolved.

FALLBACK if Graph returns 401:
- Use GET https://dev.azure.com/<ADO_ORG>/_apis/connectionData?api-version=7.0-preview.1 (Authorization: Bearer <access_token>)
- OR read createdBy.id from the created PR response.
- Cache that value as YOUR_ID.

**§7.3.1 Approve PR** — PUT:
https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_apis/git/repositories/<ADO_REPO>/pullrequests/<PR_ID>/reviewers/<YOUR_ID>?api-version=7.0
Authorization: Bearer <access_token>
Content-Type: application/json

Body:
```json
{ "vote": 10, "isFlagged": false, "hasDeclined": false }
```

**§7.3.2 Enable Auto-Complete** — PATCH:
https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_apis/git/repositories/<ADO_REPO>/pullrequests/<PR_ID>?api-version=7.0
Authorization: Bearer <access_token>
Content-Type: application/json

Body:
```json
{
  "autoCompleteSetBy": { "id": "<YOUR_ID>" },
  "completionOptions": {
    "deleteSourceBranch": true,
    "mergeStrategy": "noFastForward",
    "transitionWorkItems": true,
    "autoCompleteIgnoreConfigIds": [],
    "bypassPolicy": false
  }
}
```

After §7, build `JIRA_PR_COMMENT`:

```
Pull Request (<PRODUCT>)

- [<TARGET_BRANCH> - <PRODUCT>](<PR_URL>)
```


## §8 JIRA (<JIRA>) — PR link on parent (no changelog here)

Use the Jira integration tool.

PRE-REQ:
- cloudId resolved (e.g. getAccessibleAtlassianResources).
- `JIRA_PR_COMMENT` built from §7.

Call `addCommentToJiraIssue`:
- issueKey: <JIRA>
- cloudId: resolved
- Body: `JIRA_PR_COMMENT`

Rules:
- **ONE** `addCommentToJiraIssue` call on parent `<JIRA>`; body = `JIRA_PR_COMMENT`.
- MUST add the created PR as a markdown web link on the parent Jira.
- DO NOT post the **Changelog** here (that is §8.1) or the RCA (that was §6).
- DO NOT use the Jira REST API directly.
- FAIL if the tool is unavailable.


## §8.1 JIRA (<JIRA>) — technical changelog on parent

Post a **developer-facing** summary of what changed. Separate comment from §8 (PR link) and §6 (RCA).

PRE-REQ:
- CHANGESET diff / `--stat` available.
- Do **not** post until §7 finished.

**Compose `JIRA_CHANGELOG_BODY`** (cache verbatim):

SOURCE (mandatory):
- The CHANGESET diff from §2 (per-file diff and `--stat`) for this repo.
- One bullet per **distinct technical change**.

STYLE — technical:
- Name **files, types, procedures, columns, parameters, screens** as in the diff.
- Verb-led, past tense or imperative: "Added …", "Updated …", "Mapped …", "Passed … through …".
- Traceable to the diff only — no invented work.

FINAL FORMAT (match exactly):

```
**Changelog**:

- <technical change 1>
- <technical change 2>
```

Rules:
- Heading must be `**Changelog**:` followed by a blank line, then `- ` bullets.
- At least **one** bullet; empty changelog → **STOP** and re-read the diff.

Call `addCommentToJiraIssue`:
- issueKey: <JIRA>
- cloudId: resolved
- commentBody: `JIRA_CHANGELOG_BODY`
- contentFormat: markdown

Rules:
- **ONE** `addCommentToJiraIssue` call for the changelog (separate from the §8 PR comment and the §6 RCA).
- DO NOT duplicate the full PR description.
- FAIL if the tool is unavailable.


# ==================================================================
# RULES (summary)
# ==================================================================

- JIRA_KEY is a required input parameter, validated against `[A-Z][A-Z0-9]+-\d+$`. It is used for PR metadata, the work-branch name, and the Jira comments only — never for cross-branch commit discovery.
- **No propagation.** This runbook does not derive a `BRANCHES` list, does not route by BASE_BRANCH / customer / LOB, does not cherry-pick onto multiple branches, and does not create merge/fan-out PRs. It validates the current repository's pending changes and opens exactly one PR.
- The PR target is `TARGET_BRANCH` (the current branch by default, or the explicit override). The PR source is `<TARGET_BRANCH>_<JIRA>`. A PR never targets its own source branch.
- Parent Jira issue type must be one of `Bug`, `Bug-QC`, `Bug-UAP`, `Bug-Ongoing UAP`, `Config`, `Feature`, `Gap`, `Paid`, `Suggestion`, `Technical Debt`, or `Performance`; STOP if the issue type is missing, inaccessible, or outside this list. (`Config` = billable bug → BUG; `Performance` → TECHNICAL_DEBT.)
- For FEATURE / TECHNICAL_DEBT issues: before pushing, verify linter checks pass with no new errors and all dependencies resolve (including §J exact column/identifier binding); STOP if either fails.
- **When the change touches SQL scripts (`IS_LIQUIBASE_STANDARD_CASE = true`): apply the "Liquibase standard compliance" section (§A–§J).** Every new changeset uses a timestamp ID in the correct folder/file, with preconditions where it may already exist, a rollback, and `endDelimiter:GO` where required; validate with `liquibase update` where possible (attempted, and required whenever a DB is reachable, when a changed logic object writes into a UDT/table; §J static binding is the enforced gate when no DB is reachable — R-DBAPPLY-BESTEFFORT). Never commit a version-style changeset or a raw SSDT/`SqlScript` file.
- Validation runs **before** any branch/commit/push/PR. Create the PR only if validation passes with no issue.
- If there are no pending changes (empty CHANGESET) -> STOP and report; do not create a branch or PR and do not comment on Jira.
- One fetch and one push for the repository; one az auth session for all ADO REST calls.
- STOP if: JIRA_KEY is missing/invalid; the workspace is not a git repo; TARGET_BRANCH does not exist on origin; the Azure DevOps MCP preflight fails; `az login` or `get-access-token` fails; `YOUR_ID` cannot be resolved for auto-approve/auto-complete; or any required validation check fails or cannot be run and is not explicitly waived.
- Jira activity order on the parent issue: §6 (**Root Cause Analysis**, before the PR) → §8 (PR link, after the PR) → §8.1 (**Changelog**). The RCA uses the team format from AP-22872 (Issue / Root Cause / Investigation / Technical evidence / Steps to Replicate / Proposed Solution). There is no completion-label step.
