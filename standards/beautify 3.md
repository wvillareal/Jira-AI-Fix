# Beautify changed Liquibase SQL scripts

Execute this runbook **immediately** in **Agent mode** in the **i21_Liquibase** repository. Work on all in-scope SQL files **changed on the current feature branch since it split from the base branch** (see Scope), plus any uncommitted changes. Do not ask for confirmation unless a mandatory STOP or cancel condition applies.

---

## Branch parse: BASE and JIRA (do not set manually)

Run:
```bash
git branch --show-current
```

Expected pattern: `<BASE_BRANCH>_<JIRA>`

Examples:
- `26.3Prod_MFG-13187` → `BASE = 26.3Prod`, `JIRA = MFG-13187`
- `24.2Dev_MFG-13203` → `BASE = 24.2Dev`, `JIRA = MFG-13203`

Parse rules:
- `JIRA` = trailing segment matching regex: `[A-Z][A-Z0-9]+-\d+$`
- `BASE` = branch name with `_<JIRA>` removed (everything before the final `_` + JIRA segment)
- If parse fails or branch does not match → **STOP** (do not guess; do not use a hardcoded comment)

Changeset **comment** value = `JIRA` (e.g. `MFG-13203`).

---

## Scope (all files on this branch since split from base)

Use the **base branch at branch creation** (merge-base), **not** the latest tip of base if others have pushed since. A **three-dot** diff does this automatically.

### Resolve base ref

```bash
git fetch origin <BASE> --quiet
```

Prefer `BASE_REF=origin/<BASE>`. If `origin/<BASE>` does not exist, use local `<BASE>` only if it exists; otherwise **STOP**.

### List changed files (primary)

All commits on the current branch since it diverged from base:

```bash
git diff --name-only origin/<BASE>...HEAD
```

Equivalent: `git diff --name-only $(git merge-base origin/<BASE> HEAD)...HEAD`

This includes files committed earlier on the feature branch (e.g. `schema/tables/`), not only the working tree.

### Also include uncommitted work (union)

```bash
git diff --name-only HEAD
git diff --name-only --cached
```

Union all three file lists, then keep only paths under the beautify folders below.

### Classify (in-scope paths only)

| Type | Path |
|------|------|
| Stored procedures | `logic/stored-procedures/*.sql` (not `ReadmeMFG.md`) |
| Views | `logic/views/*.sql` (not `ReadmeMFG.md`) |
| Schema tables | `schema/tables/*.sql` (not `ReadmeMFG.md`) |

Skip everything else (e.g. `schema/udt/`, `logic/functions/`) unless the user explicitly extends scope in chat.

**Do not** use a two-dot diff (`origin/<BASE> HEAD`) for scope — that compares branch tips and pulls in unrelated changes when base has moved forward.

---

## Beautify tasks (checkpoints only)

- **Stored procedures only** — in-scope files under `logic/stored-procedures/`: beautify using `logic/stored-procedures/ReadmeMFG.md`, **checkpoints only**, plus **RAISERROR formatting** (below).
- **Views only** — in-scope files under `logic/views/`: beautify using `logic/views/ReadmeMFG.md`, **checkpoints only**.
- **Schema tables only** — in-scope files under `schema/tables/`: beautify using `schema/tables/ReadmeMFG.md`, **checkpoints only**.

Read each applicable `ReadmeMFG.md` from the workspace before editing. Apply **only** the checkpoints defined there; for stored procedures, also apply **RAISERROR formatting** below — do not invent other rules.

**Exclude:** `ReadmeMFG.md` (any path) — never modify.

---

## Liquibase changeset metadata

For every changeset block touched in changed files:

- Set **author** / changeset person to: `jonathan.valenzuela@irely.com`
- Set **comment** to: `<JIRA>` parsed from current branch (see above)

---

## Rules (mandatory)

| Area | Rule |
|------|------|
| **Stored procedures & views** | Do **not** refactor. Do **not** change logic. **Strictly beautify/format only.** Must **not** affect query logic or behavior. |
| **Stored procedures** | Use **RAISERROR** (not `THROW`) for user-facing errors. Apply **RAISERROR formatting** below. |
| **Schema tables** | Beautify per ReadmeMFG checkpoints only. |
| **All** | Skip files outside the three folders above unless they are table scripts under `schema/tables/`. |

---

## RAISERROR formatting (stored procedures only)

Apply when beautifying in-scope stored procedures, in addition to `ReadmeMFG.md` checkpoints.

### Prefer RAISERROR over THROW

- Replace `THROW` with `RAISERROR` for validation and business-rule errors (same message text and severity/state semantics).
- In `BEGIN CATCH`, use `SET @ErrMsg = ERROR_MESSAGE()` then `RAISERROR (@ErrMsg, 16, 1, 'WITH NOWAIT')` — not `THROW;`.
- Declare `@ErrMsg NVARCHAR(MAX)` when the procedure uses a catch block that re-raises.

### RAISERROR inside `IF` — `BEGIN` / `END` required

When `RAISERROR` is the statement executed under an `IF` (including `IF EXISTS (...)`), the body **must** be wrapped in `BEGIN` / `END`:

- `BEGIN` on its own line, indented **one TAB** from the `IF` line.
- `END` on its own line, aligned with `BEGIN`.
- `RAISERROR` and its arguments inside the block, indented **one TAB** from `BEGIN`.

Do **not** place `RAISERROR` directly on the line after `IF` without `BEGIN` / `END`.

### RAISERROR — newlines and indent

Format every `RAISERROR` with the keyword, opening `(`, each argument, and closing `)` on separate lines:

1. `RAISERROR` on its own line (inside `BEGIN`, one TAB from `BEGIN`).
2. Opening `(` on the next line, one TAB from `RAISERROR`.
3. Each argument on its own line, one TAB from `(`; first argument is the message (no leading comma).
4. Second and later arguments each start with `, ` (comma + space) on the same line as the value.
5. Closing `)` on its own line, aligned with opening `(`.

**Reference format** (`IF` + `BEGIN` / `END` + multi-line `RAISERROR`):

```sql
IF EXISTS (SELECT *
           FROM @udtMFShift AS Shift
           WHERE LOWER(strRowState) = 'added'
             AND EXISTS (SELECT *
                         FROM dbo.tblMFShift AS ExistingShift
                         WHERE ExistingShift.intLocationId = @intLocationId
                           AND ExistingShift.strShiftName = Shift.strShiftName))
	BEGIN
		RAISERROR
		(
			'Shift name should be unique.'
			, 11
			, 1
		)
	END
```

**Parameterized message** (same layout; add substitution args after state):

```sql
		RAISERROR
		(
			'Shift ''%s'' already used in Transaction (Work Order), Shift cannot be deleted.'
			, 11
			, 1
			, @strShiftName
		)
```

- Business-rule severity/state: `11`, `1` (match existing MFG shift procedures unless the file already uses another documented pattern).
- `BEGIN CATCH` re-raise: single-line `RAISERROR (@ErrMsg, 16, 1, 'WITH NOWAIT')` is acceptable.

---

## Pre-flight cancel (STOP — do not beautify)

Before editing, for each in-scope **stored procedure** file:

1. Confirm **file name** aligns with the **SP name** inside the script.
2. Confirm **Liquibase Save Logic** and **Rollback** sections exist and are consistent with repo conventions in the matching `ReadmeMFG.md`.

If **any** SP file fails name / Save Logic / Rollback alignment → **cancel this entire prompt** (STOP, report which file failed, make no edits).

---

## Execution order

1. Parse `BASE` and `JIRA` from `git branch --show-current`; STOP if invalid.
2. `git fetch origin <BASE>`, then list in-scope SQL files via `origin/<BASE>...HEAD` (union with uncommitted diffs); classify (SP / view / schema table).
3. Run pre-flight cancel check for all in-scope SPs.
4. Read relevant `ReadmeMFG.md`(s).
5. Beautify per `ReadmeMFG.md` checkpoints; for stored procedures, also apply **RAISERROR formatting**; update changeset author and comment (`<JIRA>`).
6. Summarize files touched and confirm no logic changes on SP/view.

---

## Do not

- Refactor or rename objects in SP/view scripts (except filename alignment check — if misaligned, cancel instead of renaming without explicit user approval).
- Change `WHERE`, `JOIN`, `SELECT` lists, parameters, or control flow in SP/view.
- Edit `ReadmeMFG.md`.
- Beautify unrelated paths (e.g. `schema/udt/`, `logic/functions/`) unless the user explicitly extends scope in chat.
- Use working-tree-only scope when branch commits exist — always run `origin/<BASE>...HEAD` first.
