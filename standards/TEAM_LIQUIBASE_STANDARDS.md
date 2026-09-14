# Team standards: Liquibase in this repository

This document is **iRely’s team layer** on top of the official Liquibase product documentation. Read it **before** the generic Liquibase docs when working in this repo. Official reference: [Liquibase documentation](https://docs.liquibase.com/).

Sources: *Liquibase: Development Standard* and *Liquibase: Migration Standards* (Confluence exports, January 2026 policy).

---

## 1. Changeset identifiers (January 2026 onward)

- **New changesets** must use **timestamp-based IDs**, not version-style IDs. This applies to **every** new changeset type — schema/table/FK/index/UDT **and `runOnChange` logic objects** (functions, stored procedures, views, triggers). It is **not** limited to schema changesets.
  - **Preferred:** `YYYYMMDDHHmmss` (example: `20260101090000`).
  - **Deprecated for new work:** version-style IDs such as `25.1.1` or `24.2.1`.
  - **Cherry-pick / copy caveat:** a literal `git cherry-pick` or a wholesale copy of a source logic object brings the source changeset id across verbatim, which is frequently version-style. When propagating a fix this way, **re-id** any newly introduced version-style changeset to a fresh timestamp id (and set `--comment:` to the propagated ticket) before commit — this applies to `runOnChange` logic objects too, not only schema.
- **Existing** changesets (for example `24.x`, `26.x`) **do not** need to be renamed. Only **new** changesets must follow the timestamp rule.
- For tooling and snippets that generate timestamp IDs automatically, see the internal guide: [Liquibase Code Snippets Usage Guide](https://irely.atlassian.net/wiki/spaces/FRM/pages/424870503/Liquibase+Code+Snippets+Usage+Guide) (Confluence, FRM space).

In formatted SQL, the header looks like:

```text
--changeset you.name@irely.com:20260514120000
```

---

## 2. Development rules (non-negotiable)

### Rule 1 — Schema changes go through Liquibase

Do **not** apply schema changes manually in **Development** or **Production**. Use Liquibase. Manual drift causes deployment failures and mismatched environments.

### Rule 2 — Deployed changesets are immutable

Once a changeset has run in **any** environment, you **must not** edit it (including whitespace, comments, or SQL text).

- Liquibase stores a **checksum** per changeset in the changelog table (this project uses custom names; see `liquibase.properties`: `databaseChangeLogTableName`, `databaseChangeLogLockTableName`).
- Any change to the file content changes the checksum and leads to **checksum validation errors** on the next run.

**Correct approach:** add a **new** changeset that performs the fix or adjustment.

**Exceptions (when editing may be allowed):**

1. **`runOnChange: true`** — used for **logic** objects (stored procedures, views, functions, and similar) where the team standard intentionally allows the file body to be updated and re-applied.
2. **Local development only** — if the changeset has **only** ever run on your machine, you have **not** pushed to Git, and you have rolled back locally before editing. As soon as it is shared or deployed elsewhere, treat it as immutable.

### Rule 3 — Verify before you push

Run **`liquibase update`** (or your team’s equivalent pipeline) against a **development** database and confirm the migration behaves as expected **before** pushing changes.

> In this repository, CLI commands typically require a JDBC `url` (and related credentials) in `liquibase.properties` or on the command line; `validate` / `update` will fail without them.

### Rule 4 — Preconditions when SSDT and Liquibase overlap

Use **preconditions** when the same change might exist from **SSDT** and **Liquibase** (common when lifting changes from older branches or versions, for example **23.1 and below** into **24.1+**).

- Use **`onFail: MARK_RAN`** (or the pattern your team’s examples use) so duplicate definitions do not fail the run when the object already exists.
- **Do not** blanket every changeset with heavy preconditions; overuse can hurt deployment performance.
- Preconditions may also be used for **pre/post deployment** scenarios where the team pattern calls for them.

### Rule 5 — Avoid misleading `--rollback` text in non-Liquibase SQL

Do **not** put Liquibase-style rollback markers (`--rollback`) in **logic** scripts that are **not** meant to participate in Liquibase rollback parsing.

Also avoid ordinary SQL comments that look like Liquibase rollbacks — for example a line that is only `-- ROLLBACK` in a stored procedure — so parsers and reviewers are not confused. Use a different phrasing (for example describe the application flow without a standalone `-- ROLLBACK` comment).

---

## 3. Migration standards (what to edit for each change type)

### 3.1 Versioning model (high level)

- **23.1 and below:** schema and many scripts still originate from **SSDT**.
- **24.1 and above:** changes are expected to live in **Liquibase** as the migration source of truth.
- When porting **from lower versions** into higher versions, **transfer** the SSDT (or script) changes into this Liquibase project following the patterns below.

### 3.2 Logic (stored procedures, views, functions, triggers)

- Follow: [Liquibase: Logic (fn, sp, view, trg)](https://irely.atlassian.net/wiki/spaces/FRM/pages/62012975/Liquibase+Logic+Function+Stored+Procedure+View+Trigger).
- **Compare** scripts between the older version and the target version, **merge** intentionally, then paste the result into the appropriate Liquibase file.
- If no file exists for the object in this repo, **create** one with the merged content.
- If a file **already exists**, **replace** its content with the merged result (subject to `runOnChange` and team rules for immutability of one-time DDL changesets).

### 3.3 Schema (tables, foreign keys, indexes, user-defined types)

- Follow: [Liquibase: Schema (table, fk, index, udt)](https://irely.atlassian.net/wiki/spaces/FRM/pages/62011589/Liquibase+Schema+Table+Foreign+Keys+Index+User-Defined+Type).
- When changing a **UDT**, check whether old database schemas can restore stale dependent logic during `uspSMLiquibaseRefreshUdt`. If a dependent stored procedure, function, view, or trigger can be recreated from an old saved definition that references removed or renamed columns, add a cleanup changeset under `dependencies\udt\<UdtName>.sql` using `uspSMLiquibaseDropLogic '<ObjectName>', '<OBJECT_TYPE>'` before the UDT refresh runs.
- For **new tables** (and similar one-time DDL), include **preconditions** so the changeset is safe when the object may already exist from SSDT or a prior partial deploy. Example pattern from team standards (abbreviated):

```sql
--liquibase formatted sql

--changeset author@irely.com:20260106073241
--comment: TICKET - Create tblExample
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'tblExample'
CREATE TABLE [dbo].[tblExample] ( ... );
--rollback DROP TABLE [dbo].[tblExample];
```

- More samples: [Liquibase: Examples](https://irely.atlassian.net/wiki/spaces/FRM/pages/62015257/Liquibase+Examples).

---

## 4. How this repository is wired (quick map)

| Area | Location | Included from |
|------|----------|-----------------|
| Root changelog | `root-changelog.xml` | Entry point (`changeLogFile` in `liquibase.properties`) |
| Table / FK / index / UDT / stats | `schema\tables`, `schema\foreign-keys`, etc. | `includeAll` in `root-changelog.xml` |
| Logic | `logic\functions`, `logic\views`, `logic\stored-procedures`, `logic\triggers` | `root-changelog.xml` |
| Core / dependencies / data / utilities | `core\`, `dependencies\`, `data\`, `utilities\` | `root-changelog.xml` |

**Practical rule:** put **table** DDL for `dbo.tblFoo` in `schema\tables\tblFoo.sql` (or the file your table already uses), using `--liquibase formatted sql` and one or more `--changeset` blocks.

---

## 5. Standard pattern: add a nullable column to an existing table

Use the same style as other columns on that table:

1. **`--liquibase formatted sql`** once at top of file (if not already present).
2. **`--changeset`** with **email:timestamp** id.
3. **`--comment:`** with ticket or short reason.
4. **`--preconditions onFail:MARK_RAN`** plus **`--precondition-sql-check`** so the column is only added if missing (idempotent with SSDT / replays).
5. **`ALTER TABLE ... ADD`** with explicit nullability and constraints.
6. **`--rollback`** using `uspSMLiquibaseDropColumn` (and default-constraint drops if you added a default).

**Worked example in this repo:** `dblNewColumn` on `tblAPPayment` (`DECIMAL(18,6) NULL`) — see the last changeset in `schema\tables\tblAPPayment.sql`.

---

## 6. Checklist before opening a PR

- [ ] New changesets use **timestamp** IDs (`author@irely.com:YYYYMMDDHHmmss`).
- [ ] No edits to changesets already deployed outside your machine.
- [ ] Preconditions present where SSDT / duplicate deploy risk exists; otherwise kept minimal.
- [ ] Rollback defined for schema changes where the team expects it.
- [ ] No spurious `--rollback` / `-- ROLLBACK` patterns in logic per Rule 5.
- [ ] **lb-204:** stored-procedure changesets include `endDelimiter:GO` on the `--changeset` line.
- [ ] **lb-205:** a standalone `GO` sits on its own line immediately before `--rollback`.
- [ ] `liquibase update` (or CI) run successfully against dev.

---

## 6a. Code review rules — stored procedures (lb-204 / lb-205)

### Rule lb-204 — Add `endDelimiter:GO` on the changeset line for this stored procedure

Example:

```sql
--changeset wendell.villareal@irely.com:20260910160100 runOnChange:true endDelimiter:GO
```

### Rule lb-205 — Put a standalone `GO` on its own line before `--rollback` so the batch splits correctly

Example:

```sql
END
GO
--rollback EXEC uspSMLiquibaseRollbackLogic 'uspSTGenerateShelfTagPreview'
```

---

## 7. Official Liquibase docs (use after this page)

Use the upstream manuals for syntax edge cases, global flags, and product behavior, for example:

- [Liquibase SQL format](https://docs.liquibase.com/concepts/changelogs/sql-format.html)
- [Changeset attributes](https://docs.liquibase.com/concepts/changelogs/changeset.html)
- [Preconditions](https://docs.liquibase.com/concepts/changelogs/preconditions-introduction.html)

This team document does not replace those references; it **prioritizes iRely policy and repo layout** so changes stay deployable and reviewable.
