# JIRA-AI-Fix runbook (module-agnostic) — analyze → apply acceptance → feature branch → RCA/Acceptance Verification

> **Version.** `1.9.0` · source copy — hand-distributed, not unpacked from a release zip
>
> **Local merge note (2026-09-14):** merged onto `JIRA-AI-Fix 20.md` (1.9.0) while **retaining §1.6e Knowledge Base** and `KB-CONSULTED` / R-KB-* cross-refs from the prior 1.8.0 working copy (1.9.0 had dropped that section). New 1.9.0 rules kept: **R-CLONE-NONINTERACTIVE**, **R-MODULE-STANDARD-OWNER**, **R-MODULE-STANDARD-ABSENCE**, and related §2.7 / §3.6 wording.

Execute this runbook **immediately and completely** in **Agent mode** once a **JIRA_KEY** is provided. Given only a Jira key, it:

1. **Analyzes** the Jira issue.
2. **Checks** the acceptance criteria.
3. **Applies** the acceptance criteria (implements the change in the current repository).
4. **Creates** a feature branch.
5. **Pushes** the feature branch.
6. **Comments** the **Root Cause Analysis (RCA) — Acceptance Verification** on the Jira.

Between steps 1 and 2 two mandatory gates run: **§1.5** (branch/Jira consistency — auto-align) and **§1.6** (resolution feasibility — skip already-resolved tickets; restore the reported database locally per **§1.7** when the symptom is data-dependent; post a single **Information Request** comment and stop when required evidence is missing).

Do not summarize or ask for confirmation unless a mandatory **STOP** condition applies or **the affected repository cannot be auto-resolved from the Jira evidence** (see Input parameters — the runbook identifies the repository itself; it asks the user only as a last resort when that resolution stays ambiguous).

**This runbook does NOT create a Pull Request and does NOT propagate.** It stops after pushing the feature branch and posting the RCA / Acceptance Verification comment on the Jira. (For the PR flow, use `JIRA-PR-Automation.md`.)

**This runbook is module-agnostic.** It runs against **any i21 module** — Accounts Payable, Accounts Receivable, General Ledger, Inventory, Contract Management, System Manager, and any other — and it holds **no per-module configuration**: no table map, no key→module lookup, no GL module string, no document-type list. Every module-specific fact is derived at run time from the ticket, the repository and the connected database, per **Module resolution** below. Where a concrete Accounts Payable object, table or ticket appears in this file it is marked a **worked example**: it records how a gate behaved on a real defect and is there for the reasoning, never as a value to reuse.

**Order:** Accept **JIRA_KEY** (optional **TARGET_BRANCH** override, optional **REPO_ROOT** / **REPO**) → resolve **REPO_ROOT** (the main folder where all i21 repositories reside, default `C:\i21Source`) → read the Jira (§1 issue read + **issue type gate: bug / technical debt / performance / data-fix types only — `Feature`, `Gap`, `Paid`, `Suggestion` and `Config` are out of scope** + **issue status gate: `Open` / `Reopened` only**) → **auto-resolve REPO_PATH** = `<REPO_ROOT>\<repo folder>` from the Jira/module evidence and cross-repo code search (an explicit REPO parameter wins; ask the user only when resolution stays ambiguous) and **load/clone the repository** so the code is locally available and current → resolve a provisional **TARGET_BRANCH** / **FEATURE_BRANCH** → complete the Jira code analysis (§1) → align the branch with the Jira fix version / build (§1.5 — **auto-switch**, STOP only when no base can be derived) → **ask whether we already ran this, and what is different now (§1.6 Step 0.0** — R-RERUN-DELTA: a developer re-runs for four reasons and three of them are a capability we lacked last time, so compare this runbook's own prior comment's recorded basis — ticket state AND capability — against now; no material delta is a STOP that posts nothing**)** → **classify resolution feasibility** (§1.6 — `STATIC` / `DB_REQUIRED-ACTIONABLE` / `DB_REQUIRED-BLOCKED` / `INFO_REQUIRED` / `CANNOT-FIX`; when required, acquire and restore the reported database locally per §1.7, when required information is missing post the standardized **Information Request** comment and STOP, and when the fix cannot land here post the **CANNOT-FIX** details+recommendation comment and STOP) → **decide whether the i21 application itself is required (§1.6b** — R-APP-REQUIRED: two trigger families — the client is the only layer that can raise the symptom, **or** the app-layer deployed state is unknown/disputed (`Apply patch <JIRA>` HDTN, repro steps gated on a patch, a build stamp next to "still occurring", dev/QA disagreeing about reproducibility); classification only, never a STOP**)** → **resolve the app environment and remember it (§1.6c** — R-APP-ENV-REGISTRY: `APP_ENV` comes from the parameter, from a URL found on the ticket, or from the `appEnv` registry in `%USERPROFILE%\.jira-ai-runbook-config.json`; whichever resolves is **probed alive** before use, and what the run learns — liveness, build stamp, session path — is **written back**, so the next ticket on this customer starts with the environment in hand**)** → **check that the customer is running the code we are reading (§1.7b** — script every implicated DB object out of the reported database and diff it against `TARGET_BRANCH`; a stale deployed body means the root cause is a *deployment* gap and the fix already exists**)** → **prove we actually raised the symptom (§1.8** — the mandatory reproduction gate: reported transaction AND a new transaction, on whichever layer is reachable; emits the `REPRO` verdict that §6 must carry, and forbids an RCA that never reproduced anything when a DB or APP_ENV was available**)** → **adjudicate the app question on evidence (§1.8b** — R-APP-ELIMINATION: only when every reachable layer has been *executed* and none raised the symptom, and the symptom belongs to a Trigger A class nothing cheaper can raise, does the run reach `APP_REQUIRED-PROVEN` and post an **ENVIRONMENT REQUEST carrying the elimination ledger** → STOP**)** → check acceptance criteria (§2) → **ask whether the fix should be written or ported (§2.5** — R-ALIGN-TO-SIBLING: diff the changed object's **body** against every active sibling line in **both** repos before authoring; a sibling that already implements the missing behaviour makes the fix a **port** whose source branch the RCA must name, a novel fix authored anyway needs a written justification, and every ported hunk runs the **port-dependency check** (R-PORT-DEPS) — prerequisites verified by content on the target, separable gaps stripped and recorded, an inseparable one a STOP — whatever the ISSUE_CATEGORY**)** → apply the acceptance criteria and validate (§3) → **prove the fix is in the right place (§3.4** — origin trace to where the value is actually lost, reachability of every changed statement on the reported repro, and a fall-through audit of the touched conditional chains; fail-closed, runs before every other §3 check**)** → **prove a client-side fix sits in the tree the branch actually serves (§3.4a** — R-JS-CLIENT-TREE: `universal/` from 23.1 up, `app/` on 22.x and below, detected from the branch and confirmed by per-tree commit counts; a `.js` fix in the unserved tree passes every downstream check and changes nothing**)** → when the fix touches Liquibase and a DB for the JIRA is known, launch the **async schema-change confirmation** on a separate agent (§3.5 — `liquibase update` → rollback verification, DB left rolled back, logs tracked, result commented on the PR; on a pre-24.1 branch the confirmation is instead the case-C **execute-then-restore**: run the changed script on the JIRA's DB, prove it executes, restore the pre-fix definitions so the DB is left unfixed; the main run continues without waiting) → author, validate, test and roll back the **data fix (§3.6)** when ISSUE_CATEGORY = DATA_FIX → check **regression impact (§3.7** — dependents + golden-set differential; repo/DB layer only, no app environment**)** → trace the **defect lineage (§3.8** — which change introduced the defect, which lines already carry a fix, and whether that fix is complete**)** → **property-test the changed object (§3.9** — old vs new side by side on a throwaway local DB, grid built from the code's own decision boundaries, invariants asserted so the fix provably cannot drift**)** → **assemble and prove the deployable patch (§3.10** — when the CHANGESET touches a DB object: whole object bodies, re-runnable, applied to the reported database, reported transaction re-tested symptom-free, pre-fix bodies restored so the DB is left unfixed; attached to the ticket so the customer can be corrected before the build ships**)** → **sweep the data the defect already broke (§3.11** — when the defect persisted a wrong value AND a database is available: one read-only query derived from the proved mechanism, calibrated so the reported transaction appears in its own result set, producing the count and identifiers that say whether a `Data Fix` JIRA is required — a code fix repairs no existing row**)** → create the feature branch and commit (§4) → push (§5) → post the **RCA — Acceptance Verification** comment on the Jira (§6 — **successful deliveries only**; every run that ends without a delivered fix posts the §6.5 triage / information-request / cannot-fix comment instead) → **status handoff (§6.6)** → **PR handoff (§6.7)**.

---

# Optional configurations (accuracy boosters — check at run start)

**All runbook configuration lives in ONE consolidated file:**

`JIRA_AI_CONFIG` = **`%USERPROFILE%\.jira-ai-runbook-config.json`** — user profile, NEVER in a repo. It has six sections: `atlassian`, `helpdesk`, `sharepoint`, `appEnv`, `i21connect`, and `sqlServer` (which contains the `knownServers` registry). Secrets (SQL password, session cookies) may be stored directly in it because the file lives outside every repo — never copy them into a repo, Jira, Confluence, PR, or log.

> **Uninstall safety — this file is not package residue.** `%USERPROFILE%\.jira-ai-runbook-config.json` is created by no GitHub project and deleted by no uninstall; it belongs to the runbooks in this folder. On this machine `%USERPROFILE%\.jira-ai-config.json` is a **hardlink** to it — the name the `@irely/*` skill packages and `Setup-IrelySkills.ps1` use — so both systems read and write ONE file and cannot drift. Deleting that link during an uninstall is safe; deleting this file is not. Exactly **two** things outside this folder must survive an uninstall: **this file**, and **`~/.atlassian-token`** (the real Atlassian credential — `~/.irely-skills/atlassian-token` is only a placeholder template and is disposable). Everything else — `~/.irely-skills/`, `~/.claude/skills/*/`, the global `@irely/*` npm packages — can be removed without affecting these runbooks.
>
> **Exclude this note from content diffs.** It is machine-local provenance, not a runbook rule. When comparing this file against the packaged copy under `~/.claude/skills/*/` or against its GitHub source, skip this blockquote: it is expected to differ, and its absence upstream is not drift.

Every section is operator-maintained except one: **`appEnv` is the single node this runbook writes** (§1.6c, R-APP-ENV-REGISTRY). Each app environment a run finds is recorded there with where it was found, whether it was **still alive** on the last probe, and what build it was serving — so the next ticket on the same customer resolves it from the file instead of rediscovering it, and so a decommissioned environment is caught by one request rather than mistaken for a bug that will not reproduce.

```json
{
  "atlassian":  { "email": "", "apiToken": "", "tokenFile": "<path to ~/.atlassian-token>" },
  "helpdesk":   { "baseUrl": "https://helpdesk.irely.com/irelyi21Live", "cookie": "<session cookie>", "obtainedAt": "<date>",
                  "mcp": { "url": "https://helpdesk.irely.com/iRelyi21Live_MCP", "apiKey": "<bearer key>", "obtainedAt": "<date>", "serverName": "irely-helpdesk" } },
  "sharepoint": { "tenant": "<tenant>.sharepoint.com", "cookie": "<session cookie>", "obtainedAt": "<date>" },
  "appEnv":     { "<envKey>": { "baseUrl": "https://…/2710DEV", "kind": "prod|dev", "customer": "…", "user": "…", "password": "…", "storageState": "<path outside every repo>", "obtainedAt": "<date>",
                                "source": "<AP-24801 description | HDTN 123456 | operator>", "firstSeen": "<date>", "lastCheckedAt": "<date>", "lastAliveAt": "<date>",
                                "status": "alive|unreachable|stale", "consecutiveFailures": 0, "lastError": "<transport reason only>",
                                "lastBuildStamp": "22.12.0829.4808", "lastBuildStampAt": "<date>", "seenOn": [ "AP-24801" ] } },
  "i21connect": { "baseUrl": "https://i21connect.com", "storageState": "<path outside every repo>", "releaseApi": "<XHR endpoint, once discovered>", "obtainedAt": "<date>" },
  "sqlServer":  { "server": "…", "instance": "…", "auth": "sql", "user": "…", "password": "…", "…": "…", "knownServers": [ "…" ] }
}
```

Both cookie sections are captured and refreshed the same way — `Setup-JiraAiFix.ps1 -Section helpdesk` / `-Section sharepoint`, which drives a browser and reads the cookie once the sign-in actually works. Both expire in days, and an expired one is a recorded gap, never a STOP.

Legacy fallbacks are honored when the file or a section is absent: env `ATLASSIAN_EMAIL`/`ATLASSIAN_API_TOKEN` and `~/.atlassian-token` for `atlassian` (that token file is shared with other runbooks and remains valid — the `atlassian` section can point at it via `tokenFile` instead of duplicating the secret), and the retired per-purpose files `.i21-sqlserver.json` / `.i21-helpdesk.json` for older setups.

No section is required to start a run, but each one that is **missing or empty removes a capability**: the run then proves less, falls back to an Information Request, or must disclose a skipped validation. At run start, check the file and report the gaps in the run output, so the operator knows why a run was narrower than it could have been.

| # | Section | What it enables | Behavior when missing / no info |
|---|---------|-----------------|--------------------------------|
| 1 | `atlassian` | §1 attachment evidence: downloading and reading screenshots/PDFs, **screen recordings** (decoded to frames with `ffmpeg` — a PATH tool, not a config section; see **R-VIDEO-EVIDENCE** in §1 step 5) and attached DB backups (the Atlassian MCP is 403-blocked on attachment content). Precedence: `email`+`apiToken` in the section → `tokenFile` → env vars. | Load-bearing screenshot/attachment evidence cannot be read → STOP / §1.6 Information Request instead of a root cause |
| 2 | `sqlServer` | §1.7 local restore of a DB attached/linked on the JIRA (defines **where** the AI restores it); §3.5 `liquibase update` + rollback confirmation and its logs | `DB_REQUIRED` issues cannot be reproduced/proven → Information Request asking for the DB; §3.5 skipped with the RCA disclosure `liquibase update NOT run` |
| 3 | `sqlServer.knownServers` | §1.7 step 0: when the JIRA (description/comment) says the DB was **already restored on a server** (e.g. an HDTN restore note naming a QA server + DB name), the AI matches that server by name/alias and uses the existing DB directly — no download, no re-restore | Server names mentioned in the JIRA cannot be resolved to a connection → the run falls back to downloading/restoring locally, or to an Information Request; record the unmatched server name in the run output so the operator can add it to the registry |
| 4 | `helpdesk` | §1 HDTN evidence enrichment (**supplementary — an HD ticket is never required**): reading a *referenced* helpdesk ticket — above all its **`Database Copy` tab / restore comment / restore screenshot**, which names the server + database IT restored the copy onto (→ §1.7 step 0), plus its discussion thread, screenshots/attachments, and **helpdesk-hosted images embedded in Jira descriptions** (the Jira attachment field is often empty — refs AP-24771/AP-24802). Image GETs work with the cookie directly; the ticket thread and the `Database Copy` tab need the SPA driven via Playwright with the saved cookie (§1 step 6). | Cookie missing/**expired** (HTTP 401 / login redirect) → **record the gap and CONTINUE** on the JIRA's own evidence (operator 2026-08-07); the restore location then falls through to the §1.7 registry sweep or a §1.6 DB information request. Never a STOP. Never guess or brute-force a login. |
| 4a | `helpdesk.mcp` | **§1 step 6a — reading the customer SOP a reporter cited** (`HDTN-<ticket> - SOP-<n> <symptom>`): the SOP's subject, customer, module, line of business and **version**, its ordered steps with the i21 screen each one drives, and the screenshots embedded in them. Feeds the §1.6 Step 2b repro specification (**R-REPRO-STEPS** item 0a) and the §2.4 premise ladder (**A1b**). The `apiKey` comes from `<mcp.url>/setup` after an SSO sign-in and does **not** expire on a days scale. | No key → SOP unread: **record the gap, CONTINUE**, and emit the one-line setup pointer. Key rejected → the server-side session behind it aged out; same gap, different pointer (re-paste the cookie at the setup page). Never a STOP — see §1 step 6a. |
| 5 | `appEnv` | **§1.6b `APP_REQUIRED` classification, §1.7a runtime reproduction, §1.7c app-layer deployed-fidelity check — and the §1.6c registry that remembers every environment a run has found.** One entry per environment: `baseUrl`, `kind` (`prod` / `dev`), `customer`, the login `user`/`password` (same `password`-field-wins rule as `sqlServer`), a `storageState` pointer to the saved Playwright session, and `obtainedAt` — plus the run-written liveness fields `status` / `lastCheckedAt` / `lastAliveAt` / `consecutiveFailures` / `lastError` and the last observed `lastBuildStamp`. **This is the one config node the runbook writes** (§1.6c step 3): an environment discovered on a ticket is persisted here and resolved from here on later runs, and every entry is probed alive before it is used. Auth is a **one-time headed login** — the operator completes SSO/MFA in a visible browser — whose session is saved to `storageState`; every run after replays it **headless**. Same capture-and-replay model the `helpdesk` and `sharepoint` sections already use. | No `appEnv` and no `APP_ENV` parameter → §1.7a/§1.7c are skipped and disclosed — but *missing* is a starting state, not a permanent one: the node is **created** by the first run that finds an environment on a ticket (§1.6c step 3), and an entry whose last probe failed is marked `stale`, never silently trusted or silently deleted. When §1.6b classified the run `APP_REQUIRED = YES` this is **not** a silent skip: the run continues on every reachable layer and §1.8b adjudicates — on a completed elimination ledger it posts the environment request and STOPs. Session expired (login redirect on first navigation) → re-run the headed capture; never brute-force, never hard-code credentials into a repo, a Jira comment, or this runbook. |
| 6 | `i21connect` | **§1.5a build-number → branch resolution (R-BUILD-RESOLVE)** and the `REPORTED_ENV_KIND` it derives: `baseUrl` (`https://i21connect.com`), the SSO `storageState` pointer, and — once discovered from a headed run’s network trace — the `releaseApi` endpoint the release page itself calls, so later lookups cost one request instead of a driven UI. | Unreachable or session expired → `BUILD_BRANCH UNRESOLVED`, fall back to §1.5 rules 4–5 parsing, and disclose the fallback. Never a STOP; never assert a branch from an unresolved stamp. |

Accuracy rule: a missing optional config is never guessed around — the affected capability is skipped **and disclosed** (run output + RCA/Information Request), never silently faked.

**One PATH tool, not a config section: `ffmpeg`.** It decodes a screen recording into readable frames (§1 step 5, **R-VIDEO-EVIDENCE**), `Setup-JiraAiFix.ps1 -Section ffmpeg` installs it, and unlike every row above its absence is **not** skip-and-disclose but a **STOP** — the only one in this table’s territory, and only on a ticket that actually carries a recording. The rule above cannot apply to it: "disclose the skipped capability" would mean posting an information request for evidence the reporter already attached, so there is no honest way to continue. The run stops, the operator installs, the ticket is untouched.

---

# Module resolution (runtime — no per-module configuration)

This runbook carries **no module profile**. Every module-specific fact below is **derived on each run**
from the ticket, the repository and the connected database, and the derivation is recorded in the run
output so a reviewer can check it against the same sources.

The reason is fail-closed. A hardcoded per-module table goes stale silently and then points a gate at
the wrong object — the gate still passes, against nothing. A derivation that cannot be completed is
visible, and becomes either a STOP or a stated `N/A` with its reason.

| Variable | How it is derived | Resolved by | Fail-closed rule |
|---|---|---|---|
| `JIRA_PROJECT` | the project key of `JIRA_KEY` (`AP-24899` → `AP`) | §1 | never inferred from the current branch or the repo folder |
| `MODULE` | the module the project key names, read from the Jira project's own name (`getVisibleJiraProjects` / the issue's `project` field) — never from a key→module table in this file | §1 | unresolvable → report the bare project key and continue. `MODULE` is display metadata; it is never an input to a gate |
| `OBJECT_PREFIX` | the naming prefix the objects on the implicated path **actually carry** (`uspAPPostBill` → `uspAP`, `fnICGetItemUOM` → `fnIC`) — observed on the path, never predicted from `JIRA_PROJECT` | §1 step 2 | a path whose objects carry a prefix **other than** the ticket's own project is the R-OBJECT-OWNERSHIP tripwire — take it to the §2.6 ownership gate **before** §3 edits anything; report it, never normalize it away |
| `DOC_TYPES` | the document types **this ticket** names, harvested from the description, comments and screenshots (voucher/IR, invoice/credit memo, receipt, contract, load, ticket, work order, …) | §1 | none named → the §1.6 information request asks for the specific documents. Never substitute a generic example document type |
| `MASTER_TABLE` / `DETAIL_TABLE` | for every table the CHANGESET or the data fix writes to, resolve its header/line partner **from the live schema**: `sys.foreign_keys` + `sys.foreign_key_columns` on the connected DB | §3 / §3.6 step 2 | no declared relationship → Standard 2 is `N/A` and the comment says so. **Never** inferred from a name resemblance (`tblXXHeader`/`tblXXDetail` is a convention, not a proof) |
| `ROLLUP_RULE` | the formula relating a master rollup column to its detail rows, **read out of the module's own posting / recalculation procedure** — the one the application itself calls | §3.6 step 2 | not locatable in a real procedure → **STOP**. An invented rollup formula is the R-DATAFIX equivalent of an unverified RCA |
| `GL_MODULE_NAME` | the `strModuleName` value the module's GL rows actually carry: `SELECT DISTINCT strModuleName FROM tblGLDetail WHERE strTransactionId IN (<the reported documents>)` | §3.6 step 2 | reported documents absent, or no GL rows → Standard 4 is `N/A` **with that reason stated**, never assumed balanced |
| `MODULE_PREFIX` | the 2–3 letter module code the **affected tables themselves** carry (`tblICItemStock` → `IC`, `tblARInvoice` → `AR`, `tblAPBill` → `AP`), read off the primary table the data fix keys on. Cross-check it against `JIRA_PROJECT`; **where they disagree the tables win** — the project key says where the symptom was reported, the tables say whose data is being changed (R-OBJECT-OWNERSHIP) | §3.6 step 1 | affected tables span more than one prefix → the **primary** table (the one the analysis result set keys on) decides, and the others are named in `@strRemarks`. No prefix resolvable from any affected table → **STOP** |
| `DATAFIX_LOG_TABLE` | **`tbl<MODULE_PREFIX>DataFixLog`** — the module's **own** data-fix audit trail. Discover what already exists before deciding: `SELECT name FROM sys.tables WHERE name LIKE 'tbl%DataFixLog'`. An existing table for this module is used exactly as it is; a module with none yet gets one created by the script (§3.6 step 1a) | §3.6 step 1 | the template's shipped log-table name belongs to whichever module wrote the template and is **almost never** right for this run — retarget it. A script left pointing at another module's table is a §3.6 FAIL: its idempotency guard is inert, so the fix can be applied twice with no complaint |
| `CONSUMING_MODULES` | the modules that read the affected tables/columns — taken from §3.7 tier 1 (`sys.sql_expression_dependencies` plus the repo-wide reference search), never from an enumerated list | §3.6 step 5 | tier 1 not runnable → the impact analysis states the coverage limit explicitly |

**No table, column, procedure, GL module string, document type or repository name for any module is
hardcoded anywhere in this runbook.** Two consequences worth stating plainly:

- A gate that depends on an unresolved derivation is **skipped and disclosed**, exactly as §3.5 and
  §3.11 disclose a not-run check. It is never quietly passed on an assumption.
- The AP objects in this file (`tblAPBill`, `uspAPPostBill`, `tblAPDataFixLog`, `strModuleName = 'Accounts Payable'`, and
  the `AP-#####` ticket citations) are **worked examples**. They show a gate operating on real
  evidence. Reading one as a default for your module is the specific mistake this section exists to
  prevent.

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

REPO = <optional repository to analyze/modify> (repo name / PRODUCT — any i21 module repo, or the cross-module `Liquibase` / `SqlScripts`; e.g. `AP` / `Accounts Payable`, `AR`, `GL` — or a full local path such as `C:\i21Source\AP`)

Validation:
- REPO_ROOT is OPTIONAL; when not provided it defaults to `C:\i21Source`. It is the **container** of the i21 repo clones (~45 sibling repos) and is **NOT itself a git repository** — never run git commands against `<REPO_ROOT>` directly.
- REPO is OPTIONAL. When provided (repo name or full path) it wins and is used directly.
- **IF REPO is not provided -> AUTO-RESOLVE the affected repository from the Jira** (do NOT ask the user first, and do NOT silently assume the current working directory or the opened workspace):
  1. Read the Jira (§1 issue read) and extract the module/artifact evidence: `JIRA_PROJECT` & `MODULE` (resolved per **Module resolution** — an `AP-*` key points at Accounts Payable, an `AR-*` key at Accounts Receivable, and so on; read from the Jira project itself, never from a table in this file), screens, ExtJS classes/xtypes, C# types, SQL objects, and any file paths named in the description, comments, or attachments.
  2. Map that evidence to candidate repositories under `<REPO_ROOT>` (the PRODUCT table in **Repository scope** gives the *shape* of the mapping, not a closed list — ANY i21 repo under `<REPO_ROOT>` is a valid candidate when the evidence points there, e.g. a framework/EntityManagement widget consumed by the reporting module's screen).
  3. Confirm by code search: the candidate whose tree actually contains the affected artifact(s) (`git -C <candidate> grep -il "<artifact>" origin/<Jira-derived branch>`) is REPO_PATH. If parts of the fix genuinely span repos, the PRIMARY repo is the one owning the defective artifact; record the others in the §1 analysis.
  4. ONLY IF the repository is still ambiguous after the code search (no candidate contains the artifact, or several contain same-named but different objects) -> ASK THE USER and WAIT.
- REPO_PATH = `<REPO_ROOT>\<repo folder>` resolved from REPO (when provided) or from the auto-resolution above, via the PRODUCT table in **Repository scope** (e.g. `C:\i21Source\AP`). If a full path to one repository is given, use that path as REPO_PATH directly (and its parent folder as REPO_ROOT).
- REPO_PATH MUST be the path of **one repository**, not the `<REPO_ROOT>` container — the container fails the `rev-parse --is-inside-work-tree` check in **Repository scope**.
- Resolution, loading, and cloning of REPO_PATH are defined in **Repository scope** below. All git commands in this runbook run against `<REPO_PATH>` (`git -C <REPO_PATH> …`).

APP_ENV = <optional URL of a running i21 application environment for this JIRA (e.g. `https://…/2710DEV`)>

Validation:
- APP_ENV is OPTIONAL and is **never provisioned by this runbook** (no app environment is built, deployed, or configured here). It serves two purposes, both needing a *running* app and neither substitutable by SQL: the **§1.7a runtime reproduction** (R-RUNTIME-REPRO) of symptoms raised in the client — screen behavior, ExtJS field state, document/PDF rendering, HTTP payloads — and the **§1.7c app-layer deployed-fidelity check** (R-APP-DEPLOY-DIFF), the only instrument that can say what app-layer code the environment is actually executing. §1.7b answers that for database objects; **a database cannot report the application build**.
- **Whether this JIRA needs it is a classification, not a guess** — §1.6b (R-APP-REQUIRED) decides, and it runs on every issue.
- **Where APP_ENV comes from — parameter, ticket, or registry (§1.6c).** Not passing the parameter does not mean there is no environment. §1.6c resolves it from three sources in order — the explicit parameter, a URL **found on this ticket** (description, a comment, the address bar visible in an attached screenshot, the linked HDTN, an `Apply patch <JIRA> to <env>` ticket), then the **`appEnv` registry** in `JIRA_AI_CONFIG` matched by recorded identity — **probes** whichever resolved to confirm the app is still alive, and **writes what it learned back** so the next ticket on this customer opens with the environment already in hand. Every *no `APP_ENV`* below therefore means *none of the three sources produced a live environment*, never *the operator did not pass one*.
- When APP_ENV is NOT provided and §1.6b did **not** classify the run `APP_REQUIRED`: skip §1.7a/§1.7c entirely, never STOP for them, and — when the EVIDENCE_SET is UI-level — record `runtime reproduction NOT run — no APP_ENV provided` in the run output and disclose it in the §6 RCA (same disclosure discipline as a skipped `liquibase update`).
- When APP_ENV is NOT provided and §1.6b classified the run `APP_REQUIRED = YES`: **the run does not stop there.** It continues through §1.7 / §1.7b / §1.8, exercising every layer that *is* reachable, and the question is adjudicated at **§1.8b**. A STOP becomes available only on `APP_REQUIRED-PROVEN` — a completed elimination ledger showing what was executed on each reachable layer and that none of them raised the symptom. That narrow case supersedes the blanket "never a STOP" of operator 2026-08-07; every other shape stays a disclosure (operator 2026-08-24: absence of an app environment is not a stop until we have tested and verified that the app is required, and the comment must say what was tested and why).
- **`APP_ENV_PROD` / `APP_ENV_DEV` (operator 2026-08-24).** `APP_ENV` names either kind; supply both where both exist. **The reported environment is where the symptom is real and is analysed — read-only. Dev is where the fix is exercised.** With both in hand §1.7c step 5 runs the three-way comparison, whose main payoff is catching the case where **dev already carries the fix and the reported environment has not received it** — a deployment gap, not a defect, and one no amount of branch reading will reveal. Which kind the *report* came from is resolved from the build stamp by §1.5a (`REPORTED_ENV_KIND`), never from the ticket’s prose — a JIRA is often reported on a Dev build.
- **Credentials and session.** Provided by the `appEnv` config section (or by the operator inline). Login runs **once, headed**, so the operator can complete SSO/MFA by hand; the resulting Playwright `storageState` is saved outside every repository (user profile, same rule as `sqlServer.password`) and **every reproduction and test thereafter runs headless** against that saved session. A login redirect on first navigation means the session expired → re-run the headed capture. Never brute-force, never guess, never commit a session file or a password.
- **Headless is the default; headed is the fallback for render-class symptoms.** Layout, font metrics, print CSS and PDF generation can differ between headless and headed Chromium, so a defect *about how something looks* is re-checked headed before it is graded. Always pin an explicit viewport (1920x1080, deviceScaleFactor 1) so screenshots across runs are comparable, and wait on ExtJS component readiness rather than on fixed sleeps.
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

**Canonical selection JQL** (substitute the module's own `JIRA_PROJECT`, and its own type names — the `issuetype` list below is the reference scheme, see **Issue type gate**):

```
project = <JIRA_PROJECT>
AND issuetype in ("Bug", "Bug-QC", "Bug-UAP", "Bug-Ongoing UAP", "Technical Debt", "Performance", "Data Fix")
AND status in (Open, Reopened)
AND (labels IS EMPTY OR labels NOT IN ("JIRA-AI-NeedInfo", "JIRA-AI-CannotFix", "JIRA-AI-Triaged", "JIRA-AI-Fixed", "JIRA-AI-DataFix", "JIRA-AI-OwnerReview", "JIRA-AI-PremiseChallenged"))
ORDER BY priority DESC, updated ASC
```

- **`labels IS EMPTY OR …` is mandatory, not defensive.** Jira's `NOT IN` does not match issues whose field is empty, so `labels NOT IN (…)` alone silently drops every unlabeled ticket — i.e. exactly the never-processed ones the pass exists to find.
- **Filter on labels, never on status.** Every not-fixed outcome deliberately leaves the status untouched (§6.6: an information request keeps the ticket `Open` because the reporter owns it), so status alone cannot dedupe. The type and status gates still apply to whatever this JQL returns — the filter narrows the candidate set, it never replaces a gate.
- **Which labels gate selection:** the seven terminal outcome labels above, and only those. `JIRA-AI-Fixed` / `JIRA-AI-DataFix` are terminal for this runbook — the fix exists and the next move belongs to `JIRA-PR-Automation.md` or a human. `JIRA-AI-OwnerReview` (§2.6) is terminal the same way: the fix exists as a proven patch, and the next move is the owning module's. `JIRA-AI-NeedInfo` / `JIRA-AI-CannotFix` / `JIRA-AI-Triaged` mean the run's conclusion stands until the blocking gap changes. `JIRA-AI-PremiseChallenged` (§2.4) is terminal in the same way and for a different reason: nothing is blocked and nothing is missing — the run is waiting on a **decision** about whether the reported behaviour should change at all, and re-running before that decision arrives would re-derive the same challenge from the same evidence.
- **Never filter on `JIRA-AI-RegressionFlag` or `JIRA-AI-FixPropagated`.** The first is an attribute of a delivered fix, the second belongs to the propagation runbook — neither says anything about whether *this* runbook has processed the ticket. Excluding them wrongly drops live work (ref AP-24523: `Reopened` on 2026-08-11 while carrying `JIRA-AI-FixPropagated` from an earlier propagation run — a genuine re-analysis candidate).
- **Legacy per-project labels are excluded too, and never rewritten.** A deployment migrating from a project-scoped runbook carries both namespaces for a while (`AP-AI-Fixed` alongside `JIRA-AI-Fixed`). While any legacy label exists in the project, the selector's `labels NOT IN (…)` list must name **both** sets — otherwise every ticket a previous project-scoped run terminated comes straight back into the queue. New labels are always written in the `JIRA-AI-*` namespace; historical labels are left exactly as they are (rewriting them destroys the only record of which runbook version reached that conclusion).
- **Re-entry is evidence-driven, not time-driven.** A labeled ticket comes back into scope when the gap that stopped the run is addressed: a human clears the label, or the ticket gains a comment/attachment **newer than** the runbook's own terminal comment. Re-picking such a ticket is correct and the §1.6 **dedupe guard** — not this filter — decides whether a second comment is warranted. Never re-post an identical request against unchanged evidence; never age a label out on a schedule.
- **A corrected description produces neither a comment nor an attachment (operator 2026-09-04).** That is the hole in the bullet above, and it is the single most consequential kind of drift: someone fixes a wrong description or revises the acceptance criteria **in place**, the ticket keeps its terminal label, and the corrected requirement is never seen by any later pass. So the selector also re-admits a labeled ticket whose **`updated` is later than this runbook's own terminal comment** — `AND (labels IS EMPTY OR labels NOT IN (…) OR updated > <the terminal comment's date>)` where the JQL form allows it, otherwise as a second pass over `labels IN (<the terminal set>) AND updated > -30d` whose members are handed to §1.6 Step 0.0 individually. This re-admits noise too, since a label edit or a priority bump also moves `updated`; that is intended and costs nothing, because **Step 0.0 rules on materiality and stops without posting when the delta changes no result.** A cheap wasted read is the correct trade against a corrected requirement that is never acted on.
- **Capability changes are invisible to any JQL.** A database becoming reachable, an app environment coming back, or a missing config section being filled leaves no trace on the ticket at all, so no selector can find those. They are why an operator naming a `JIRA_KEY` explicitly always wins, and why Step 0.0 compares capability rather than only ticket state.
- **An explicitly provided `JIRA_KEY` always wins.** This filter governs *automatic* selection only. An operator naming a ticket runs it regardless of its labels.
- **Cohort expansion (batch passes).** When the pass is cohort-based, expand the selected JIRA into its customer/environment cohort (§1 step 7a) and process the cohort in one run — one restore serves all of it, and **R-DB-SLOT-LIMIT** caps concurrent DB cohorts at two. Apply the label filter to each member individually; an already-terminated sibling stays out.
- **Unattended runs must always leave a label.** A scheduled run cannot ask the operator anything, so every STOP that would normally await an answer — the §1.5 case-twin guard, the artifact-present-only-on-a-forbidden-Prod-branch conflict, an ambiguous repo resolution — terminates through the **§6.5 D TRIAGE comment + `JIRA-AI-Triaged`** (R-NOFIX-COMMENT), naming the decision the operator owes. Otherwise the next scheduled pass re-derives the same stall from scratch, indefinitely. **The §2.4 premise challenge is the one STOP that does not route through D**: it awaits a *business* decision rather than an operator one, and it carries its own comment (§6.5 E) and its own label (`JIRA-AI-PremiseChallenged`), so the rule this bullet exists to enforce — never stop without leaving a label — is satisfied by its own route.
- **Reporting benefit:** because every outcome lands a label, a batch pass's statistics are a set of JQL counts (`labels = "JIRA-AI-Fixed"`, `= "JIRA-AI-NeedInfo"`, …) rather than a hand-maintained tally — countable by anyone, at any time, without a tracking file.

# Issue type gate (mandatory)

Before doing any work, read `<JIRA_KEY>` from Jira and cache:

PARENT_ISSUE_TYPE = <the issue type that gates the run: the issue's **own** type. Only when `<JIRA_KEY>` is a **sub-task** does the gate read its parent instead — the sub-task inherits the parent work item's classification. The Epic/Story/Initiative *above* a standard issue is never read and never gated on (an Epic parent does not make a Bug-QC out of scope).>

**The gate is by CATEGORY, resolved against the project's own issue-type scheme.** i21 projects do not
share one set of type names, so the names below are the **reference scheme** (the AP project's), not a
closed list. Read the project's actual types with `getJiraProjectIssueTypesMetadata` on `JIRA_PROJECT`
and map each one to a category:

| Category | What belongs in it | Reference-scheme names |
|---|---|---|
| BUG | a reported defect in delivered behaviour | `Bug`, `Bug-QC`, `Bug-UAP`, `Bug-Ongoing UAP` |
| TECHNICAL_DEBT | internal improvement or optimization, no contracted behaviour change | `Technical Debt`, `Performance` |
| DATA_FIX | wrong data to correct, no code change required | `Data Fix` |
| OUT OF SCOPE | new functionality, or billable configuration | `Feature`, `Gap`, `Paid`, `Suggestion`, `Config` |

- **Match by type id where you have it, name only as a fallback.** Issue-type ids are stable across
  projects in one Jira instance while display names are not (`Data Fix` = id `10038`), so an id match is
  the more reliable half of this gate.
- A type the project clearly uses as a defect type but which is absent from the reference scheme
  (`Defect`, `Bug-Prod`, …) maps to BUG. **Record the mapping in the run output** so a reviewer can check
  the judgement rather than having to reconstruct it.
- **Genuinely ambiguous category → STOP**, silently, exactly as an out-of-scope type does. Guessing a
  `Feature`-shaped type into BUG is precisely how this runbook would end up implementing new
  functionality, which it must never do.
- The exclusions are exclusions **by category, not by name**: a type meaning "new functionality" or
  "billable configuration" is out of scope whatever the project calls it.

Allowed bug issue types (reference scheme):
- `Bug`
- `Bug-QC`
- `Bug-UAP`
- `Bug-Ongoing UAP`

Allowed technical debt / performance issue types (reference scheme):
- `Technical Debt`
- `Performance`   (performance optimization — ISSUE_CATEGORY = TECHNICAL_DEBT)

Allowed data-fix issue type (reference scheme):
- `Data Fix`   (Jira issue type id `10038` — "issues that require only a datafix and not a bug fix; the data issue can be the result of old bugs that were already resolved" — ISSUE_CATEGORY = DATA_FIX)

**Explicitly OUT OF SCOPE — never run (operator 2026-08-11):**
- **New-feature issue types: `Feature`, `Gap`, `Paid`, `Suggestion`.** This runbook no longer has a `FEATURE` category. New-feature work does not enter this flow at all — not analysis, not a branch, not a comment.
- **`Config` (billable bugs).** Removed from the allowed bug types; a `Config` issue is treated exactly like any other out-of-scope type.

All five of these types are a **silent STOP**, identical to any other out-of-scope type: no analysis, no repo load, no branch, no label, and **no Jira comment**. Report the skip as `OUT-OF-TYPE (<issue type>)` in the run output; in a batch, continue to the next JIRA.

IF PARENT_ISSUE_TYPE maps to no category above, or its category is ambiguous:
    STOP execution — this runbook applies only to the defect, technical-debt/performance, and data-fix
    categories. (Do NOT post any comment for an out-of-scope issue type.)

IF the resolved category is TECHNICAL_DEBT (reference scheme: `Technical Debt`, `Performance`):
    ISSUE_CATEGORY = TECHNICAL_DEBT
ELSE IF the resolved category is DATA_FIX (reference scheme: `Data Fix`, id `10038`):
    ISSUE_CATEGORY = DATA_FIX
ELSE:
    ISSUE_CATEGORY = BUG

**R-DATAFIX-DB — a data fix ALWAYS requires the database (no exception).** When `ISSUE_CATEGORY = DATA_FIX`, the §1.6 feasibility classification can never be `STATIC`: a data fix corrects rows that exist only in the customer's database, so the affected row set cannot be identified, counted, or verified without it. §1.6 resolves to `DB_REQUIRED-ACTIONABLE` (DB reachable → §1.7 immediately) or `DB_REQUIRED-BLOCKED` (→ ONE information request for the backup, then STOP). Never author, deliver, or "reason out" a data fix against code alone.

# Issue status gate (mandatory)

ISSUE_STATUS = <the issue's current status, from the §1 issue read>

Allowed statuses:
- `Open`
- `Reopened`

**Match these by meaning against the project's own workflow, not by string.** `Open` and `Reopened` mean
"nobody has started, or it has come back to the start" — a project whose workflow names that state
differently (`New`, `To Do`, `Reopen`) satisfies the gate. Resolve the project's statuses from the issue's
own workflow rather than assuming the reference names exist; a status name absent from the project is a
naming difference, never evidence that the gate passed.

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
     with the non-interactive guards of **R-CLONE-NONINTERACTIVE** set first — `$env:GIT_TERMINAL_PROMPT = '0'`, so a credential that cannot be found becomes an immediate failure, and `$env:GCM_INTERACTIVE = 'never'`, so Git Credential Manager raises no window either. **Leave the machine's credential helper alone** — never add `-c credential.helper=` here. Measured 2026-09-10 on both halves: with the guards set and the helper intact, a fetch against `irely.visualstudio.com` succeeded unattended, while the identical command with the helper stripped failed instantly on `could not read Username for 'https://irely.visualstudio.com': terminal prompts disabled`. The cached ADO credential is precisely what lets this clone run unattended, so dropping it converts a working clone into a guaranteed failure on every developer machine. The two guards are sufficient because they change only what happens when there is **no** credential to find: unguarded, a machine with no `gh` and no helper does not fail, it waits on a prompt nobody can answer — measured at **5 h 24 m** on a task still reporting *running* after printing `fatal: Unable to read prompt input from standard input [0xe9]`. A STOP that never arrives is worse than one that does. Add `-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30` so a remote that accepts the connection and then goes silent aborts rather than hangs, and **delete any partial directory a failed clone left behind** before reporting the failure — step 1 above reads a path that merely exists as *already cloned*.
     Use the Azure DevOps MCP / `az`-authenticated git (no PAT). Resolve `<ADO_REPO>` from the repo the user named, via the PRODUCT table below. (Create `<REPO_ROOT>` first if the container folder itself does not exist yet.)
   - If the clone fails (auth, network, unknown repo) -> STOP execution.
3. When `TARGET_BRANCH` was provided: `git -C <REPO_PATH> checkout <TARGET_BRANCH>` then `git -C <REPO_PATH> pull --ff-only origin <TARGET_BRANCH>`, so §1/§3 analyze the correct branch. (When TARGET_BRANCH was not provided, the current branch is used — see Feature-branch detection.)
4. Confirm it is a git repository: `git -C <REPO_PATH> rev-parse --is-inside-work-tree` returns `true`. If not -> STOP execution.
5. Resolve `ADO_REPO` from the origin remote: `git -C <REPO_PATH> remote get-url origin` -> the name after `/_git/`. Cache `ADO_REPO`.
6. Resolve `PRODUCT` for display from the remote substring:

| PRODUCT | ADO_REPO | REPO_PATH (under REPO_ROOT) | Typical remote substring |
|---------|----------|------------------------------|---------------------------|
| *the module repo §1 resolved* | the repo name **as it exists in ADO** — confirm with `repo_get_repo_by_name_or_id` before cloning; never construct it from the project key | the folder name **already in use** under `<REPO_ROOT>` for that repo (list `<REPO_ROOT>` — do not invent a second folder for a repo that is already cloned) | the module token in the `origin` URL after `/_git/` |
| Liquibase | i21_Liquibase | `<REPO_ROOT>\Liquibase` (e.g. `C:\i21Source\Liquibase`) | Liquibase |
| SQLScript | i21_sqlscripts | `<REPO_ROOT>\SqlScripts` (e.g. `C:\i21Source\SqlScripts`) | SQLScript, SqlScripts, or i21_sqlscripts |
| Accounts Payable *(worked example of row 1)* | i21_accountspayable | `<REPO_ROOT>\AP` (e.g. `C:\i21Source\AP`) | AP or i21_accountspayable |

`Liquibase` and `SQLScript` are **cross-module**: they appear for every module, because schema and SQL
changes for any module land there. Row 1 is whichever module repository §1 resolved from the evidence —
resolve it, do not pattern-match it. A repo name guessed as `i21_<projectkey>` and not confirmed against
ADO is a clone failure waiting to happen, and → STOP per step 2.

# Derived variables (must be resolved before execution)

JIRA = JIRA_KEY
PARENT_ISSUE_TYPE = <resolved from parent JIRA>
ISSUE_CATEGORY = BUG | TECHNICAL_DEBT | DATA_FIX   # from issue type gate (there is no FEATURE category — new-feature types are out of scope)
ISSUE_STATUS = <the issue's current status — must be `Open` or `Reopened`, see Issue status gate>
REPO_ROOT = <input parameter — the main folder where all i21 repositories reside; default C:\i21Source>
REPO_PATH = <`<REPO_ROOT>\<repo folder>` (e.g. C:\i21Source\AP), resolved from the REPO parameter; if the repository was not provided, ASK THE USER — then loaded/cloned per Repository scope>
ADO_REPO = <resolved from origin remote `/_git/<name>`>
JIRA_PROJECT = <the project key of JIRA_KEY — see Module resolution>
MODULE = <the module JIRA_PROJECT names, read from the Jira project itself — display metadata, never a gate input; see Module resolution>
OBJECT_PREFIX = <the object-naming prefix actually observed on the implicated path, e.g. `uspAP`, `fnIC` — see Module resolution>
DOC_TYPES = <the document types THIS ticket names — see Module resolution>
PRODUCT = <the resolved module repo's display name, or Liquibase | SQLScript, for display>
TARGET_BRANCH = <override parameter, else current branch — auto-aligned to the Jira-derived EXPECTED_BRANCH by §1.5>
FEATURE_BRANCH = `<TARGET_BRANCH>_<JIRA>`   # branch carrying the acceptance-criteria implementation
JIRA_FIX_VERSION = <fixVersions from the JIRA, e.g. 26.3 — see §1.5>
JIRA_BUILD = <reported version/build from the JIRA, e.g. 26.3ProdSucafina.0724.235 — see §1.5>
JIRA_CUSTOMER = <customer from the JIRA, e.g. Sucafina — see §1.5>
ACCEPTANCE_CRITERIA = <extracted from the Jira — see §2>
FEASIBILITY = STATIC | DB_REQUIRED-ACTIONABLE | DB_REQUIRED-BLOCKED | INFO_REQUIRED | CANNOT-FIX   # resolution-feasibility class — see §1.6
RERUN = FIRST-RUN | NO-DELTA (<prior verdict + date>) | DELTA (<class(es)>) | DELTA-UNKNOWN (<prior comment has no basis footer>)   # §1.6 Step 0.0 (R-RERUN-DELTA). NO-DELTA is a STOP that posts nothing
RERUN_DELTA = <class(es) SETUP | DATABASE | APP-ENV | TICKET (CORRECTION|EXTENSION) | EVIDENCE> · material: <what it unlocks, tied to the prior run's own verdict> | immaterial: <what changed and why it cannot change the result>   # carried into the §6 Supersedes block
RUN_BASIS = <the two-half footer this run will stamp: ticket state (updated instant, fixVersion, env, build, customer, attachments, last comment read, description chars) + capability (config sections resolved, DB server/dbname or not reachable, app env or not reachable)>   # §6 footer (R-RUN-BASIS) — what the NEXT run compares against
SYMPTOM_QUOTE = QUOTED (<the verbatim observable> — from <the artifact this run fetched and read>) | CLASS-ONLY   # §1.6 Step 1a (R-SYMPTOM-QUOTE). CLASS-ONLY BARS the §6 RCA
VIDEO_EVIDENCE = <one row per screen recording on the ticket: `<id/file> · <duration> → <n> frames read · yielded: <error text | steps | document numbers | values>`> | DECODE-FAILED (<ffmpeg present, the file would not decode — continue and disclose>) | STOPPED-NO-DECODER (<n> recordings, ffmpeg not on PATH — operator install required; NOTHING posted to the Jira) | none supplied   # §1 step 5 (R-VIDEO-EVIDENCE). Decoded frames are QUOTED-grade evidence; an undecoded recording is a defect in the run, never a gap on the ticket
FALSIFIER = <what the selected candidate predicts the ticket's evidence must show> · checked against: <artifacts> · consistent | CONTRADICTED by <artifact>: <what it shows>   # §1.6 Step 2d (R-FALSIFIER) — CONTRADICTED is a STOP on that candidate
REPRO = <the §1.8 verdict — DERIVED from the §1.8 step 6 evidence ledger, never chosen; see R-REPRO-DERIVED>
REQUEST_LEDGER = <one row per item of the previous information request: ARRIVED (<where>) | STILL-MISSING> | none — no prior request   # §1.6 (R-REQUEST-RECONCILE)
RUNBOOK_VERSION = <from the `> **Version.**` header under this file's title — the authority; else the `version` in `MANIFEST.json` at the ROOT of the installed skill folder> | working copy — unreleased | unknown   # stamped on every comment by §6.8 (R-RUNBOOK-STAMP); header and manifest disagreeing means the file was replaced by hand, and that is reported
RUNBOOK_CURRENCY = CURRENT | STALE <local> -> <remote> | AHEAD <local> > <remote> | N/A (working copy) | UNRESOLVED (<reason>)   # §6.8 rule 10 (R-RUNBOOK-CURRENCY) — this file's own header vs the maintainer repo's default branch, resolved at run start. NEVER a STOP, and a missing MANIFEST.json is not an input to it
JIRA_AI_CONFIG = <the consolidated runbook configuration file, `%USERPROFILE%\.jira-ai-runbook-config.json` — sections `atlassian` / `helpdesk` / `sqlServer`; see Optional configurations. Lives in the user profile, NEVER inside a repo.>
SQLSERVER_CONFIG = <the `sqlServer` section of JIRA_AI_CONFIG — see §1.7>
RESTORE_DB_NAME = <name of the locally restored copy of the reported database, from the §1.7 naming pattern, e.g. `i21_AP-24754_ECOM`>
RESTORE_SLOTS = <the local restore pool: at most **2** databases matching `dbNamePattern` may exist on the local instance at once; a third DB_REQUIRED cohort is parked as `DB_QUEUED` until a slot is released (**drop the DATABASE only — the compressed backup archive is kept**, see **R-DB-KEEP-ARCHIVE**) — see **R-DB-SLOT-LIMIT** in §1.7>
DB_BUILD_VERSION = <the `strVersionNo` of the newest row in the restored/connected DB's `tblSMBuildNumber` — see §1.7 step 2.6>
DB_PROVENANCE = <where the database actually came from, resolved in §1.7 step 0/1 and carried verbatim into the terminal comment: `shared <server>/<dbname>`, or `local restore of <acquisition source — which HDTN's Database Copy / attachment / link / knownServers sweep>`; plus which HDTN supplied it when the ticket lists more than one, or `not traceable to a listed HDTN` — see **R-DB-PROVENANCE** in §1.7>
DB_CANDIDATES = <every step-0 candidate, gated and ranked, NOT just the winner: `<db> @ <date> (<source>) — primary | retained: <why not primary>`. Retained copies are the dated snapshot series §1.8 / §3.8 / §3.11 consult for absence, origin-bounding and hand-corrected rows — see **R-DB-CANDIDATE-SET** in §1.7>
APP_ENV = <optional input parameter — URL of a running i21 app environment, used ONLY by §1.7a runtime reproduction; never provisioned by this runbook>
APP_ENV_VERSION = <the i21 version reported by APP_ENV, resolved in §1.7a>
IS_DATAFIX_CASE = true WHEN ISSUE_CATEGORY = DATA_FIX   # routes to §3.6 instead of a code change
ORIGIN_TRACE = <the write chain for a value defect and the first carry gap in it: `<w0…wn> | root cause = <wi> | other callers of w0 = <list|none>` — see §3.4 Proof 1>
REACHABILITY = <per changed statement: `<file>:<line> = ON-PATH | OFF-PATH (<failing guard>) | UNDETERMINED (<predicate>)` — see §3.4 Proof 2>
FALL_THROUGH = <`none`, or `<variable> @ <file>:<line> — reachable when <condition> — first misbehaviour: <statement>` — see §3.4 Proof 3>
SIBLING_LINES = <the active branches (with repo) that also carry a changed logic object, from the fresh ls-remote scan across BOTH repos — see §2.5 step 1>
ALIGN_VERDICT = <per changed logic object: PORT-AVAILABLE | NO-SIBLING-BEHAVIOUR | NOVEL-JUSTIFIED | N/A (single-line object) | NOT-RUN (<reason>) — recorded BEFORE §3 authors anything; see §2.5 (R-ALIGN-TO-SIBLING)>
PORT_SOURCE = <`<repo>/<branch>` the ported body was taken from, or `none` — the branch the RCA must name when ALIGN_VERDICT = PORT-AVAILABLE; see §2.5 step 3>
PORT_EXCLUSIONS = <per deliberately stripped portion of a ported hunk: `<portion / referenced JIRA> — excluded: <missing prerequisite> not on <TARGET_BRANCH>`, or `none — body taken whole` — see §2.5 step 4 (R-PORT-DEPS)>
CHANGED_OBJECTS = <every SQL logic object (SP/view/function/trigger) or code artifact whose definition the CHANGESET alters — see §3.7>
DEPENDENTS = <everything that consumes a CHANGED_OBJECT: repo-wide references + `sys.sql_expression_dependencies` when a DB is available — see §3.7 tier 1>
GOLDEN_SET = <the reported document(s) PLUS N sampled rows that exercise the same code path and are NOT the reported defect — see §3.7 tier 2>
REGRESSION_VERDICT = CLEAN | UNEXPECTED-DELTAS | CONTRACT-FAIL | NOT-RUN   # §3.7
DEFECT_ORIGIN = <the change that introduced the defect: `<JIRA key> | <summary> | <commit> | <date> | <author>`, or `not determinable` — see §3.8>
FIX_COVERAGE = <per active version line: DEFECT | PARTIAL | FIXED | N/A — established by CONTENT and proven with a counterexample; see §3.8>
COVERAGE_GAPS = <lines still DEFECT/PARTIAL that this run does not fix — reported, never acted on (§3.8 step 6)>
PROPERTY_TEST = <§3.9 result: inputs/evaluations, failures OLD→NEW, subset check, fixed, changed, unwanted drift, accuracy regressions, residual classes — or NOT-RUN with the reason>
CANDIDATE_CHANGESET = <every artifact the fix is ABOUT to touch (repo file or DB object), from the §1 step 4 analysis + the §2.5 alignment — the input to the §2.6 ownership gate, resolved BEFORE §3 edits anything>
OBJECT_OWNER = <the module/project that OWNS each candidate artifact, decided from file location + caller distribution + the project keys on every prior commit — NOT from the JIRA's own project key; see §2.6 (R-OBJECT-OWNERSHIP), confirmed at §3.8 step 5>
OWNERSHIP_ROUTE = OWNED | FOREIGN-SHARED | FOREIGN-EXTERNAL | UNDETERMINED   # per artifact, §2.6. FOREIGN-SHARED = fixed and pushed as normal, but the owning project's reviewer is REQUIRED before any PR. FOREIGN-EXTERNAL/UNDETERMINED = a FULL HOLD: the object is not edited in REPO_PATH, no fix is authored at all, the diagnosis is the deliverable, §4/§5 are skipped, and the JIRA is never re-homed (R-NO-REHOME)
DATAFIX_FILE = `<JIRA>DataFix.sql`   # the delivered data-fix artifact — see §3.6
MODULE_PREFIX = <the 2–3 letter module code the AFFECTED TABLES carry (`tblICItemStock` → `IC`), from the primary table the fix keys on — the tables win over JIRA_PROJECT on disagreement; see Module resolution>
DATAFIX_LOG_TABLE = <`tbl<MODULE_PREFIX>DataFixLog` — the module's OWN data-fix audit trail; an existing one is used as-is, an absent one is created by the script — see Module resolution and §3.6 step 1a>
MASTER_TABLE / DETAIL_TABLE = <the header/line pair for each table the fix writes to, resolved from `sys.foreign_keys` on the connected DB — see Module resolution>
ROLLUP_RULE = <the master-to-detail total formula, read out of the module's own posting/recalculation procedure — see Module resolution>
GL_MODULE_NAME = <the `strModuleName` value the module's own GL rows carry, read from `tblGLDetail` for the reported documents — see Module resolution>
CONSUMING_MODULES = <the modules that read the affected tables/columns, from §3.7 tier 1 — see Module resolution>
CHANGESET = <the files changed while applying the acceptance criteria — see §3>
IS_LIQUIBASE_STANDARD_CASE = true WHEN any file in CHANGESET is a SQL-script file (i21_Liquibase `.sql`/`.xml`, or i21_sqlscripts/SqlScripts `.sql`)
TARGET_VERSION = <the numeric version prefix of TARGET_BRANCH, e.g. `22.1` from `22.1ProdWaMa`, `26.3` from `26.3Prod`>
IS_PRE_LIQUIBASE_BRANCH = true WHEN TARGET_VERSION < 24.1   # Liquibase exists only for i21 versions >= 24.1 — see R-LB-24.1-TARGET
RUN_SESSION_ID = <the harness session id of THIS run, read from the `CLAUDE_CODE_SESSION_ID` environment variable — identifies the run's own transcript for the §6.8 telemetry footer. Unset/empty is never a STOP: §6.8 reports the measurement as unavailable.>
RUN_START_UTC = <UTC instant stamped ONCE, before the first §1 Jira read, format `yyyy-MM-ddTHH:mm:ss.fffZ` — the zero point for the §6.8 elapsed-time and token counts. Never re-stamped, including after a context compaction.>

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
- **Data Fix Standards (All Modules)** — the module-neutral baseline every data fix must meet: Standards 1–4, the fail-checks `S5`–`S17`, the dry-run-and-roll-back proof, and the Senior BA review gate (mandatory whenever a data fix is authored, on ANY issue type):
  https://irely.atlassian.net/wiki/spaces/AP/pages/705168896/Data+Fix+Standards+All+Modules
- **JIRA Datafix Template** (the base script EVERY data fix must derive from):
  https://irely.atlassian.net/wiki/spaces/AP/pages/434602044/JIRA+Datafix+Template
- **The module's own data-fix addendum**, where one is published — a child of the standards page, titled `<Module> Data Fix Addendum`, binding the baseline's placeholders to that module's real objects (log table, master/detail pairs, rollup formulas, settlement relation, GL module string, posted flag, business keys) and adding its own standards, numbered in the module's namespace (`AP-1`, `IC-1`, …). Accounts Payable's addendum is the **Data Fix Guidelines** page:
  https://irely.atlassian.net/wiki/spaces/AP/pages/503382346/Data+Fix+Guidelines

**Space note.** These pages live in the `AP` Confluence space for historical reasons; the standards page
is **org-wide** and applies to every module. Three rules follow:
- **The baseline is the floor.** A module addendum may tighten a standard or add its own; it may not
  weaken or remove one. Where an addendum and the standards page conflict, the standards page wins.
- **Read the addendum for the module whose TABLES the fix writes to**, not the module whose project key
  raised the ticket — those differ, and `MODULE_PREFIX` (**Module resolution**) is what decides. Record
  in the run output which pages were actually read, and say so explicitly when the module has none.
- **An addendum is a starting point, never the authority.** A published table name since renamed, or a
  rollup formula the posting procedure no longer uses, passes a review by eye and proves nothing on
  execution. Every derivation in **Module resolution** still runs against the connected database on the
  ticket in hand.

`§3.6` is this runbook's **executable restatement** of that standards page — the same Standards 1–4, the
same fail-checks `S5`–`S17`, the same dry-run proof, expressed as gates a run can fail and evidence a
reviewer can check. The numbering is shared deliberately, so a `S16 FAIL` on a Jira means the same thing
to the Senior BA reading the iNet page as it does to the run that raised it. Where the two ever diverge,
the iNet page is the source of record and `§3.6` is the defect.

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
- **Stamp the run clock BEFORE the first Jira read (R-RUN-TELEMETRY, §6.8):** resolve `RUN_START_UTC` (`(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')`) and `RUN_SESSION_ID` (`$env:CLAUDE_CODE_SESSION_ID`), and carry both to §6.8 unchanged. Stamped after the analysis has begun, the measurement understates the run; a failure to resolve either value is recorded and the run continues.

1. Read the issue with `getJiraIssue` for `<JIRA>`. Cache: summary/title, issue type, priority, status, description, customer, **fix version**, **reported version/build**, and all comments. (The last three feed the §1.5 branch check.)
2. Confirm PARENT_ISSUE_TYPE against the **Issue type gate** and ISSUE_STATUS against the **Issue status gate** (`Open` / `Reopened` only). STOP if either is out of scope.
3. Summarize the reported problem / requested behavior (symptom, expected behavior, affected area/module). This summary feeds the RCA in §6.
4. Identify the affected code area in `REPO_PATH` from the Jira description and any linked technical evidence (files, objects, screens, procedures, columns). PRE-REQ: the repository was already loaded/cloned and fetched per **Repository scope** — the analysis MUST read the actual current code in `<REPO_PATH>`, not assumptions about it.
5. **Attachment evidence (screenshots / PDFs / screen recordings) — do NOT stop on "screenshot-only" evidence.** When the load-bearing evidence (an error message, measured values, a failing document, the click path that produced it) lives in image, PDF or video attachments, download and read them:
   - Attachment ids and filenames come from the §1 issue read (`fields=["attachment"]` → each entry has `id` and a `content` URL).
   - The Atlassian MCP has **no** attachment tool, and its OAuth token is scope-blocked (HTTP 403) on `/rest/api/3/attachment/content/<id>` — do not retry through the MCP.
   - Download with the user's Atlassian **API token** (basic auth):
     `curl -sL -u "<ATLASSIAN_EMAIL>:<ATLASSIAN_API_TOKEN>" -o <file> "https://irely.atlassian.net/rest/api/3/attachment/content/<id>"`
     Credentials come from the `atlassian` section of `JIRA_AI_CONFIG` (`email`+`apiToken`, else its `tokenFile` pointer), falling back to `~/.atlassian-token` (`email:token` on one line) or the environment (`ATLASSIAN_EMAIL` / `ATLASSIAN_API_TOKEN`). A token is created at https://id.atlassian.com/manage-profile/security/api-tokens.
   - Read the downloaded image/PDF directly (vision) and extract the exact error text / values into the analysis. Never guess at unread screenshot content.
   - **R-VIDEO-EVIDENCE — a screen recording is evidence, and it gets watched (operator 2026-09-03).** A reporter who records the defect has supplied **more** than a screenshot, not less: the recording carries the click path *and*, in its final seconds, the error dialog. Vision cannot read a container file, so the recording is **decoded into frames and the frames are read** — it is never counted as prose, never counted as missing, and never handed back to the reporter as "please provide steps".
     1. **Detect by `mimeType`, never by the filename alone.** Each entry of the §1 issue read carries `mimeType`: anything `video/*` takes this path, and an `image/gif` over ~1 MB is treated as one too (a GIF that large is an animation, and reading its first frame reads the setup instead of the failure). Download it exactly as an image is downloaded — same basic-auth curl for a Jira attachment, same step-6 fetch ladder for a helpdesk-hosted one.
     2. **Probe, then decode with `ffmpeg`** into the session scratch directory — **never into a repository** (same rule as every other artifact this runbook writes). Probe first so the duration is on the record:
        `ffprobe -v error -show_entries format=duration -show_entries stream=width,height,nb_frames -of default=nw=1 <file>`
        Then extract in **two passes**, because neither alone is sufficient:
        `ffmpeg -v error -i <file> -vf "select='gt(scene,0.15)'" -fps_mode vfr -frames:v 40 -q:v 2 <scratch>\<JIRA>-vid<k>-scene-%03d.jpg`
        `ffmpeg -v error -i <file> -vf fps=1/2 -frames:v 40 -q:v 2 <scratch>\<JIRA>-vid<k>-tick-%03d.jpg`
        The **scene pass** catches every screen transition and every dialog that appears; the **tick pass** (one frame per two seconds) guarantees coverage of a recording that barely changes — a screen where only a grid cell updates produces almost no scene changes, and the scene pass alone can return a single frame from a clip with two clear states (measured, 2026-09-03). `-frames:v 40` is a **cap, not a target**; a 40-second clip yields a dozen. On an `ffmpeg` older than 5.1, `-fps_mode vfr` is spelled `-vsync vfr`.
     3. **Read the LAST frames first, then walk backwards.** The error the ticket was filed about is almost always in the final seconds; the path that produced it is in the earlier ones. Reading forward from frame 001 spends the run on a login screen.
     4. **What the frames must yield — recorded item by item, not as "the video was reviewed":** the **verbatim error text** (→ Step 1a `SYMPTOM_QUOTE = QUOTED`, the frame being the artifact this run fetched and read), the **screen and menu names plus the click path** (→ transcribed into a numbered sequence and resolved under **R-REPRO-STEPS**, §1.6 Step 2b, and driven at §1.7a), the **document numbers** visible in headers and grids, and the **expected-vs-actual values**. A recording that yielded none of these was not read — say which frames were read and what each contributed.
     5. **`ffmpeg` absent from PATH, with a recording on the ticket, is a STOP — and the question goes to the OPERATOR, never to the reporter (operator 2026-09-03).** This is the same shape as the missing-API-token STOP at the end of this step, for the same reason: a **one-time setup gap on the analysis machine** is not a gap on the ticket. Halt **before** §1.6 classifies and before anything at all is written to the Jira:
        - **Nothing goes to the Jira.** No RCA, no information request, no triage comment, no `JIRA-AI-*` label, no transition. A missing decoder on our side must never surface as a question on the customer’s ticket — that is R-EVIDENCE-UNREADABLE with a new cause and it is the more expensive half of it: the reporter who filmed the defect did **more** than most, and gets told they supplied nothing.
        - **Report to the operator and stop**, in these terms: `STOP — <JIRA> carries <n> screen recording(s) and ffmpeg is not on PATH, so the load-bearing evidence cannot be read. One-time install: winget install --id Gyan.FFmpeg --scope user --accept-package-agreements --accept-source-agreements  (no admin rights — it lands under %LOCALAPPDATA%). Then open a NEW terminal — winget adds it to the user PATH, but never to a terminal that was already open — and re-run <JIRA>.` The wizard installs it too: `Setup-JiraAiFix.ps1 -Section ffmpeg`.
        - **The run never installs it itself, and never waits on an install.** It reports the one command and stops. This runbook does not mutate the operator’s machine mid-analysis, and a background install the run then polls is exactly the kind of half-state that makes a run unauditable.
        - **The STOP does not depend on how important the recording looks.** Whether a recording is load-bearing is precisely what cannot be known before watching it — that is the whole lesson of R-EVIDENCE-UNREADABLE, where the asset assumed unimportant carried both of the items the run then declared missing. A recording on the ticket and no decoder is a STOP even when the description reads complete.
        - **It is triggered by evidence, not by run start.** No recording on the ticket → `ffmpeg` is never checked, never probed and never mentioned; a run on a text-only ticket is unaffected by its absence.
        - **A decode that fails with `ffmpeg` present is a different state** — a truncated or corrupt upload. That one is not a STOP: record `decode: FAILED <ffmpeg’s own error>`, continue on the remaining evidence, and §6.5 B governs what may be asked for.
     6. **Every recording is decoded BEFORE §1.6 classifies**, on the same "order matters" rule as the stills. A recording nobody watched is the same defect as a screenshot nobody opened, and it buys the same wrongly-asked question and the same stalled week.
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
   - **R-EVIDENCE-UNREADABLE — "unreadable" is a measurement, never an assumption (operator 2026-08-28, ref SC-9232).** The rule above already required this fetch; SC-9232's run skipped it, wrote *"it is not reachable by the automation account"* into the Information Request, and asked the reporter to re-attach. The image was **public** — HTTP 200, `image/png`, 130 KB, and it needed **no cookie at all** — and it carried both items the same comment listed as missing: the verbatim error text and the ticket number. Two hard requirements follow:
     1. **Fetch ladder for an off-Jira image, in order:** (a) plain unauthenticated GET — helpdesk `Export/...` asset paths are frequently served without a session, so the cookie is not the first thing to reach for and its absence or expiry is not a reason to skip the attempt; (b) GET with the `helpdesk` cookie; (c) the §1 step 5 Atlassian-token route for a genuine Jira attachment. Only after (a) and (b) both fail is a helpdesk-hosted image unreadable.
     2. **You may only call evidence unreadable by exhibiting the failed fetch.** Record `evidence fetch: <url> -> <HTTP status> (<auth used>)` in the run output for every attempt, and never write "unreachable/unreadable" into a Jira comment without that line behind it. An unfetched asset is `NOT ATTEMPTED`, which is a defect in the run — not a gap on the ticket. Asking a reporter to re-supply evidence they already supplied is the most expensive kind of wrong this runbook can be: it stalls the ticket for days and moves the blame. **And a 200 is not a read.** A video fetches perfectly and still tells the run nothing until it is decoded, so its ledger line carries a second half — `evidence fetch: <url> -> 200 (video/mp4, 4.2 MB); decode: <n> frames read | FAILED <reason>` (**R-VIDEO-EVIDENCE**). A fetched-but-undecoded recording is `NOT ATTEMPTED` on exactly the same terms as an unfetched image, and it may never be reported as missing evidence.
   - **No HDTN referenced at all → skip this step silently and continue.** Never treat a missing HD ticket as missing evidence, never ask the reporter for one, and never search the helpdesk for a ticket the JIRA does not name.
   - Cookie missing or **expired** (HTTP 401 / redirect to the login page) → **record the gap and CONTINUE on the evidence the JIRA itself carries** (operator 2026-08-07 — supersedes the 2026-08-06 STOP; the HD ticket is supplementary, so its unavailability must never halt an otherwise-analyzable JIRA). Report `helpdesk cookie expired — HDTN evidence not read; refresh required for fuller evidence` in the run output, and where the unread HDTN would have supplied the restore location, fall through to the normal §1.7 acquisition path (registry sweep → ticket backup/link → §1.6 DB information request). Never guess or brute-force a login; never store the helpdesk password anywhere.

6a. **CUSTOMER SOP evidence — when the reporter cited an SOP, read the procedure they cited (R-SOP-EVIDENCE, operator 2026-09-09).** iRely reporters name the Help Desk SOP alongside the HD ticket in the summary — `HDTN-495072 - SOP-1334 Cannot create voucher for Load Shipment Other Charge from Pending Payable tab` — and that number points at the customer's own signed-off procedure: the screens in order, the configuration, the values, and screenshots of each step working. It is the **strongest statement of intended behaviour this runbook can obtain**, because a consultant wrote it *for that customer* and the customer accepted it.

   **What it is NOT.** An SOP is a business-process document. It names no function, no table, no stored procedure and no column, and it shows the process **succeeding** — so it can never locate the defect or specify the code change. It collapses the front of the run (is this real, how is it reproduced, what should it look like) and leaves §1.6 through §3.4 untouched. **A cited SOP never replaces the JIRA's own evidence** (operator 2026-09-09): the JIRA carries what went wrong — symptom, build, branch, customer, database, failure screenshots — and the SOP carries what should have happened. A run authoring a code change whose justification is a screenshot of the feature working has inverted this rule. **The executed object still beats the inferred mechanism (§1.7b);** an SOP sits further from the deployed object than a formula does.

   **Trigger.** An `SOP-<n>` token anywhere in the summary, description or comments — **case-insensitive, and the number is required**: `\bSOP-(\d+)\b` under a case-fold. Tested 2026-09-09 against live summaries, and the number is what separates a citation from prose: *"Weight not matching as per the SOP applied filter"* (RM-13165), *"Standalone AP SOPs for Delta Features"* (AP-24541) and *"26.3 BASE SOP - FRD-T51"* all name SOPs and cite none, so none of them may trigger this step. A ticket may cite more than one (`SOP-61 and SOP-2259`) — read each. No token → skip silently, exactly as a missing HDTN is skipped. **Never search the Help Desk for an SOP the JIRA does not name, and never ask a reporter for one** — most JIRAs cite none and that is not a gap.

   **The number IS the id (verified 2026-09-09).** `strSOPNumber` is `"SOP-" + intSOPId` (`intSOPNumberLength: 8` for `SOP-1334`), so the token parses straight into `sop_id`. **Do not look it up in the Jira `SOP` project** — that project's counter tops out at `SOP-1007` while cited numbers reach `SOP-2259`, and the low numbers *collide* with unrelated Cloud issues: the case named "SOP-531 - Print Multiple Checks" sits against a Jira issue about a General Journal. A key that resolves is not a key that matches.

   **Access ladder — walk in order, stop at the first rung that answers.** All three read the same server, `helpdesk.mcp.url`, as the developer whose session it holds; there is no new privilege on any rung.
   1. **In-session MCP tools** (`mcp__<serverName>__get_sop`, `…_get_sop_steps`, `…_search_sops`). **A server registered mid-session is not in that session** — restart, or use rung 2. Enumerate the roster at first use and pick by name; it grows, so nothing here hardcodes it beyond the three above.
   2. **Plain HTTPS JSON-RPC with the `apiKey`** — no MCP client, no registration, no cookie, so this rung works from a script or any agent: POST `helpdesk.mcp.url` with `Accept: application/json, text/event-stream` and `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_sop","arguments":{"sop_id":<n>}}}`. The reply is SSE — concatenate the `data:` lines, then `result.content[0].text` is **itself a JSON string and needs a second parse**. Verified 2026-09-09 on `SOP-1334`: `get_sop` 200, `get_sop_steps` 200 with `total: 13`.
   3. **No key → the SOP is unread.** Record the gap, CONTINUE, and emit the pointer (see failure modes).

   **No cookie-only route is known.** Six plausible Help Desk data paths were probed anonymously and with a cookie (2026-09-09) and all returned 404 — the guesses were wrong, which is not proof none exists, but rung 2 makes the search unnecessary. The `helpdesk` cookie is **not** required for any part of this step.

   **What to harvest, and what NOT to pull.** From `get_sop`: subject, `strCustomer`, `strModule`, `strLineOfBusiness`, `strSOPStatus`, and **`strVersionNo`**. From `get_sop_steps`: `strSOPStep`, `strSOPDescription`, **`strScreenLink`** (the i21 screen that step drives — this is what makes the steps resolvable under R-REPRO-STEPS and drivable at §1.7a), and `strSOPStepDetail`.
   - **Select the steps the ticket is about; never fetch the whole SOP blind.** Measured on `SOP-1334`: 13 steps, 224 image references (217 unique), ~104 KB of step JSON and roughly **6 MB** of PNG. Match `strScreenLink` against the screens the symptom names, take those steps and their neighbours, and say which steps were read.
   - **The step number is a string and the default sort is on the SOP id**, so `limit=5` returns steps **1, 10, 11, 12, 13** — not 1–5 (measured). Sort numerically before reading, or page with `start`/`limit` and re-order.
   - **Richness varies per step and coverage may not exist.** In `SOP-1334`, one step carried 70 images and 12 KB of prose while another carried 2 images and 449 characters. A thin step is a thin step — record it as such rather than reporting the SOP as covering the path.
   - **Screenshots: reuse the §1 step 6 fetch ladder unchanged, and rung (a) is the one that works.** Step bodies embed `./Export/CRM/<guid>.png` — **relative**, so join to the `irelyi21Live` base, not the bare host. Verified 2026-09-09: 25 of 25 sampled images returned valid PNG on a **plain unauthenticated GET** (7 KB–64 KB, median 27 KB), so an expired `helpdesk` cookie does not cost the SOP screenshots. Read them (vision) and extract expected state — a sampled frame carried the window title, required-field markers, grid columns, live test data and the verbatim confirmation dialog. **Same never-guess rule as every other image, and the same ledger line** (`evidence fetch: <url> -> <status> (<auth used>)`) under R-EVIDENCE-UNREADABLE.
   - Steps and SOP records also expose **help-manual, training and video links**; a step's recording is evidence on the same terms as a ticket's and goes through **R-VIDEO-EVIDENCE** (§1 step 5), decoder STOP included.

   **APPLICABILITY — what to do when the SOP does not line up with the ticket (R-SOP-APPLICABILITY, operator 2026-09-09).** Check five dimensions, record each one, and apply the precedence rule below. **A mismatch on any of them is a statement about the SOP's applicability, never evidence about the ticket** — it may narrow what the SOP is allowed to settle, and it may never be reported as though the reporter were wrong (R-SOP-ABSENCE).

   **The worked example is the ticket this step was built from, and two of its four comparisons mismatch benignly** (measured 2026-09-09): AP-23873 is project **AP**, customer **Sucafina**, LOB **CTRM**, component **Voucher-CT**, fixVersion **26.3**; `SOP-1334` is customer **Sucafina SA**, module **Contract Management**, LOB **CTRM**, version **24.2**. Read naively that is two failures. Read correctly it is a normal ticket.

   | Dimension | Compare | A mismatch means |
   |---|---|---|
   | **Customer** | Jira customer field ↔ `strCustomer` | **The one that matters.** Match on **identity, not string equality** — `Sucafina` and `Sucafina SA` are the same customer and a string compare reports a false mismatch. A genuinely *different* customer's `Customer SOP` describes **another tenant's configuration** — its own chart of accounts, item setup and terms — so it drops to a **pointer** (A1b cannot answer) and its values may never be used as this ticket's expected state. Check `strSOPType` first: a **Base SOP** is customer-neutral by construction and this dimension does not apply to it. |
   | **Module / project** | Jira project & component ↔ `strModule` | **Expected, and never a discrepancy.** A business process crosses modules; the defect surfaces in whichever module owns the failing screen. Here a CTRM milling process pays its mill through an AP voucher, which is exactly why an AP ticket cites a Contract Management SOP. Record it and move on — **never** use a module mismatch to conclude the wrong SOP was cited. |
   | **Line of business** | `customfield_10054` ↔ `strLineOfBusiness` | Informational, and usually the strongest confirmation that the right SOP was cited (both `CTRM` here). A mismatch alongside a customer mismatch is the real signal that the number is wrong. |
   | **Version** | `TARGET_BRANCH` / fixVersion ↔ `strVersionNo` | Bounds authority, does not discard the SOP. Covering the ticket's line → A1b can answer; materially older (24.2 against 26.3) → **pointer only**, because the screen may have changed since. Record `SOP version <v> vs TARGET_BRANCH <b>`. |
   | **Status** | — ↔ `strSOPStatus` | Anything other than a completed status (`SOP Complete` here) is a **draft**: a pointer, never authority. Nobody signed it off yet. |

   **Screen miss — no step's `strScreenLink` matches the failing screen.** Record `SOP-<n>: no step covers <screen>` and continue on the JIRA's evidence. It means the defect sits outside the documented path, or the process reaches that screen through a step the SOP compresses — **not** that the SOP contradicts the ticket, and **not** that the citation was wrong. Read the neighbouring steps for the configuration they establish, and say that is what you did.

   **Precedence when the SOP and the JIRA genuinely disagree — three cases, and they resolve differently:**
   1. **On what was OBSERVED — the JIRA wins, always.** The SOP shows the path succeeding, which is what a procedure document does; it is not a claim that the path succeeded on this customer's build last Tuesday. An SOP screenshot may **never** be used to argue a reported symptom did not happen. That reading is the §1.8 reproduction gate's job, on the customer's data.
   2. **On what SHOULD happen — §2.4 A1b decides**, under its own two conditions (a covering version, and a positive showing rather than an omission). This is the only case in which an SOP may refute a ticket, and a run reaching `PREMISE-REFUTED` here cites the SOP **step** and the version it compared, never the SOP number alone.
   3. **On APPLICABILITY — the SOP is demoted, not discarded.** Any pointer-grade outcome above means the SOP stops supplying expected values and stays useful for the repro path and the configuration. The run says which dimension demoted it: `SOP-<n>: pointer only (<customer mismatch | version 24.2 vs 26.3 | draft status>)`.

   **Never resolve a disagreement by choosing the more convenient source.** A mismatch is disclosed in the run output and carried into §6, so the reviewer sees what the run reconciled and on what basis. Silently preferring the SOP produces a fix justified by another customer's process; silently dropping it discards the strongest statement of intent on the ticket.

   **What it feeds.** The resolved steps go to **§1.6 Step 2b item 0a** (R-REPRO-STEPS — an SOP the reporter cited *is* reporter-supplied repro steps) and are driven at §1.7a; the expected values and dialogs become the check the fix is verified against at §3; the SOP itself becomes rung **A1b** of the §2.4 premise ladder. All of it joins the §1.6 `EVIDENCE_SET`.

   **Failure modes — three of them, distinguished, and none is a STOP.** An SOP is supplementary on exactly the terms an HD ticket is (operator 2026-09-09): its unavailability must never halt an otherwise-analyzable JIRA.
   - **No `apiKey` configured** → `SOP evidence: not read — no helpdesk.mcp.apiKey; SOP-<n> cited on the ticket`, plus the pointer: the key is issued at `<mcp.url>/setup` after an SSO sign-in and pasted into `helpdesk.mcp.apiKey`; `Setup-JiraAiFix.ps1 -Section hdmcp` walks the whole thing. **Report the one command and continue — never install, register or configure anything mid-analysis** (same rule as the `ffmpeg` STOP, minus the STOP).
   - **HTTP 401 — and it has TWO causes that need different fixes; read the body, never the status alone (tested 2026-09-09).** A malformed or wrong key answers `{"error":"invalid_token","detail":"Invalid Compact JWS"}` → the key itself is bad, so **re-issue it** at `<mcp.url>/setup`. A key that authenticates but whose **server-side session has aged out** is the other case: the server reads the Help Desk as the developer whose cookie was pasted into its setup page, and that cookie expires on the days scale **independently of the local `helpdesk.cookie`** — refreshing the local one does not refresh it, so the fix is to **re-paste the cookie** at the setup page. A key that worked yesterday and fails today with no `invalid_token` is this second case. Record `SOP evidence: not read — helpdesk.mcp 401 (<invalid_token | session expired>); <re-issue the key | re-paste the session cookie> at <mcp.url>/setup` and continue.
   - **SOP not found** → the number is wrong, or the SOP was deleted. The server says so explicitly (`No SOP found for id <n>.`, returned as a tool error rather than a transport failure — so a run must read the tool result, not just the HTTP status). Record `SOP evidence: SOP-<n> not found` and continue. **Never substitute a similar SOP found by search** — a plausible wrong procedure is worse than none, on the same reasoning as a plausible wrong precedent in step 7b.

   **This step never writes to the Help Desk** (R-SOP-READ-ONLY): no comment, no note, no watcher, no field. And the `apiKey` is a secret under the runbook's existing rule — never echoed into a Jira comment, an RCA, a PR, a captured command line, a log or a repository.

   **Absence is never a signal (R-SOP-ABSENCE).** No SOP cited, an unread SOP, or an SOP that does not cover the failing path — none of these is evidence that the reported behaviour is correct, and none may be reported as though it were. They bound what §2.4 can settle and nothing more.

7. **Sibling sweep (mandatory — the decisive evidence often lives on a sibling ticket):** run it as **two sweeps with different scopes**, because the things harvested here are not scoped alike (operator 2026-08-10). A restored database is a **customer-scoped** resource; a prior fix is a **defect-scoped** one. Keying both off one customer-wide JQL is what produced the AP-23288 failure mode: the WAMA 22.1 cohort returns 60+ tickets (page cap — the true cohort is larger), of which exactly ONE sits in the reported component (the subject ticket itself), leaving 59 "prior fixes" with no bearing on the defect.

   **7a. Customer sweep — DB and branch evidence ONLY.** One JQL over the cohort: same project + same customer + same fixVersion, plus any shared campaign label (e.g. `26.2AgrowstarIssue`). **No recency filter** — a restore note's usefulness tracks the freshness of the DB copy, not how recently the ticket moved (ref AP-22786: created 2026-01-26, but its `AP5 / WAMA01_0803DAN` note was posted 2026-08-05; any window keyed on ticket age would have hidden it). When the customer field is EMPTY (ref AP-24784), key the cohort on the environment URL host / campaign label instead; if neither exists, record `sibling sweep: no cohort key` and continue. Harvest ONLY:
   - **dedicated branch names** announced in comments (ref: AP-24727 — the correct branch `26.3DevCTRMFeatures_Sucden` is named only in sibling AP-24511's comment);
   - **DB restore notes / HDTN restore requests** and **backup links** (ref: AP-24802 — the restored Agrowstar DB is documented only on sibling AP-24801's HDTN-511883; ref: AP-23288/AP-24557/AP-24669 — the WAMA DB on AP5 is named only on sibling AP-22786). Request the DB on ONE ticket of the cohort, never per-ticket.

   Everything 7a produces is a **CANDIDATE only**. A DB harvested here was restored for a DIFFERENT ticket and must clear the §1.7 step 0 acceptance gate before the run treats it as this JIRA's database.

   **7b. Defect sweep — prior fixes ONLY.** Scope by DEFECT, not by customer: same project + the subject ticket's **component(s)** (for AP-23288: `VendorStatement*`), **any customer**, resolved within the last **12 months** — **except component- or screen-scoped prior art, which has no time limit** (R-PRIOR-ART-NO-EXPIRY, operator 2026-08-31): a prior fix to the same screen or component never ages out, whatever its date. Ref AP-24914 — AP-13793 (January 2024) had already corrected the very binding that later regressed, had aged out of the 12-month window, and the same defect was then re-diagnosed from scratch twice and fixed in the wrong module once. Harvest prior fixes of the same defect family and link them in the analysis. A customer-cohort ticket in an unrelated component is **not** a prior fix and must never be cited as one — a plausible-looking wrong precedent is worse than no precedent, because §1.5 and §1.6 build on whatever this step hands them. Subject ticket has no component → defer 7b until §1.6 has named the defective object, then key on that object name; if neither exists, record `defect sweep: no defect key` and continue.

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
   4. **Reported-build fallback:** `JIRA_FIX_VERSION` is missing/TBD, or no rule-1/2 branch exists on origin -> **resolve `JIRA_BUILD` through §1.5a (R-BUILD-RESOLVE) first** — the i21 Connect release list maps a build number to the branch that produced it, authoritatively, including the mainline shapes (`24.22.0824.5121` → `24.2Dev`) and abbreviations (`26.1DevIB` → `26.1DevInternalBooks`) that no parse recovers. Only when that lookup is unavailable, fall back to parsing: strip the trailing `.<MMDD>.<seq>`; if the remaining family string is itself a branch on origin (exact case), use it.
   5. **Build-stamp → branch resolution:** the family string matches NO branch (e.g. `26.3FeatSucden`) -> resolve it instead of giving up: extract `<version>` + the customer/LOB token (drop the `Feat|Prod|Dev` marker), score the tokens against the `ls-remote --heads origin "<version>*"` list — a unique hit wins (`26.3FeatSucden` → `26.3DevCTRMFeatures_Sucden`, ref AP-24727). Cross-check via Azure DevOps **pipeline definition names** (`pipelines_get_build_definitions`, name `*<customer>*`): definitions are named `<branch>_<component>` and their builds carry the real `sourceBranch` (verified 2026-08-06: `26.3DevCTRMFeatures_Sucden_GCE` → `refs/heads/26.3DevCTRMFeatures_Sucden`). NOTE: app build stamps are NOT ADO build numbers — a `pipelines_get_builds buildNumber` lookup returns nothing (verified 2026-08-06); resolve by name as above.
   6. None of these resolves to a branch on origin -> **STOP** and report: the base cannot be derived from the Jira; the operator must supply TARGET_BRANCH explicitly (BLOCKED-BRANCH → §1.6 Information Request asks for the Fix Version).

   **Guards (2026-08-06 dry run + same-day regression):**
   - **Case-twin guard:** if the ls-remote scan shows branches differing ONLY by case (real example: AP repo `22.1ProdWaMa` vs `22.1ProdWama` — different heads; SqlScripts `22.1DevWAMA` vs `22.1DevWama`), never guess a casing — use the alias-table branch name **for the repo being targeted**. Branch names are per-repo, not just per-casing: the alias table gives one name per repo, and the correct name in one repo may not exist at all in the other. **A name absent from the owning repo's scan is NOT by itself a STOP — first read that repo's own row in the alias table** (ref AP-24669: `22.1DevWaMa` does not exist in i21_sqlscripts in any casing, yet the live WaMa branch there, `22.1ProdDevWaMa`, was sitting in the scan the whole time). It is a STOP only when the alias table has no entry for that repo AND the scan leaves two or more same-name-different-case candidates undecided — then report the twins to the operator (refs: AP-22786, AP-23288, AP-24557, AP-24669).
   - **Artifact-presence corroboration:** when two candidates survive, prefer the one whose tree actually contains the defective artifact (`git ls-tree` / `git grep` on each candidate). Test ONLY branches present in the FRESH ls-remote scan — stale local remote-tracking refs (e.g. a deleted `origin/22.1ProdWama` still resolving locally) give outdated evidence.
   - **Artifact absent from every Dev candidate:** when the defective artifact genuinely exists ONLY on a branch rule 3 forbids, do NOT silently fix on Prod and do NOT create the object on Dev — STOP and escalate as a §1.6 Information Request/operator decision naming the conflict (Dev-first rule vs artifact location).
     **Before declaring this conflict, prove the artifact is absent from the repo's OWN live branch — scan every branch in the fresh ls-remote list, not only the ones whose name contains `Dev`.** A `<ver>ProdDev<Customer>` branch is a *development* branch despite the `Prod` token, and rule 3 does not apply to it. This guard previously carried the example "`uspAPClearingDetailsWAMA.sql` lives only on `22.1ProdWaMa` — no Dev variant has it (refs AP-24557, AP-24669)", and **that example was wrong** (corrected 2026-08-12): in i21_sqlscripts the file is present on BOTH `22.1ProdWaMa` and `22.1ProdDevWaMa`, and `22.1ProdDevWaMa` is the live Walter Matter branch. The false conflict came from testing only the name `22.1DevWaMa`, which does not exist in that repo. No escalation was ever warranted for either ticket.

   **CUSTOMER_BRANCH_ALIASES (customer field → branch token; extend as new customers appear):**

   | Customer field | Branch token / dedicated branch | Note |
   |---|---|---|
   | Walter Matter | **per repo** — AP: `22.1DevWaMa` · i21_sqlscripts: `22.1ProdDevWaMa` | The branch NAME differs by repo, not merely its casing (verified 2026-08-12). i21_sqlscripts has no `22.1DevWaMa` in any casing; its bare WaMa branches are `22.1DevWAMA`, `22.1DevWama`, `22.1ProdDevWaMa`, `22.1ProdWaMa`. The two `Dev` case-twins have been locked since 2022, so **`22.1ProdDevWaMa` is the live WaMa branch there** — treat it as a normal Dev-first target, NOT as a rule-3 Prod exception. |
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

## §1.5a Build number → branch, via i21 Connect (R-BUILD-RESOLVE)

Runs inside §1.5 step 2 (before rules 4 and 5) and is re-used by §1.6b, §1.6c (which takes an environment's `kind` from `REPORTED_ENV_KIND`, never from the URL's spelling), §1.7 step 2.6, §1.7c and §1.8b. It answers one question the repository cannot: **which branch produced this build number, and when.**

**Why a lookup rather than a parse.** §1.5 rules 4–5 derive the branch by stripping `.<MMDD>.<seq>` off the stamp and matching or fuzzy-scoring what remains. That works only when the family token *is* the branch, and on mainline it usually is not. From the live release list (observed 2026-08-24):

| Build number | Family token after stripping | Actual branch | Would rules 4–5 get it? |
|---|---|---|---|
| `26.3ProdSucafina.0824.318` | `26.3ProdSucafina` | `26.3ProdSucafina` | Yes — rule 4 |
| `26.3DevSucafina.0824.355` | `26.3DevSucafina` | `26.3DevSucafina` | Yes — rule 4 |
| `26.1DevIB.0824.41` | `26.1DevIB` | `26.1DevInternalBooks` | No — abbreviation; rule 5 must fuzzy-score it |
| `24.22.0824.5121` | `24.22` | `24.2Dev` | **No** — the token is not a branch name in any form |
| `22.12.0829.4808` (AP-15931) | `22.12` | `22.1Dev` | **No** — same shape |

The last shape is the mainline shape, so it is also the most common one to arrive on a ticket. **Never conclude a branch from the token alone when the lookup is available.**

**Source.** `https://i21connect.com/#/release` lists every build newest-first, each row giving the build number, its **branch**, and its build time. It is produced by the build system, so it is authoritative in a way string-parsing never is — including for customer branches (`26.3ProdSucafina`) and abbreviated ones (`26.1DevIB`) that no naming rule covers.

**Procedure:**
1. For every build number harvested into `JIRA_BUILD` (§1.5 step 1 — the build field, the description, comments, the environment field), and for `DB_BUILD_VERSION` (§1.7 step 2.6) and `APP_BUILD_STAMP` (§1.7c step 1), query the release list's **Find release** search with the build number.
2. Record `BUILD_BRANCH` and `BUILD_TIMESTAMP` per stamp. Feed `BUILD_BRANCH` into §1.5 as the resolved family — it **precedes** rules 4 and 5, which stay in place as the offline fallback.
3. Also read the **newest build on that branch**. `reported build < newest on its branch` is the honest, timestamped form of "their environment is behind", and it replaces reading dates out of the stamp's digits.

**Access (SSO).** Same shape as the helpdesk: a hash-route SPA behind the corporate SSO, so a plain GET returns the app shell. Same solution, in this order of preference:
1. On the first headed run, capture the **XHR the release page itself calls** from the network trace, and reuse that endpoint directly on later runs — one request per lookup instead of driving a UI. Record it in the `i21connect` config once discovered.
2. Otherwise drive the SPA headless with the saved Playwright `storageState`: type the build number into **Find release**, read the matching row.
Login is headed once so the operator completes SSO/MFA by hand; every run after replays the session headless. A login redirect on first navigation is the expiry signal → re-capture headed. Never brute-force, never guess, never commit the session file.

**Never a STOP.** Unreachable, expired, or the build number is not listed → record `BUILD_BRANCH UNRESOLVED (<stamp>) — i21connect <reason>`, fall back to §1.5 rules 4–5, and disclose the fallback. An unresolved stamp is a known gap, not a licence to assert a branch.

### Reported-environment kind (R-REPORTED-ENV-KIND)

**A JIRA is often reported on a Dev build, not a Prod one** (operator 2026-08-24), and the ticket's prose is not reliable about which. The resolved `BUILD_BRANCH` is. Record `REPORTED_ENV_KIND` = `Dev` | `Prod` | `Customer-Dev` | `Customer-Prod`, derived from the branch name rather than from anything the description says, and let it govern three readings that otherwise go wrong:

- **Staleness.** On a `Prod`/`Customer-Prod` report, `APP-STALE` (§1.7c) means *the customer has not received the build carrying the fix* — a patch/deploy deliverable. On a **`Dev` report it means a dev environment is behind its own branch head** — a redeploy, and usually not a ticket at all. Same verdict string, different deliverable; never write the customer-facing one for a Dev report.
- **Patch signals.** §1.6b B1/B2 on a Dev environment means someone hand-patched a dev box. Worth naming in the ledger, but it is not the customer-patch case and must not be reported as one.
- **The three-way comparison** (§1.7c step 5) keys on *reported* vs *fix-target* environment. That is usually prod vs dev — but on a Dev-reported ticket both sides are Dev, and the useful comparison becomes the reported dev environment against its own branch head.

`REPORTED_ENV_KIND` goes in the run output and in the §6 Verification status block alongside the build stamp it came from.

## §1.6 Resolution feasibility gate (mandatory — classify BEFORE implementing)

Runs after §1.5, before §2. Its purpose is to stop the two dominant failure modes of automated runs measured on a live open queue (2026-08-04 audit of 65 open `Bug-QC` issues in the **AP** project — the ratios below are that queue's, cited as evidence the failure modes are real and common, not as rates to expect in another module): **duplicating work that is already fixed** (25/65) and **attempting a static fix for a data/environment-dependent symptom** that can only be proven on the reported database (28/65). Every run MUST record its `FEASIBILITY` verdict in the run output.

**Step 0.0 — REPEAT-RUN DELTA (R-RERUN-DELTA, operator 2026-09-04). Runs BEFORE Step 0, and is the first thing §1.6 does.**

A developer re-runs this runbook for four reasons, and three of them are changes on **our** side rather than on the ticket (operator, 2026-09-04): **(1)** the runbook's own setup/configuration was missing or incomplete, **(2)** the database could not be reached, **(3)** the app environment failed, **(4)** the ticket's description or acceptance criteria were wrong. Every one of them means the earlier run reached its verdict **without something this run may now have** — so the question this gate answers is not "has anything changed" but **"has anything changed that would make this run reach a different result?"** A re-run that cannot name such a change is re-deriving a conclusion that already exists.

1. **Find this runbook's own prior comments.** Read the ticket's comment history for terminal comments this runbook posted (identified by the `Automated analysis — JIRA-AI runbook` footer). None → this is a first run; record `RERUN = FIRST-RUN` and continue to Step 0.
2. **Read the `Run basis` footer of the most recent one (R-RUN-BASIS).** It records both halves of what that run had: the **ticket state** it read and the **capability** it could reach. A prior comment with no basis footer (posted by a runbook older than 1.5.0) → `RERUN = DELTA-UNKNOWN`: the comparison is done by **reading** the prior comment against the ticket now, and the run continues. Never treat a missing footer as "nothing changed".
3. **Enumerate the deltas** against that basis. Prefer the ticket's own **field change history** since the basis timestamp — it names the edited fields directly and needs no digest. When the history is unavailable through the Jira tool, fall back to comparing the values the footer recorded, and say in the run output which method was used.

   | Delta class | What to compare | Makes a different result when |
   |---|---|---|
   | `SETUP` (cause 1) | the config sections the basis recorded as missing vs what resolves now | a section the prior run lacked now resolves **and** that section feeds this ticket's analysis |
   | `DATABASE` (cause 2) | the basis's DB reachability + the literal `<server>/<dbname>` vs what §1.7 step 0 finds now | a database is reachable now and the prior verdict was `DB_REQUIRED-BLOCKED`, `NOT-REPRODUCED-*`, `SUBSTITUTE-DB*` or any criterion graded `NOT TESTED` for want of one |
   | `APP-ENV` (cause 3) | the basis's `APP_ENV` liveness/build stamp vs a fresh probe | an environment is alive now and the prior run recorded `APP-FIDELITY UNVERIFIED`, `APP_REQUIRED-PROVEN`, or a criterion blocked on the client layer |
   | `TICKET` (cause 4) | description, **acceptance criteria**, Fix Version, environment field, customer/LOB, reported build | any of them changed — see the correction/extension split below |
   | `EVIDENCE` | attachments and comments newer than the basis | new evidence bears on the symptom, the repro, or the reported values |
   | `NONE` | — | nothing above intersects the prior run's basis or its stated blocker |

4. **Rule on materiality — the delta must intersect what actually limited the prior run.** A change that cannot alter the outcome is named and dismissed, not silently ignored: a SharePoint credential refresh does not unblock a ticket whose blocker was an unreadable screenshot, and a priority edit changes nothing at all. Record `RERUN_DELTA = <class(es)> · material: <what it unlocks, tied to the prior run's own verdict> | immaterial: <what changed and why it cannot change the result>`.
5. **`NONE`, or every delta immaterial → STOP.** Report `RERUN = NO-DELTA (prior <verdict> of <date> stands: <one line>)`, **post no comment**, and leave the labels as they are. Re-posting an unchanged conclusion is the waste class the whole §1.6 gate exists to prevent, and a second identical RCA is worse than none: the ticket then carries two, and nothing says which governs.
6. **Material delta → continue, carrying `RERUN_DELTA` into §6.** The new comment MUST open with the **Supersedes** block (§6) naming what the earlier comment concluded, what changed since, and what is now different. When cause 4 applies, split it, because the two halves dispose of the delivered code differently:
   - **CORRECTION** — a requirement the earlier run built to has **changed or been withdrawn**. The pushed branch may implement a specification that no longer exists. State the earlier commit's fate: kept and amended, or superseded and needing retraction.
   - **EXTENSION** — the requirements **grew**; the earlier fix is right but partial. The added criteria enter §2 as new items and are graded normally; the earlier ones are not re-litigated.

**Step 0 — ALREADY-RESOLVED check (runs after Step 0.0):**
**This runbook's own artifacts never satisfy this check (R-RERUN-DELTA, operator 2026-09-04).** Conditions (a) and (b) below are both satisfiable by a *previous run of this very runbook* — it posts an RCA and pushes a named fix commit — so a second run reading its own output would declare the ticket resolved and stop, which is right when nothing changed and badly wrong when the description was since corrected. Step 0.0 owns the "did we already run this" question; Step 0 asks only whether **someone else's** delivered fix resolved it. Exclude this runbook's own comments, branches and commits when evaluating (a) through (d).
Re-read all §1 comments and linked PRs. The issue is **already resolved in substance** ONLY when ALL of these hold:
- (a) a Root Cause Analysis is on the ticket, AND
- (b) a fix exists — merged/active PR link, attached patch `.sql`, or a named fix commit, AND
- (c) **the LATEST dev/QA evidence passes** — a later FAIL, retest-failed comment, or a `Reopened` status voids an earlier PASS (recency rule; ref AP-24412: fix merged 07-09, QA FAILED 07-21 → still in scope), AND
- (d) **the fix content is still present on BOTH `EXPECTED_BRANCH` AND the branch family the latest QA evidence was produced on** (they can differ under Dev-first and sit in opposite states — AP-22099: Dev keeps the substance in rewritten form while Prod is reverted) — verify by CONTENT (diff/blob check of the changed objects), never by `git log --grep <JIRA>` alone: a revert commit also matches the grep and reads as "fix landed" (revert-detection rule; ref AP-22099: fix cherry-picked to 22.2Prod in PR 154760 on 07-09 and REVERTED in PR 155000 on 07-10 after a QC FAIL — the literal triple (a)+(b)+old-PASS matches, yet the issue is definitively unresolved and MUST be analyzed).
→ Only then report `ALREADY-RESOLVED (evidence: <comment/PR refs>)` and **STOP. Do not re-implement, do not create a branch, do not post any comment.** Duplicating an existing fix creates conflicting PRs and misattributes the work.
→ A `Reopened` issue is NEVER ALREADY-RESOLVED: reopening is itself the statement that the delivered fix did not hold — proceed to Step 0.5.

**Step 0.1 — PRIOR-ART SEARCH (R-PRIOR-ART, mandatory — do NOT scope the already-fixed question to this ticket; ref AP-24899).** **Read the knowledge base first (§1.6e, R-KB-FIRST)** — it is the one prior-art source keyed on what the ticket already gives you (an error code, a quoted message, an object name), and it costs **one keyed extraction — never a read of the index** (§1.6e step 2, R-KB-EXTRACT). It does not replace any sweep below: its earned records are prior art to be cited and checked like any other, its derived records are pointers that must be confirmed on this ticket's branch, and a miss means nothing was indexed rather than that nothing exists.
Step 0 asks "does *this ticket* say it is fixed?" That is the wrong question when the same defect was already diagnosed and fixed on a **different** JIRA — the ticket in hand then carries no fix link, passes Step 0 cleanly, and the run re-derives a root cause from scratch with nothing to check itself against. AP-24899 is the worked example: the identical defect had been diagnosed on **AP-22527** seven months earlier, on the *same customer* (Sucafina) and the *same build* (24.2.1009.1129); the run never looked outside the ticket, invented a different mechanism, and pushed a wrong fix. Three searches, all cheap, all mandatory:

1. **Object history (the highest-yield one — run it first).** For every code/DB object on the implicated path — **and every file that CONSUMES it** (the view / viewmodel / controller that binds to it, the caller that invokes it; R-PRIOR-ART-CONSUMERS, operator 2026-08-31) — read who last changed it and why: `git log --oneline -20 -- <path>` and, once a specific line is suspect, `git log -S'<the suspect expression>' --oneline -- <path>`. Every JIRA key those commits name is prior art on *this object*. On AP-24899 the defect line is `ALTER TABLE #tmpMiscPOPayables DROP COLUMN intVoucherPayableId, B_intItemId` in `uspAPUpdateIntegrationPayableAvailableQty.sql`; `git log -S` on it surfaces AP-22527 (PR 129516) and its own ancestor AP-12861 immediately.
2. **Signature search across the project.** JQL the ticket's distinguishing signature — not its wording: the error class/number, the screen, the customer, the build. e.g. `project = AP AND (summary ~ "<screen>" OR description ~ "<error text>") AND "Customer" = <customer> ORDER BY created DESC`. Same customer + same build + same screen is a near-certain duplicate even when the summaries read differently ("VOUCHER WARNING FOR A NON-CONSUMABLE ITEM" vs "Voucher not opening in Pending payables" are the same defect).
3. **Read the prior RCA before writing ours.** Any hit → read its Root Cause in full. Then one of exactly two things must appear in this run's output:
   - the prior mechanism is the same → this is a duplicate or a deployment gap; go to §1.7b and expect `DEPLOYED-STALE`. Do **not** author a new code fix; the outcome is almost always "the fix exists, the environment needs it".
   - the prior mechanism is *different* → this run must **explicitly refute** it, naming the evidence that rules it out. A silent disagreement with an accepted, QA-passed RCA on the same signature is the drift signature itself — the earlier analysis had the failing environment in hand and this one usually does not.

4. **The restored database's own datafix log (R-PRIOR-ART-DATAFIXLOG, operator 2026-08-31).** Whenever §1.7 restored a copy, or a `knownServers` connection to the reported environment exists, run `SELECT strJIRAId, strAuthor, strRemarks, strBuildNumber, dtmDateExecuted, strFileName FROM tbl<MODULE_PREFIX>DataFixLog ORDER BY dtmDateExecuted DESC` (`tblAPDataFixLog` in AP; the same table exists per module). Every row is a defect already proven **in this exact database, on this build, for this customer** — the only prior-art source that is environment-specific, and it costs one query. Read `strRemarks` for the mechanism, not just the key: a datafix that reset orphaned state on a table names the failure family without naming this ticket. Ref AP-24960 — the log held **AP-24868** (*“reset orphaned ysnInPayment on payment schedules that are not on any payment”*), same customer, same build, same payment-schedule tables, executed four days before the ticket was reported; the run that missed it searched only git and Jira, and concluded the stale value had no writer.

→ Record `PRIOR_ART = <keys, and same-mechanism / refuted-because-<reason> / none>` in the run output. `none` is only reportable after all four searches actually ran.

**Step 0.5 — FIX-DELIVERY CHECK (Reopened issues with a merged fix; ref AP-24412):**
When the ticket carries a merged fix PR but QA reports the symptom again, determine **whether the fix was actually in the build the tester used** before re-analyzing:
1. Resolve the fix commit(s): merge date/time and the branch they landed on (Azure DevOps PR data / `git log`).
2. Parse the tester's failing build stamp `<family>.<MMDD>.<seq>` (from the QA comment/screenshot): the build's branch family and cut date.
3. **Ancestry test, not branch-name match (regression finding, ref AP-24412):** the fix is in the build iff its commit is an **ancestor of the build's branch as of the cut date** — `git merge-base --is-ancestor <fix-commit> origin/<family>` — and the operative arrival date is the **earliest ancestry-path merge into the family branch**, NOT the PR's own merge date (AP-24412: PRs merged to `26.3Prod`/`26.3DevSucafina` on 07-06/07-09, but the content reached `26.3ProdSucafina` via the sync merge PR 155484 on **07-14**, before the 07-19 cut → fix WAS in build 0719.211). Transitive arrival through sync/CP merges counts; test content ancestry, never assume from the PR's target branch. Fix in build → **residual defect**; continue the analysis with the merged diff as the baseline (the residual cause must be sought beyond it; per-requirement verdicts from Step 1.5 sharpen this — requirements already passing confirm delivery, the still-failing one is the residual scope).
4. Fix NOT in the tested build (not an ancestor as of the cut) → the retest was premature. **Post ONE informational comment** stating: the fix was merged in PR `<id>` on `<date>` and reaches `<family>` via `<the sync path>`; the failing build `<stamp>` predates it; please retest on the first `<family>` build cut AFTER the **arrival-on-family** date (never the PR merge date). **This runbook creates NO PR and re-implements nothing in this case — provide the information only** (operator 2026-08-06).

**Step 1 — build the EVIDENCE_SET** from §1: exact error text, failing document numbers, expected-vs-actual values, repro steps — from the description, comments, downloaded/read attachments (§1 attachment step), **frames decoded from any supplied screen recording** (§1 step 5, **R-VIDEO-EVIDENCE**), helpdesk-hosted images, the environment field, and the §1 step-7 sibling sweep. Screenshots referenced but unreadable/absent count as MISSING evidence, not as evidence — and so does a recording that was downloaded but never decoded.

**Step 1a — `SYMPTOM_QUOTE`: can you quote the symptom, or only name it? (R-SYMPTOM-QUOTE, operator 2026-09-02, ref SC-9232).** Record exactly one of two states before any code is read, and carry it into §6:

- **`QUOTED`** — the primary observable exists **verbatim** in the EVIDENCE_SET together with the artifact it came from: the exact error string, an expected-vs-actual pair of values, or a captured screen state. The source must be something this run **fetched and read** (§1 step 5 / step 6) — never the reporter's prose summary of it, never a paraphrase, and never a description of a screenshot nobody opened. A **frame decoded from a supplied screen recording** is such an artifact: the dialog in the last seconds of a recording is a captured screen state and it qualifies `QUOTED` exactly as a screenshot does. What never qualifies is a recording this run did not decode — that is `CLASS-ONLY` **and** a defect in the run, not a gap on the ticket.
- **`CLASS-ONLY`** — the symptom is known by its class alone: "unable to distribute", "wrong amount", "error on save", "screen does not load".

**While `SYMPTOM_QUOTE = CLASS-ONLY`, no §6 RCA may be posted.** The run terminates through the §1.6 information request or the §6.5 D triage comment, whichever fits. This is deliberately blunt, and it follows directly from Step 2a: an error *class* has several producers by construction, so a root cause named against a class is a guess about which producer fired — however fluent the reasoning that produced it, and however well it survives code reading.

SC-9232's first run reached exactly this insight unaided — *"'Unable to distribute' is an error class, not an error"* — and it then evaporated, because it lived in a sentence in a comment rather than in a variable the next run inherited. Two runs later a root cause was published against the class. The verbatim error had been on the ticket from the first day and took one unauthenticated GET to read (R-EVIDENCE-UNREADABLE); it named a stored-procedure parameter that no amount of code reading had considered, and it falsified the published hypothesis outright.

`CLASS-ONLY` is not a failed run — it is a true statement about the evidence, and reporting it costs the reporter one copy-paste. Publishing a root cause on top of it costs a wrong fix on a customer ticket, and the ticket's real defect stays open behind it.

**Step 1.5 — enumerate ALL requirements (multi-requirement rule; ref AP-24801, AP-24802):**
A ticket often carries more than one distinct reported defect/requirement — one in the description and more in comments or screenshots (e.g. AP-24802: duplicated SQL charge lines AND a duplicated UI grid column). List every distinct requirement, analyze EACH, and fix as many as feasible in this run; give each its own verdict line in the run output and its own entry in the §6 Acceptance Verification block.
- **Cross-team routing comments are judged on evidence, not taken as a gate** (operator 2026-08-06; ref AP-24801: an RM comment says "Moving Jira to AR Team", but the screenshot shows an AP screen/flow): when the artifact/screenshot evidence sits in AP, proceed with the AP analysis and note the routing dispute in the RCA — do not silently drop the issue because a comment reassigned it.
- If a comment reports a **genuinely different issue** than the description, analyze what is in scope and apply Reporter Rule R1 (§6.5): a different issue belongs on a separate JIRA.

**Step 2 — STATIC-PROOF test.** Attempt to pin the root cause by reading the actual code on `TARGET_BRANCH`:
0. **Resolve `SERVED_TREE` BEFORE the first client-side search (R-JS-CLIENT-TREE, hoisted here operator 2026-08-31).** §3.4a decides which ExtJS tree the branch actually serves; resolve it **now**, not there — `git ls-tree --name-only origin/<TARGET_BRANCH>`, both `universal` and `app` present → `universal`, only `app` → `app`, neither → no split. Then constrain every client-side search that follows to it: `git grep -n <symbol> origin/<TARGET_BRANCH> -- <SERVED_TREE>/`, never a filesystem grep of the working copy. That does three things a repo-wide grep cannot: it keeps the dead tree out of the result set (on `AP` 24.1 the two trees share **455 basenames**), it keeps gitignored `build/` bundles out, and it pins every line number the RCA quotes to `TARGET_BRANCH` rather than to whatever branch the working copy happens to be sitting on. §3.4a still runs as the placement check on the CHANGESET; only the determination moves here. **A root cause quoted out of the unserved tree is void** (§3.4a step 5), and a line number resolved against the wrong branch is a citation the reviewer cannot follow.
1. Locate the code path the EVIDENCE_SET implicates (screen → controller/store → SP/view/function). **Screen-first tracing (ref AP-24669):** identify the actual screen from the screenshot, then trace how that screen loads its data (view/store → SP) AND how the transaction writes its data (posting path/GL generation) — when the report and the writer disagree (e.g. AP Clearing Details shows a row the GL never got), reconcile BOTH code paths against the description before concluding a DB is needed; the DB request may still be valid, but the code validation comes first and sharpens what to ask for.
2. **Cross-object error attribution (ref AP-24784):** never confine the search to the object named in the error/stack — search the exact error message string REPO-WIDE (triggers, functions, CATCH-rethrow wrappers included). AP-24784's "cannot delete posted voucher" names `uspAPDeleteVoucher` line 347, but the RAISERROR lives in the `trg_tblAPBill` INSTEAD-OF-DELETE trigger re-raised by the proc's CATCH.
2a. **ERROR-CLASS DISCRIMINATION (R-ERROR-CLASS, mandatory whenever the symptom is a named error; ref AP-24899).** A reported error almost always belongs to an **error *class* with several possible producers**, and the first producer you find that could explain it is a *candidate*, not the cause. Finding one and stopping is the most common way a run produces a fluent, internally consistent, completely wrong RCA.
   - **Enumerate before you choose.** List EVERY construct reachable from the reported user action that can raise this error class, then discriminate between them. Do not write a Root Cause while two candidates remain unexcluded.
   - Worked example (AP-24899, "identity column error" = SQL 544): at least two producers sit on the Add-Payables→SAVE path — (i) Entity Framework inserting a phantom parent graph into identity tables, and (ii) `INSERT INTO @voucherPayablesMiscPO SELECT * FROM #tmpMiscPOPayables` inside `uspAPUpdateIntegrationPayableAvailableQty`, where an undropped extra temp column shifts `SELECT *` by one so the UDT's identity column receives an explicit value. Both raise 544 on the same click. The run picked (i) by plausibility and never enumerated (ii), which was the real one — and was already fixed in the repo.
   - **Common i21 error classes and their competing producers** — enumerate all of the applicable row before choosing: SQL **544 / 8101** (identity insert) → EF phantom-parent insert · `INSERT … SELECT *` column shift from an undropped/added temp-table column · explicit key value in a UDT/table-type load · `SET IDENTITY_INSERT` left off in a data script. SQL **207** (invalid column) → object/UDT bind mismatch · a view not refreshed after a base-table change · `SELECT *` contract drift. SQL **2627 / 2601** (duplicate key) → missing dedupe in a staging insert · re-entrant posting · a NULL-killing predicate that lets a row through twice. SQL **8152 / 2628** (truncation) → widened source column not widened downstream. **HTTP 500 on save** → any of the above surfacing through the ORM, so the class must be resolved to the raising statement before it is attributed to the UI. **UI / client-side validation warning** → a controller-level validator method · an `Ext.data.validator` declared in the model's `validators:` block for the implicated field (a *different file*, routinely in a `.Shared` package, routinely carrying a variant message) · a shared-package validator reused by several screens · server-side validation on the API the save posts to. For ExtJS, **always read the model's `validators:` block for the implicated field before recording `candidates = 1`**: a field validator fires on record validation and is invisible to any search of the controller.
   - **`SELECT *` over a temp/staging table is a standing suspect** whenever the error involves column counts, identity columns, or bind mismatches: the failure appears at the consumer while the defect is the producer's column list. Check the drop/add-column statements between the `SELECT … INTO` and the `INSERT … SELECT *`.
   - **Discrimination requires an observation, not an argument.** Acceptable discriminators: an execution capture naming the raising object (`ERROR_PROCEDURE()` / `ERROR_NUMBER()` in a wrapper, Extended Events, Profiler — see §1.8), or the §1.7b deployed-object diff. **A repo-wide search of the exact error text NARROWS the candidate set; it never certifies `candidates = 1`** (R-ERROR-TEXT-NARROWS, operator 2026-08-31). Message strings drift by a word between producers of the same invariant, so an exact-string search that returns one hit is evidence of one *wording*, not of one *producer*. Before recording `candidates = 1`, run a second pass on the **predicate** — the comparison, the invariant, the field being validated — and not on the message. Ref AP-24960: `VoucherViewController.validatePaymentScheduleTotal` raises *“Amount due is not equal with payment schedules total.”* while `AccountsPayable.Shared/src/common/validators/PaymentScheduleTotal.js`, wired at `Bill.js:1230` on the `dblAmountDue` field, raises *“Amount due is not equal with payment schedules.”* — the same invariant, one word apart. The exact-text search returned a single producer, recorded `candidates = 1`, and certified the wrong answer; the delivered fix guarded one of the two. Reasoning about which candidate is "more likely" is not a discriminator.
   - Record `ERROR_CLASS = <class> · candidates = <n> · selected = <object> · discriminated by = <observation>`. When `n > 1` and no observation could be made, the run may NOT claim a root cause: carry all surviving candidates into the §1.8 verdict and the §6 RCA as competing hypotheses.
2b. **REPORTER-SUPPLIED REPRO STEPS — resolve them into a repro specification; never mistake them for the error (R-REPRO-STEPS, operator 2026-08-28, ref SC-9232).** A numbered `Steps 1..n` sequence in the description or a comment is the highest-value evidence a reporter can add short of the error text, and it has exactly two jobs here: it **bounds the R-ERROR-CLASS candidate set**, and it **makes §1.8 Axis B constructible**. Use it in this order:
   0a. **A CITED SOP IS reporter-supplied steps (R-SOP-EVIDENCE, §1 step 6a).** When the ticket names an `SOP-<n>`, the customer's procedure supplies the numbered sequence directly — and in a better form than prose, because each step already carries the screen it drives (`strScreenLink`) and a screenshot of its expected end state. Resolve it through items 1–5 exactly as a typed sequence, with three differences: the screen name is **given** rather than inferred, so item 1's "resolve every step to a field, a column and a value" starts from a named screen and the §1.6d catalogue lookup is direct; the expected values come from the step's screenshots, so item 4's discrimination has an authority behind it; and **the SOP documents the path SUCCEEDING**, so it bounds `ERROR_CLASS` by telling you what the customer was *doing*, never by telling you what failed. **Do not ask a reporter for steps while a cited SOP sits unread on the ticket** — that is §6.5 B's bar, on the same terms as item 0. An SOP that is cited but unreadable is `NOT ATTEMPTED` until the step 6a ladder has been walked and its failure exhibited.
   0. **Steps supplied as a recording ARE steps (R-VIDEO-EVIDENCE).** When the sequence arrives as a screen recording instead of as text, transcribe the decoded frames (§1 step 5) into the numbered form yourself, record that transcription and its frame sources in the run output, and run items 1–5 against it — the medium does not make the steps missing. A run that asks for "step-by-step reproduction" while a recording of those steps sits on the ticket has re-asked for supplied evidence, which §6.5 B bars outright.
   1. **Resolve every step to a field, a column and a value** in whichever module owns the screen. "Set distribution type: Split" → the distribution-option column and its code; "set each split's entity distribution type to Spot Sale" → the per-split entity distribution column and its code; "enter futures and basis price for each entity" → the manual pricing path, not the auto one. A step you cannot resolve to a named field is a step you have not used.
   2. **Re-enumerate the candidates against the resolved shape and cross off the ones the steps exclude.** Every validation on the path whose precondition the steps contradict is out; every one whose precondition they *satisfy* moves up. Record the before/after: `ERROR_CLASS candidates: <n> -> <m> after repro steps`. That delta is the whole reason the steps were worth asking for, and an unchanged count means they were read as prose instead of resolved.
   3. **Drive §1.8 Axis B with it.** The resolved shape is a construction recipe — it says what to *build*, so a NEW transaction can be created on a restored copy even when no reported document number was given and Axis A is `NOT-REPRODUCED-TXN-ABSENT`. Steps convert a run that could only *search* for the artifact into one that can *manufacture* it, and where a DB or `APP_ENV` is reachable they can move `FEASIBILITY` off `INFO_REQUIRED`. On a `SUBSTITUTE-DB-COLD` copy (§1.7 R-DB-COLD-SWEEP) Axis B is unavailable — a cold-sweep copy is shared and takes no writes — so the steps buy candidate elimination there and nothing more; say so rather than implying the repro was run.
   4. **They narrow; they do not discriminate.** Only an observation selects from the surviving set (2a, last bullet). When the steps leave `m > 1` and the exact error text is still missing, then the error text is still missing: re-ask for **that one item**, name the surviving candidates and what each of them would print, and do not re-ask for the steps that were just supplied (§1.6 dedupe guard, and the Reporter Rules note in §6.5).
   5. **A step sequence with no document numbers does not become one.** Steps say what shape to build; they do not name the transaction that failed. Never close that gap with a similar record found in a database — that is an `ANALOGY` under §1.8 and it can never grade a criterion `PASS`.
2c. **DATA-CAUSE RESOLUTION — the issue type never rules out a data cause (R-DATA-CAUSE, operator 2026-08-31).** `ISSUE_CATEGORY` records how the ticket was filed; it says nothing about what is actually wrong. A `Bug`, `Technical Debt`, `Performance` or `Bug-*UAP` ticket is routinely caused by data, and that data is routinely written by a program — the two are one loop seen from opposite ends, and neither end may be assumed away from the issue type. Every run resolves this explicitly, whatever the type:
   1. **Upstream — is the symptom being raised by a stored value that should not be there?** Any persisted value in the EVIDENCE_SET that the run cannot attribute to a writer is a **candidate root cause** and is traced under §3.4 Proof 1. It is never recorded as a curiosity, a side-note or a *related defect* and left at that.
   2. **Downstream — did a program defect write rows that are already wrong?** That is §3.11's direction, armed by the evidence and not by the issue type.
   3. Record `DATA_CAUSE = none | present: <the value, the rows, the count> | undetermined: <what was checked and why it did not settle>` in the run output and on the §6 RCA. `none` is reportable only after the check actually ran.

   Ref AP-24960: the run recorded a posted voucher's Amount Due of 1,062.50 against a payment-schedule total of 18,763.69 under **Related defects found**, classified the ticket from its own chosen fix as a UI defect, and left the value untraced. The stale value *was* the ticket; the two UI defects were only what made it unrecoverable for the user.
2d. **PREDICTED OBSERVABLE — every hypothesis states what would disprove it, and that check runs against the evidence already on the ticket (R-FALSIFIER, operator 2026-09-02, ref SC-9232).** Before a candidate is recorded as `selected` in 2a, write down two things: the observation the ticket's own evidence **must** show if that candidate is the cause, and the observation that would **rule it out**. Then test both against every artifact in the EVIDENCE_SET — screenshots included, and *especially* the ones already read for some other purpose.

   Record `FALSIFIER = <what must be true if this candidate is the cause> · checked against: <artifacts> · result: consistent | CONTRADICTED by <artifact>: <what it actually shows>`.

   A `CONTRADICTED` result is a **STOP on that candidate**, exactly like `REPRO-ATTEMPTED-DISPROVEN` (§1.8 step 5): return to 2a and select from the surviving set. It is never a caveat carried inside an RCA, and it is never outweighed by how well the candidate explains everything else.

   Ref SC-9232: the published hypothesis was that the screen never adds a split's Spot Sale quantities into its running total, so the distributed amount stays short and Process refuses to complete. Its predicted observable is therefore *Distributed Units < Total Units, Remaining > 0*. The single screenshot on the ticket showed **Total Units 977.718 · Distributed Units 977.718 · Remaining 0** — the hypothesis was contradicted by evidence attached before the first run ever started, and finding the contradiction required reading one number.

   This is the cheapest gate in the runbook. It needs no database, no app environment and no execution, so it remains available on precisely the runs that can prove nothing else — the runs where an unfalsified hypothesis is most likely to be published as a cause.

3. **Cross-module handoff check (ref AP-24802):** when the defective artifact is fed by another module (e.g. the SC/Scale module creates the voucher payables that AP displays), verify the upstream module's handoff (what it actually sends — e.g. the number of payable rows) before assuming the defect is on the consuming side; name the owning module in the analysis.
4. The root cause is **statically proven** ONLY when a concrete defect is identified in the code AND that defect deterministically produces the reported symptom for *any* data satisfying the repro preconditions — e.g. wrong column referenced, missing join/filter predicate, inverted guard, wrong format string/date write-format, missing field in an entity↔view mapping, error-207 bind mismatch. **This includes deterministic aggregation/sign/filter defects that happen to be reported against specific documents** — "wrong for the reported documents" does not force DB_REQUIRED when the arithmetic/filter error is fully visible in code and holds for any conforming row (refs: AP-23443 — sign/netting bug in `uspAPRptOpenClearing` doubles the receipt amount for any negative settle-storage row; AP-23288 — missing Cash Refund branch + a `ysnCancelledPayable != 1` NULL-killing predicate). In such cases classify STATIC and use the DB (when obtainable) only as the validation vehicle.
   **`STATIC` is a routing decision, never an exemption from proof (R-STATIC-NOT-EXEMPT; ref AP-24899).** Before this rule, `STATIC` was self-certifying and it silently switched off the runbook's only reproduction requirement: §1.7's BEFORE/AFTER proof algorithm runs only under `DB_REQUIRED-ACTIONABLE`, so a hypothesis that merely *felt* deterministic bought an exemption from being tested — decided by the very reasoning that produced it. `STATIC` now means only "no database is *required* to author the fix". It does NOT mean the symptom need not be raised: **§1.8 runs on every run regardless of this verdict**, and if a database or app environment is in fact reachable, a `STATIC` run must still attempt the reproduction there and record the outcome. A `STATIC` classification that was never confronted with an execution is a hypothesis wearing a verdict's clothes.
5. The root cause is **NOT statically provable** when the symptom genuinely depends on data state: rounding at specific quantities/amounts, posted/unposted transaction sequences, records created by older builds, upgrade failures on a particular database, "cannot reproduce on standard data", or the affected object exists in no repo copy that is both **current and on the valid deployment channel** for TARGET_VERSION (a stale copy in a non-deployed channel does not count — ref AP-24446: a pre-multi-company `uspAPRpt1096.sql` exists in SqlScripts, but SSDT is not the 24.3 channel and the deployed body must be scripted from the customer DB).

**Step 2.9 — DATA_FIX routing (R-DATAFIX-DB; applies when `ISSUE_CATEGORY = DATA_FIX`):**
The STATIC-PROOF test of Step 2 does not apply — a data fix is not a code defect, so there is no code path to pin. What replaces it:
1. Confirm the ticket really is a data correction: the current code produces correct results going forward, and the defect is the **rows already written** (typically by a bug since fixed — the issue type's own definition). If the code is still defective, this is a BUG in a Data Fix ticket: analyze the code defect, say so in the analysis, and apply **Reporter Rule R1** (§6.5) — the program fix belongs on its own JIRA, linked (the standards page's impact-analysis rule: every data fix names the code fix that stops the defect recurring, or states that one is required).
2. **Locate the linked program JIRA** (the root-cause code fix). Missing → do not stop; note it as a required link in the delivery comment and in the run output.
3. `FEASIBILITY` is **never `STATIC`** here: resolve to `DB_REQUIRED-ACTIONABLE` when a DB of the reported environment is reachable, else `DB_REQUIRED-BLOCKED` → ONE information request for the backup → STOP. The affected row set, its count, and every Standard 1–4 assertion in §3.6 can only be established on the real data.

**Step 3 — classify FEASIBILITY and act:**

| FEASIBILITY | When | Action |
|---|---|---|
| `STATIC` | Root cause statically proven AND the fix is verifiable without a database (or a reachable dev DB covers §3) | Continue to §2. |
| `DB_REQUIRED-ACTIONABLE` | Root cause is data/environment-dependent (Step 2.5), OR the fix touches SQL logic that writes into a UDT/table, OR the deployed object must be scripted from the reported DB — AND **the REPORTED environment's database** is reachable from the evidence: a `.bak` attachment, a download link (description, comments, or **environment field** — ref AP-23349), a `knownServers` match, or a sibling-ticket/HDTN restore note (§1 step 7a — a **candidate** only until it clears the §1.7 step-0 acceptance gate). A reachable backup of a DIFFERENT company/environment does NOT qualify (ref AP-24402: sibling TE2 backups exist but the symptom lives on ECOMProdCompany → BLOCKED); that is the same test the step-0 gate applies, so a candidate the gate rejects leaves the verdict at BLOCKED. A raised-but-unconfirmed restore request (e.g. "HDTN raised, will investigate when done") is **provisionally** actionable: if the §1.7 step-0 lookup (incl. the unnamed-server registry sweep) dead-ends, downgrade the recorded verdict to BLOCKED and note the pending request. | Run **§1.7** immediately — no information request. Restore/connect, reproduce, prove (BEFORE/AFTER), then continue to §2 using that DB as the §3 validation DB. (2026-08-06 dry run: 6 of 20 DB_REQUIRED issues were actionable — AP-23349, AP-24785, AP-24793, AP-22786, AP-24771, AP-24412.) |
| `DB_REQUIRED-BLOCKED` | Same root-cause classes, but no backup/DB of the reported environment is reachable from the ticket, its siblings, or the registry | Post the **INFORMATION REQUEST** comment asking for the DB backup (template below), then STOP. Ask on ONE ticket per customer cohort (§1 step 7), not per ticket; a **pending human request for the same customer DB** (even raised for a sibling's symptom) counts — report "awaiting DB since <date> (requested by <who> via <ref>)" instead of asking again. |
| `APP_REQUIRED-ACTIONABLE` | §1.6b classified the run `APP_REQUIRED` (Trigger A or Trigger B) **and** §1.6c resolved an `APP_ENV` for this JIRA — from the parameter, the ticket, or the `appEnv` registry — that **probed alive** with a working session | Run **§1.7a** (runtime reproduction) and **§1.7c** (app-layer deployed fidelity), fold what they capture back into the EVIDENCE_SET, re-enter Step 2, then continue to §2. Compatible with `DB_REQUIRED-ACTIONABLE` — when both apply, restore the DB first (§1.7) and point the app at it. |
| `APP_REQUIRED-PROVEN` | **Not assignable here.** §1.6b classified the run `APP_REQUIRED` and none of §1.6c's three sources produced a live `APP_ENV`, so the run continues on every reachable layer and the question is adjudicated at **§1.8b** once those layers have been *executed*. Only §1.8b can raise this verdict, and only on a completed elimination ledger showing that no reachable layer raises the symptom | Set by §1.8b → **ENVIRONMENT REQUEST** carrying the ledger + `JIRA-AI-NeedInfo` → **STOP**. One per customer cohort, same dedupe rules as the DB request. A classification alone never reaches this row. |
| `INFO_REQUIRED` | EVIDENCE_SET is insufficient to even locate the defect (no repro steps, no exact error text, referenced-but-missing attachments, no expected behavior) and cannot be derived from code | Post the **INFORMATION REQUEST** comment listing exactly the missing items (template below), then STOP. |
| `CANNOT-FIX` | The analysis concludes this run cannot deliver the fix: the defect is owned by another module's code (and the evidence supports that ownership), a won't-fix/by-design candidate, or blocked by a cross-team dependency. **Precedence:** when ownership evidence points elsewhere BUT a reachable DB could adjudicate it, `DB_REQUIRED-ACTIONABLE` wins — prove first on the DB, and post CANNOT-FIX only from the captured evidence (ref AP-22786: posting CANNOT-FIX on the AP-vs-IC assertion alone would repeat the won't-fix→reopen loop already on the thread). | Post ONE **CANNOT-FIX comment** (§6.5): the full analysis details, why it cannot be fixed here, and a concrete suggestion/recommendation (owning module + the exact artifact, or the dependency to resolve). Then STOP. (Operator 2026-08-06 — replaces the former silent skip.) |

**R-NOFIX-COMMENT — every run that does not deliver a fix leaves a comment (operator 2026-08-07).**
A run must never end silently on the ticket. Exactly ONE comment is posted per run, chosen by outcome:

| Run outcome | Comment posted |
|---|---|
| Fix delivered (branch pushed, or data fix delivered per §3.6) | **§6 RCA / Acceptance Verification** — the RCA comment is reserved for a *successful* fix and is posted nowhere else |
| Needs information (`INFO_REQUIRED`, `BLOCKED-BRANCH`, missing/untestable acceptance criteria per §2) | **INFORMATION REQUEST** (template below) + `JIRA-AI-NeedInfo` label |
| Needs the database (`DB_REQUIRED-BLOCKED`, incl. every blocked `DATA_FIX`) | **INFORMATION REQUEST** scoped to the DB backup + `JIRA-AI-NeedInfo` label — one per customer cohort |
| Needs the app environment (`APP_REQUIRED-PROVEN`) | **ENVIRONMENT REQUEST** (§1.8b §3), which MUST carry the elimination ledger — what was executed on each reachable layer and what it produced — + `JIRA-AI-NeedInfo` label — one per customer cohort |
| Cannot be fixed here (`CANNOT-FIX`) | **CANNOT-FIX** comment with details + recommendation (§6.5 A) |
| Fix was already delivered but the tester's build predates it (Step 0.5) | **fix-delivery informational** comment (§1.6 Step 0.5.4) |
| Analysis completed but the run stopped for any OTHER reason — §3 validation FAIL, DB restore failure, unresolvable branch, an aborted implementation | **TRIAGE comment** (§6.5 D) — so the ticket carries what was learned instead of nothing |
| `ALREADY-RESOLVED` (§1.6 Step 0) | **nothing** — posting here would only add noise to a ticket that already has its RCA and fix |
| `NO-DELTA` (§1.6 Step 0.0) | **nothing**, and the labels are left as they are — a re-run that cannot name a change would only add a second analysis saying what the first one said, and a ticket carrying two says which governs to nobody |
| Out-of-type / out-of-status gate | **nothing** — the issue belongs to someone else's workflow |

Dedupe applies to every row above: re-read the comments first, and do not repost an unanswered equivalent (see the rules below).

**INFORMATION REQUEST comment (template + rules):**

Post ONE comment via `addCommentToJiraIssue` (contentFormat markdown) and add the label **`JIRA-AI-NeedInfo`** (additively — re-send existing labels alongside it, never overwrite):

```
# Information Request — automated analysis (JIRA-AI)

Automated analysis on branch `<TARGET_BRANCH>` could not <establish the root cause / verify the fix> from the evidence currently on this ticket.

**What was analyzed:** <1–2 lines: the code path read and what was ruled out.>

**Database — what was supplied, and what we used:**
- Supplied on this ticket: <attachment / link / HDTN <n> `Database Copy`> | **none**
- Registry sweep: <n> known servers scanned -> <`<server> / <dbname>`, build <DB_BUILD_VERSION>, snapshot <date>> | no <customer> database found
- Acceptance gate: <PASSED - usable as primary> | <FAILED check <n>: <reason> - retained as SUBSTITUTE-DB-COLD, orientation only>
- Therefore: <the database IS / is NOT the blocker here, and what a backup would settle that the copy we have cannot>

**Missing — please provide (only the items that apply):**
- [ ] Exact error message text (copy-paste, not a cropped screenshot)
- [ ] Step-by-step reproduction, including the specific document numbers — name the module's own document types (`DOC_TYPES`; e.g. voucher/IR/contract/load in Accounts Payable, invoice/credit memo/receipt in Accounts Receivable)
- [ ] Expected vs actual behavior/values
- [ ] Browser console (F12) / network trace at the moment of failure (for UI errors)
- [ ] **Database backup (`.bak`, compressed) of the reported environment** — or a restore-point/location we can pull — required because the symptom is data-dependent and does not reproduce on a standard database
- [ ] Fix Version (the field is currently empty/TBD — the target branch cannot be derived without it)

Once provided, re-run JIRA-AI on this issue; the analysis resumes from the new evidence.

----------------------------------------------
*Automated analysis — JIRA-AI runbook <RUNBOOK_VERSION> · <model name>*
*Run basis (R-RUN-BASIS) — ticket: `updated <ISO instant read>` · fixVersion `<v>` · env `<field>` · build `<stamp>` · customer `<c>` · `<n>` attachment(s) · last comment read `<id or date>` · description `<chars>` chars; capability: config `<sections that resolved | none>` · DB `<server>/<dbname> | not reachable>` · app env `<url + build stamp | not reachable>`*
*<the §6.8 telemetry line, verbatim from the script — or `Run telemetry unavailable — transcript not readable.`>*
```

Rules:
- **Dedupe guard (JIRA-AI's own requests only):** before posting, re-read the comments and labels. If an unanswered **JIRA-AI** information request for the SAME missing items already exists (or the `JIRA-AI-NeedInfo` label is present with no new evidence since), do NOT post again — report "awaiting info since <date>" and STOP. A **human** request for the same item (e.g. a dev's DB request via HDTN — ref AP-22155 / HDTN-511903) also counts: report "awaiting <item> since <date> (requested by <who>)" instead of re-asking.
- **R-REQUEST-RECONCILE — "the reporter replied" is not "the reporter answered" (operator 2026-09-02, ref SC-9232).** An information request lists numbered missing items. A re-entry must reconcile them **item by item** before the run may treat the block as cleared: for each item in the previous request record `ARRIVED (<where — which comment, attachment or field>)` or `STILL-MISSING`, and carry that table into the run output. The previous request comment **is** the store, so nothing is written and R-DB-LEDGER-REUSE is untouched. Each still-missing item keeps its own blocker alive on its own terms — a `STILL-MISSING` exact-error-text item holds `SYMPTOM_QUOTE = CLASS-ONLY` (Step 1a) no matter what else arrived — and the re-ask names **only** the outstanding items (Step 2b.4).

  SC-9232's request asked for five things. The reporter supplied one, the reproduction steps, and the next run treated the whole block as cleared and published a root cause. The exact error text, the failing ticket number, the expected-vs-actual pair and the console trace were all still outstanding, and the first of those was the item that decided the answer. **New activity on a ticket is a trigger to re-enter (R-QUEUE-LABEL-STATE); it is never evidence that the gap closed.**
- **Third-party analysis comments are last-resort input, not a gate (operator 2026-08-06; ref AP-24683):** a prior analyzer's comment (human or bot, e.g. a "Bug Analyzer Report") neither blocks this run nor substitutes for it — JIRA-AI performs its OWN independent analysis first and consults such comments only afterwards, to cross-check or to harvest facts it could not reach. Their unanswered info request does not trigger the dedupe guard; but before asking, re-verify each item against the ticket's own attachments — do not ask for evidence already visible in an unread screenshot (ref AP-24683: the sample voucher PIDE-80 was in the ticket's own screenshot all along). **Attachment unreadable to the automation account** (attachment-level permission denial, distinct from the MCP-403 the token workaround fixes — seen on AP-24683 att 1840317): treat it as MISSING for the analysis, and word the request as an ACCESS/re-upload ask ("attachment <id> is not readable by the automation account — please re-attach or paste the content"), never as an accusation that the evidence wasn't provided. **This bullet is unavailable until the §1 step 6 fetch ladder has actually been run and failed (R-EVIDENCE-UNREADABLE).** A permission denial is a recorded HTTP status, not an inference from the host name: an image on `helpdesk.irely.com` is not unreadable because it is off-Jira, and the empty Jira `attachment` field says nothing about it. Never ask for a re-attach on the strength of where the image is hosted.
- **The database line must never be silent about what the ticket supplied (R-DB-COLD-SWEEP, §1.7 step 0; ref SC-9232).** The **Database** block above is mandatory on every information request — including one whose missing items have nothing to do with data. When no backup or link was provided and the cold sweep found a copy anyway, the comment says all three things: nothing was supplied, one candidate was found and gated, and what that copy can and cannot settle. SC-9232's request opened with *"The database is not the blocker … an AGrowStar 26.2 QA copy at build 26.2.0826.475 is already reachable, so no backup is needed"* — true, and it left the reader unable to tell whether that copy came from the ticket (it did not), whether it held the reported artifact (it did not: the only `SPL` Direct In tickets on it were Contract 50/50, not the reported all-Spot-Sale shape), or whether sending a backup was still worth doing. Conversely, never ask for a backup without first running the sweep and reporting its result.
- Ask ONLY for items that are genuinely missing; pre-check each candidate item against the ticket (including read screenshots and the sibling sweep) first — ref AP-24557: the screenshots already named the documents and the measured delta, so the only missing item was the database.
- A `BLOCKED-BRANCH` case (missing/TBD fixVersion so §1.5 cannot derive a base) uses this same protocol — the missing item is the Fix Version.
- Every §1.6 STOP verdict (`ALREADY-RESOLVED`, awaiting-info, info-request-posted, `CANNOT-FIX`) MUST be recorded in the run output and, when a tracking file is in use (e.g. `jira-ai-open-resolution-tracking.md`), as a row/update there.
- Append the **Reporter Rules note** (§6.5) to any comment posted here when one of its rules applies.

## §1.6b Does this JIRA need the i21 application? (R-APP-REQUIRED, mandatory on EVERY run) — classification only, never a STOP

Runs immediately after §1.6 Step 3, before any database work. Its output is `APP_REQUIRED = YES (<signals>) | NO`.

**This section decides that the app is *probably* needed. It never decides that the run is blocked.** When an `APP_ENV` is reachable it routes straight to `APP_REQUIRED-ACTIONABLE`; when one is not, the question stays **open** and the run continues on every layer that is reachable. The blocked verdict is not available here and is never reached by classification — it is earned at **§1.8b**, after the cheaper layers have been executed and shown not to raise the symptom (operator 2026-08-24).

**Why this is its own gate, and why "is the symptom visual?" is the wrong question.** §1.7b asks, for the database, *is the customer running the code we are reading?* — and answers it by scripting the deployed object out and diffing it. **There is no such instrument for the application layer.** A stored procedure body can be read out of a restored copy; a patched DLL, a compiled handler, or the ExtJS component a particular deployment serves cannot be read out of a database at all. The database does not record the application build. Only a running application does. So the app environment is not merely a nicer way to look at a screen — for the app half of the codebase it is the **only** deployed-fidelity instrument this runbook has, and a run that reasons about app-layer code without one is reasoning about a build nobody has identified.

That gives two independent trigger families. **Either one is sufficient.**

### Trigger A — the client is the only layer that can raise the symptom

Not "the evidence is a screenshot" (§1.8 §1 exists to kill that inference) but "no database execution could produce this observation":

| A# | Symptom class | Why SQL cannot substitute |
|---|---|---|
| A1 | A dialog whose **content** is missing, blank, truncated or generic — a `Warning` box with an empty body, an `Error` with no text | A proc can return a wrong message; it cannot return the *absence* of one. Blankness is raised in the renderer (ref AP-15931) |
| A2 | Field or grid state contradicting a correct dataset — value blanks on tab-out, dropdown empty, column renders blank while the SP returns the value, UI sort/filter disagrees with the query | The dataset being right is the whole point; the defect is downstream of it |
| A3 | Client-side JS/ExtJS error text — `Uncaught TypeError`, component-lifecycle errors, store-load failures | Never raised by SQL Server |
| A4 | Document/report **render** — layout, overlap, missing logo, pagination, print CSS | Distinct from report **data**, which §1.8's table routes to the DB |
| A5 | Hang, infinite spinner, "not responding", with no SQL error raised | There is nothing to `EXEC` |
| A6 | Behaviour resolved client-side from role, permission, company preference or screen configuration | The resolution happens in the client, not in the query |

### Trigger B — the app-layer deployed state is unknown or disputed

This is the family that fires on the two cases the operator named — **an incorrect patch was given**, and **the customer's build is behind while the fix is already on the branch**. Both are deployment questions, and §1.7b can only answer the database half of either. Any single signal is sufficient:

| B# | Signal | Where it is found | What it means |
|---|---|---|---|
| B1 | An **`Apply patch <JIRA> to <env>` helpdesk ticket** is linked | the description's `This issue relates to i21 Help Desk ticket:` lines | A patch was hand-applied to that environment. It is therefore running code that is neither `TARGET_BRANCH` nor any released build, and nothing in git describes it. A project-independent convention — verified across AP-24748, AP-24388, AP-24253, AP-24225, AP-24216, AP-24178, AP-23640, AP-23047, AP-22838, AP-22677 and AP-22637, and the same `Apply patch <JIRA> to <env>` HDTN shape is used by every i21 module |
| B2 | The **repro steps begin with "Apply patch …"** | Steps to Replicate | The defect is *conditional on the patch*. The unpatched branch does not carry it, so reading the branch proves nothing either way (ref AP-15931) |
| B3 | A comment carries a **four-part build stamp** (`22.12.0829.4808`) beside "still occurring" / "still persists" / "cannot reproduce on my end" | comments | Two parties are on two different deployed states and neither has been identified |
| B4 | **Dev and QA disagree about reproducibility** on the thread | comments | Unresolved deployed-state divergence. This is the exact shape that terminates in resolution `Cannot Reproduce` |
| B5 | §1.7b returned `DEPLOYED-STALE` / `DEPLOYED-NEWER` / `DIVERGED` **and** the implicated path contains at least one non-DB file | the §1.7b ledger | Drift is *proven* on the half we can see. The app half cannot be checked from SQL at all, and there is no reason to assume it drifted less |
| B6 | A reopen/retest of a JIRA already marked delivered, whose original CHANGESET touched non-DB files | Step 0 / 0.1 / 0.5 | The same question: did the app-layer change actually reach this environment? |

**B5 is the signal that makes this gate pay for itself on ordinary tickets** — it converts a §1.7b finding the run already has into a decision about the half it cannot see, at no extra cost.

### Step 3 — decide and route

1. Evaluate Trigger A and Trigger B. `APP_REQUIRED = YES` if **any** signal fired. Record every signal that fired, by id (`APP_REQUIRED = YES (A1, B2, B3, B4)`) — never just the verdict.
2. **Resolve `APP_ENV` per §1.6c** — explicit parameter, then a URL found on this ticket, then the `appEnv` registry in `JIRA_AI_CONFIG` — and **probe it alive** (§1.6c step 2). *No `APP_ENV`* is only true once all three sources have been tried; a run that never consulted the registry has not answered this question, it has skipped it. Alive with a working session → **`APP_REQUIRED-ACTIONABLE`** → run §1.7a and §1.7c. Whatever the probe returned, write it back to the registry (§1.6c step 3) before moving on.
3. No `APP_ENV`, and **Trigger B fired alone** (a DB is reachable and the symptom is DB-raisable) → continue on the DB layer, record `APP-FIDELITY UNVERIFIED (<signals>) — no APP_ENV`, and apply the R-VERDICT-HONESTY language downgrade in §6: the app-layer half of the deployment question is open, so no criterion that depends on it may be graded `PASS`. This shape never becomes a STOP.
4. No `APP_ENV`, and **Trigger A fired** → carry `APP_REQUIRED = YES (<signals>)` forward as an **open question**, continue the run through §1.7 / §1.7b / §1.8 exercising every layer that *is* reachable, and hand the question to **§1.8b**. Record it in the run output now, so that if the operator can supply an environment cheaply they can do so before §1.8b — but never wait, and never block, here.

### Step 4 — hand off to §1.8b

This section posts no comment and takes no STOP. Both the **ENVIRONMENT REQUEST** and the decision to stop live in **§1.8b**, because both require evidence §1.6b does not yet have: the results of actually executing the reachable layers. Classification is a reason to go looking; only the §1.8b elimination ledger is a reason to stop.

### Worked example — AP-15931, the ticket this gate is built from

[AP-15931](https://irely.atlassian.net/browse/AP-15931) — *Blank Warning message when deleting a Vendor* (Bug-QC, fixVersion 22.1). Its **Steps to Replicate** are, verbatim: *"Apply patch from EM-3841. Go to Vendor screen. Open and delete Vendor."* The thread then runs:

- Dev: *"I was unable to reproduce the issue in version 22.1. After applying the patch, I performed the deletion of the vendor, and the deletion was successful."*
- QA: *"please confirm the patch that we are referring here is the created patch from EM-3841? May we know the build to which you applied it?"*
- QA: *"after testing with the latest build version, the error is still occurring. Build version: 22.1Dev (22.12.0829.4808)"*
- QA: *"I tested again today using the AP database, but the error still persists. Could you please try using the FRM database?"*
- Dev: *"we are using the latest patch from EM-3841 … I can't still reproduce the issue."*

Resolution: **`Cannot Reproduce`**.

Signals this gate fires on at Step 1, from the description and thread alone: **A1** (a warning dialog with no text — not reachable from SQL), **B2** (the repro is gated on applying a patch), **B3** (a four-part build stamp posted beside "still occurring"), **B4** (dev and QA in direct disagreement about reproducibility). Four independent signals; one would have been enough.

What changes: the run classifies `APP_REQUIRED` before touching a database, and §1.7c captures the build stamp and served-asset state of **both** environments — the one where it reproduces and the one where it does not. The first differing artifact is the answer, and it is a measurement rather than an argument. Note what the thread did instead: it substituted **databases** (the AP DB, then the FRM DB) to explain a divergence in **application** state — the wrong axis entirely for a blank dialog — and that is what three weeks and six comments went on. `Cannot Reproduce` on a ticket where one side reproduces it every single time is not a resolution; it is an unmeasured environment difference, and it is the terminal state this gate exists to prevent.

**And if no environment had been available at all?** Then §1.6b would have recorded `APP_REQUIRED = YES (A1, B2, B3, B4)` and the run would have carried on to the database anyway — executing the vendor-delete validation path with the reported vendor and finding that it returns its message correctly, i.e. `no error raised` at the DB layer. That row is what §1.8b needs: the message provably exists in the database and is lost somewhere between there and the screen, so the remaining layer is the client and nothing cheaper can observe it. The request that follows names an experiment and shows its working, rather than asking for an environment because a screenshot looked visual.

## §1.6c App-environment registry — resolve it, prove it is alive, and remember it (R-APP-ENV-REGISTRY)

**Invoked from §1.6b Step 3 item 2**, before that step can answer *"is an `APP_ENV` reachable?"*, and again at the close of §1.7a / §1.7c to write back what the run learned. It is why a second ticket on the same customer never has to rediscover an environment the first one already found, and why a run never spends its §1.8b request asking for a URL that is already on file.

**The problem it closes.** An i21 app environment is discovered the expensive way — a URL buried in a comment, the address bar visible in an attached screenshot, an `Apply patch <JIRA> to <env>` HDTN, or an operator who happened to know it. Until now that discovery died with the run: the next ticket on the same customer started from nothing and, on a Trigger A symptom, walked all the way to a §1.8b environment request for an environment this team was already using. And a URL on file is worth nothing if nobody knows whether the app behind it is still up — environments get decommissioned, renamed and moved, and reading evidence from a dead one is not a risk, it is a silent no-op that reads as *"not reproducible"*.

### 1. Resolve — three sources, in precedence order

| # | Source | Rule |
|---|---|---|
| 1 | An explicit `APP_ENV` / `APP_ENV_PROD` / `APP_ENV_DEV` parameter | Always wins. The operator is naming the environment for *this* run |
| 2 | A URL **found on this ticket** | The description, a comment, the visible address bar of an attached screenshot, the linked HDTN's environment field, or an `Apply patch <JIRA> to <env>` HDTN (§1.6b B1). This is the *discovery* path, and its result is what step 3 persists |
| 3 | The **`appEnv` registry** in `JIRA_AI_CONFIG` | Matched by **recorded identity only** — `customer` plus `kind`, or the environment token the stored `baseUrl` already carries (`2710DEV`). Never assemble a URL from a customer name and a guessed host; that is the discipline `knownServers` applies to SQL servers, and for the same reason |
| — | None of the three | Record `APP_ENV NOT RESOLVED — no parameter, none on the ticket, none in the registry` and hand §1.6b that answer |

Sources 2 and 3 are not alternatives — resolve **both**. When they disagree, the ticket wins for this run and the registry entry is corrected in step 3. `kind` comes from `REPORTED_ENV_KIND` (§1.5a) where the URL is the reported environment, never from the URL's own spelling: `…/2710DEV` in a customer's hands is still the environment they reported on.

### 2. Liveness probe — is the app still alive? (R-APP-ALIVE, before every use)

**A registry hit is a claim, not a fact.** Before a resolved environment is used, written back, or counted as "reachable" by §1.6b, probe it: one unauthenticated `GET <baseUrl>`, short timeout (10s), no saved session.

| Probe result | `status` | What it means for the run |
|---|---|---|
| HTTP 2xx/3xx, **or** a redirect to a login page | `alive` | The app is up. A login page **is** aliveness — never read it as a failure |
| Reachable, and the saved `storageState` still authenticates | `alive` | Straight into §1.7a step 1, headless |
| Reachable, but the saved session redirects to login | `alive` (session expired) | The environment is alive; the **session** is stale → §1.7a's headed re-capture. Never a registry failure |
| DNS failure, connection refused, TLS failure, timeout, or 5xx | `unreachable` | Treat as **no `APP_ENV` of that kind** for this run. §1.6b routes to its step 3/4 and the run continues on every other layer |

Record the probe verbatim in the run output — `appEnv.<key> <baseUrl> — alive (HTTP 302 → login)`, or `appEnv.<key> <baseUrl> — unreachable (connect timeout 10s)`. A probe is one request: never a reason to slow a run down, and never a reason to stop one.

An `alive` result also **arms §1.6d step 3**: when no control catalogue exists (or the existing one is stale) for the module repo on `TARGET_BRANCH`, the background generation starts **now**, so the catalogue is normally on disk by the time §1.7a needs it — at zero cost to the main run, which continues into §1.7 without waiting.

### 3. Write back — the registry is run-maintained (R-APP-ENV-PERSIST)

**`appEnv` is the one node of `JIRA_AI_CONFIG` this runbook writes.** Update `%USERPROFILE%\.jira-ai-runbook-config.json` → `appEnv.<envKey>` at two points: immediately after the step 2 probe, and again when §1.7a / §1.7c finish. `<envKey>` is the environment's own token where it has one (`2710DEV`), else `<customer>-<kind>` — stable across runs, so an entry is **updated, never duplicated**.

| Field | Written when | Value |
|---|---|---|
| `baseUrl`, `kind` | entry created | as resolved in step 1; `kind` from `REPORTED_ENV_KIND` (§1.5a) |
| `customer` | entry created | the Jira `Customer` field (`customfield_10038`) |
| `source` | entry created | where the URL was found — `AP-24801 description`, `HDTN 123456 Apply patch`, `operator` |
| `firstSeen` | entry created | run date |
| `lastCheckedAt` | **every** probe, including a failed one | run date |
| `lastAliveAt`, `status: alive`, `consecutiveFailures: 0` | probe alive | run date |
| `status: unreachable`, `consecutiveFailures + 1`, `lastError` | probe failed | the transport reason **only** (`connect timeout`, `DNS NXDOMAIN`, `HTTP 503`) — never a credential, never a session cookie |
| `lastBuildStamp`, `lastBuildStampAt` | §1.7a step 1 resolved `APP_BUILD_STAMP` | the **full four-part** stamp verbatim. This is what lets the next run open on a known deployed state instead of re-deriving it |
| `storageState`, `obtainedAt` | §1.7a captured a session headed | the path, **outside every repository** (same rule as `sqlServer.password`) |
| `seenOn` | every run that used the entry | append this `JIRA_KEY`; keep the twenty most recent and drop the rest |

**Never deleted, only retired.** Three consecutive failed probes on separate runs → set `status: stale` and stop preferring the entry at step 1, but **leave it in the file**. Removing an environment is the operator's call — `Setup-JiraAiFix.ps1 -Section verify` lists what the node holds, so a decommissioned entry is visible as one. An entry the runbook deletes is an entry the operator cannot see was ever there.

**What is never written.** A password or session cookie the runbook read off a *ticket* is not persisted here — it is used for the run and forgotten (§1 step 5). Only a credential the operator supplied for this purpose belongs in the file, which is where `sqlServer.password` already lives. Nothing from this node is ever echoed into a Jira comment, RCA, PR, log, or Confluence page; a `baseUrl` may be named in a comment only when the ticket or its HDTN already names that environment — the discipline R-DB-PROVENANCE applies to a shared database.

**Never a STOP.** Config file missing, read-only, or unparseable → record `appEnv registry NOT updated — <reason>` in the run output and continue. The registry is an accelerator: a run that cannot write it is a slower run, not a failed one.

### 4. Why this registry is run-written when `knownServers` is not

§1.7's **R-DB-LEDGER-REUSE** forbids this runbook from maintaining any ledger of databases, restores, or servers, and that rule stands unchanged. The two cases differ in exactly one thing that matters — the cost of a stale entry:

- A **restored database** is per-JIRA and ephemeral. It gets dropped without notice, and a stale ledger entry points a later run at a database that is gone, or worse at a same-named copy holding somebody else's data. That failure is silent and it corrupts evidence.
- An **app environment** is a long-lived addressable service on a stable URL that many tickets share. A stale entry fails *loudly and cheaply*: one 10-second probe, taken before anything is read from it, after which the run carries on exactly as though the entry had never existed.

So the trade runs the other way round. A DB ledger is cheap to rebuild and dangerous to trust; an environment is expensive to rediscover and safe to verify. **Verifiability is what earns the write** — this registry is only allowed because step 2 proves every entry before anything is taken from it.

## §1.6d UI navigation & control catalogue — generated once, consulted every run (R-UI-CATALOGUE)

**Armed by §1.6b/§1.6c, consumed by §1.7a.** It exists to close the most token-expensive habit an app-layer run has: discovering *what to click* by reading screen snapshots. On the ticket this section was built from (SC-9232), identifying the controls on one screen — which combobox is "Item", which button is "Process" — cost more effort than every other layer combined, and none of that discovery survived the run. The two halves of that knowledge have different sources and the same fix:

- **Control identity is derivable from the module's own source.** ExtJS declares the human name next to the address (`fieldLabel`/`text` beside `itemId`), so a screen's control map can be extracted from the repository with no app, no session, and no browser — measured yield ~60% of itemIds carrying a name (Grain: 3,907 itemIds, AP: 1,823), including the cases that defeat any guess (`Process` → `btnSave`).
- **Menu identity is NOT derivable from source at all** — the i21 menu is data-driven per licence — but it is trivially readable from a live shell: every entry is an `<a class="i21-menu-link" data-menu='{"c":…,"n":…,"m":…,"t":…,"mid":…}'>` payload, and that payload is stable for a build and a licence.

Both are stable per branch / per environment. So: derive once, store outside every repo, consult on every run.

**The harness folder — created by this runbook itself, never shipped.** Everything lives under `%USERPROFILE%\.jira-ai-harness\` (user profile, same placement rule as `JIRA_AI_CONFIG`: never inside a repo, never committed, never attached to a Jira). Contents are class names, labels and itemIds only — no credential, no customer data — but the placement rule holds anyway.

| Path | What it holds | Written by |
|---|---|---|
| `bin\Generate-ControlCatalogue.ps1` | the generator in step 2, materialized verbatim from this document | step 1 bootstrap |
| `catalogues\<Module>@<branch>.json` | screen class → control-name → `itemId` map derived from that branch's checked-out source, with per-screen collision lists | step 3 (background agent, or on demand) |
| `nav\<envKey>.json` | the menu payloads a live shell exposes — label, screen class, module, `menuId` — keyed by the §1.6c `<envKey>` | step 4, merged across runs |
| `locks\<name>.lock` | the per-environment browser lease, plus the two write locks that stop concurrent runs from losing each other's merges (§1.7a, R-BROWSER-ISOLATION) — each holding the JIRA key, the PID and a timestamp; stale after 30 minutes | §1.7a / §1.7c, taken and released per run |

### 1. Bootstrap — the folder is created on first need, from this document alone

When `%USERPROFILE%\.jira-ai-harness\` does not exist: create `bin\`, `catalogues\`, `nav\` and `locks\`, and write the step 2 script to `bin\Generate-ControlCatalogue.ps1` **byte-for-byte as it appears below** (UTF-8). Nothing else is required — no zip, no clone, no download: a developer who has only this runbook has everything this section needs. Bootstrap failure (folder read-only, disk full) → record `harness folder NOT available — <reason>` and continue; §1.7a then runs on live discovery exactly as it did before this section existed. **Never a STOP.**

### 2. The control catalogue generator — source-derived, no app, no session

Invocation, per module repo (repeat for each repo the run's implicated paths touch). On Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.jira-ai-harness\bin\Generate-ControlCatalogue.ps1" -RepoPath <REPO_PATH> -Branch <TARGET_BRANCH>
```

On macOS/Linux the same script runs under **`pwsh`** (PowerShell 7 — `brew install powershell` / the distro package; the `powershell` binary does not exist there), and the harness folder is `~/.jira-ai-harness/`:

```sh
pwsh -NoProfile -File "$HOME/.jira-ai-harness/bin/Generate-ControlCatalogue.ps1" -RepoPath <REPO_PATH> -Branch <TARGET_BRANCH>
```

The script itself is written cross-platform (`$HOME`, forward-slash path literals); if `pwsh` is not installed and cannot be, the agent may derive the same JSON with any local tool that reproduces the script's extraction and collision rules exactly — the **file format is the contract, the script is the reference implementation.** Everywhere this section says `%USERPROFILE%\.jira-ai-harness\`, read `~/.jira-ai-harness/` on a non-Windows machine.

The script (this is the copy of record — the disk file is a materialization of it):

```powershell
# Generate-ControlCatalogue.ps1 — derive screen -> control-name -> itemId maps from an i21
# module repo's ExtJS source. Heuristic by design: a byName hit is a CLAIM to be confirmed
# on the live form (S1.6d step 5), never driven blind.
# Cross-platform: Windows PowerShell 5.1 AND pwsh 7 on macOS/Linux — hence $HOME (USERPROFILE
# does not exist on Unix) and forward-slash path literals (.NET accepts / on Windows; \ is a
# legal filename character on Unix, not a separator).
param(
  [Parameter(Mandatory=$true)][string]$RepoPath,
  [string]$Branch = '',
  [string]$OutDir = (Join-Path $HOME '.jira-ai-harness/catalogues')
)
$ErrorActionPreference = 'Stop'
# Canonicalize FIRST. The relative-path calculation below trims this prefix off each file's
# resolved FullName, so any difference in FORM between what the caller passed and what the
# filesystem reports silently cuts at the wrong offset: an 8.3 short name (C:\Users\EDELAC~1),
# a trailing slash, a relative path, or mixed separators. Measured: passing an 8.3 path emitted
# "2/universal/packages/..." - the tail of the folder name - for every file in the catalogue.
# Get-Item is the right instrument and Resolve-Path is NOT: measured on the same 8.3 path,
# Resolve-Path.ProviderPath returns C:\Users\EDELAC~1\... unchanged while Get-Item.FullName
# returns C:\Users\edelacruz\... - the long form Get-ChildItem also reports, which is the whole
# point, both sides must be normalized by the same provider.
$RepoPath = (Get-Item -LiteralPath $RepoPath).FullName.TrimEnd('\', '/')
if (-not $Branch) { $Branch = (git -C $RepoPath rev-parse --abbrev-ref HEAD).Trim() }
$sha = (git -C $RepoPath rev-parse --short HEAD).Trim()
$local = Join-Path $RepoPath 'universal/packages/local'
$appDirs = @(Get-ChildItem -Path $local -Directory -Filter '*.Web' -ErrorAction SilentlyContinue |
  ForEach-Object { Join-Path $_.FullName 'src/app' } | Where-Object { Test-Path $_ })
if ($appDirs.Count -eq 0) { throw "no *.Web\src\app under $local" }
$rxDefine = [regex]"Ext\.define\s*\(\s*['""]([\w.]+)['""]"
$rxItem   = [regex]"itemId\s*:\s*['""](\w+)['""]"
foreach ($appDir in $appDirs) {
  $module = (Split-Path (Split-Path (Split-Path $appDir -Parent) -Parent) -Leaf) -replace '\.Web$', ''
  $screens = @{}
  Get-ChildItem $appDir -Recurse -Filter '*.js' | ForEach-Object {
    $src = [IO.File]::ReadAllText($_.FullName)
    $defM = $rxDefine.Match($src)
    if (-not $defM.Success) { return }              # acts as 'continue' inside ForEach-Object
    $class = $defM.Groups[1].Value                   # first define in the file names the screen
    if ($class -notmatch '\.view\.') { return }
    $claims = @{}; $unnamed = New-Object System.Collections.ArrayList
    foreach ($m in $rxItem.Matches($src)) {
      $id = $m.Groups[1].Value
      $start = [Math]::Max(0, $m.Index - 150)       # label/xtype sit near the itemId either side
      $win = $src.Substring($start, [Math]::Min(400, $src.Length - $start))
      $name = $null
      $lm = [regex]::Match($win, "fieldLabel\s*:\s*['""]([^'""]+)['""]")
      if (-not $lm.Success) { $lm = [regex]::Match($win, "text\s*:\s*['""]([^'""]+)['""]") }
      if ($lm.Success) { $name = $lm.Groups[1].Value }
      $xt = ''; $xm = [regex]::Match($win, "xtype\s*:\s*['""](\w+)['""]")
      if ($xm.Success) { $xt = $xm.Groups[1].Value }
      if ($name) {
        if (-not $claims.ContainsKey($name)) { $claims[$name] = New-Object System.Collections.ArrayList }
        $dupe = $false
        foreach ($c in $claims[$name]) { if ($c.itemId -eq $id) { $dupe = $true } }
        if (-not $dupe) { [void]$claims[$name].Add(@{ itemId = $id; xtype = $xt }) }
      } elseif (-not $unnamed.Contains($id)) { [void]$unnamed.Add($id) }
    }
    # Collision rule: a name with more than one claimant is REMOVED from byName and recorded.
    # Ext's own down()/query() silently drives the first match, hidden twins included
    # (Grain.view.Scale declares a visible field set AND a hidden *SE twin) — a false bind
    # is never preferable to a missing one.
    #
    # THE STOLEN-LABEL CASE, which the count rule alone cannot see (measured, SC-9232 dry run):
    # the twin pair often declares the label on the HIDDEN member only — Scale.js gives
    # cboDiscountScheduleSE a fieldLabel while the visible cboDiscountSchedule carries none — so
    # the name has exactly ONE claimant and binds confidently to the control the user cannot see.
    # That is the same false bind arriving by a route the count cannot detect. Whenever a lone
    # claimant ends in `SE` and its non-SE twin exists anywhere on the screen, demote the pair to
    # a collision (visible twin first) and let step 5 resolve it live. 5 names in Grain.view.Scale
    # on 26.2Dev; each one would otherwise have driven a hidden field and reported success.
    $allIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in @($claims.Keys)) { foreach ($c in $claims[$k]) { [void]$allIds.Add($c.itemId) } }
    foreach ($u in $unnamed) { [void]$allIds.Add($u) }
    $byName = @{}; $collisions = New-Object System.Collections.ArrayList
    foreach ($k in @($claims.Keys)) {
      $ids = @($claims[$k] | ForEach-Object { $_.itemId })
      if ($ids.Count -eq 1 -and $ids[0] -cmatch 'SE$' -and $allIds.Contains(($ids[0] -creplace 'SE$', ''))) {
        $ids = @(($ids[0] -creplace 'SE$', ''), $ids[0])
      }
      if ($ids.Count -eq 1) { $byName[$k] = $claims[$k][0] }
      else { [void]$collisions.Add(@{ name = $k; itemIds = $ids }) }
    }
    # Prefix-test before trimming: on a mismatch keep the FULL path. A full path is still usable;
    # a truncated one points nowhere and looks plausible, which is the worse failure.
    $full = $_.FullName
    $rel = if ($full.StartsWith($RepoPath, [StringComparison]::OrdinalIgnoreCase)) { $full.Substring($RepoPath.Length) } else { $full }
    $rel = $rel.TrimStart('\', '/') -replace '\\', '/'
    $screens[$class] = @{ file = $rel; byName = $byName; unnamed = @($unnamed); collisions = @($collisions) }
  }
  if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
  $safeBranch = $Branch -replace '[\\/:*?"<>|]', '_'
  $file = Join-Path $OutDir ($module + '@' + $safeBranch + '.json')
  $out = @{ module = $module; branch = $Branch; commit = $sha
            generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            note = 'heuristic source derivation - confirm every itemId on the live form before driving it'
            screens = $screens }
  # BOM-less UTF-8: PS 5.1's Out-File -Encoding utf8 writes a BOM, and strict JSON parsers reject it
  [IO.File]::WriteAllText($file, ($out | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("catalogue written: {0} ({1} screens)" -f $file, $screens.Count)
}
```

The output file records the `commit` it was derived from. A catalogue is **stale when that commit no longer matches `git rev-parse --short origin/<TARGET_BRANCH>`** for the branch actually checked out — regenerate (seconds, local, free); never hand-edit a generated file.

### 3. When it is generated — in the background, never in the run's way (R-CATALOGUE-BACKGROUND)

**Trigger:** (`APP_REQUIRED = YES` per §1.6b, **or** an `APP_ENV` resolved `alive` per §1.6c step 2) **and** `catalogues\<Module>@<TARGET_BRANCH>.json` is absent or stale for the module repo §1 resolved.

**Action:** spawn a **background agent** whose entire task is step 1 + step 2 (bootstrap if needed, then run the generator against `REPO_PATH` / `TARGET_BRANCH`), and **continue the main run into §1.7 immediately — never wait, never poll.** The gate ordering does the scheduling: the DB and code layers run first anyway, so by the time §1.7a needs the catalogue it is normally on disk. The background agent writes **only under the harness folder** — it touches no repository worktree, no Jira, no database, no browser, and it needs no credentials. If it has not finished when §1.7a starts (or the platform cannot spawn one — run the generator inline then, it is seconds), §1.7a live-probes exactly as before and the catalogue serves the next run. A missing catalogue is a slower run, never a failed one, and **never a STOP**.

### 4. The navigation registry — read from the live shell, merged across runs

The menu cannot come from source (data-driven per licence) and menu anchors cannot be clicked — they are a template in `div.i21-submenus.hidden` that never becomes hittable; the app's own delegated handler calls `iRely.Functions.openMenu(payload)`, so navigation uses the payload, not the anchor. **Capture the payloads the moment §1.7a has a logged-in page** — one `page.evaluate`, a few hundred milliseconds, piggybacked on the session the run already holds (a background agent has no login and never captures this):

```js
// On a logged-in i21 shell. Submenus STREAM IN module by module in the background, so a
// single read can be partial — the file below is MERGED across runs, never replaced.
Array.from(document.querySelectorAll('a.i21-menu-link[data-menu]'))
  .map(a => { try { return JSON.parse(a.getAttribute('data-menu')); } catch { return null; } })
  .filter(Boolean)
  .map(m => ({ label: m.n, screenClass: m.c, module: m.m, type: m.t, menuId: m.mid }));
```

Write to `nav\<envKey>.json` (the §1.6c key) as `{ capturedOn: <APP_BUILD_STAMP>, screens: [...] }`, **merging by (`module`, `label`, `menuId`)** — update an existing row, append a new one, delete nothing. Two facts the consumer must know: the payload's `c` is a **launcher** class, not necessarily the class that renders ("New Ticket" opens `Grain.view.ScaleStationSelection`, what renders is `Grain.view.Scale`) — a hint, never the arrival test; and a module absent from the file may simply not have streamed in yet on any capture so far — absence here is not absence from the licence.

### 5. How §1.7a consumes these files (R-CATALOGUE-FIRST) — the payoff

1. **Extract the screen — never open the catalogue (R-CATALOGUE-EXTRACT, measured 2026-09-07).** These files are **0.5 MB to 1.6 MB each**; the largest is roughly 400k tokens, and reading one costs more than every other layer of the run put together. A single screen's entry is **145 bytes at the median** and 12 KB at the worst, so the slice is four orders of magnitude cheaper than the file that holds it — but only if the file is never opened. Extract by screen name and let it stay on disk:

   ```
   node -e "const c=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(JSON.stringify(c.screens?.[process.argv[2]] ?? null,null,1))" "%USERPROFILE%/.jira-ai-harness/catalogues/<Module>@<branch>.json" AccountsPayable.view.Voucher
   ```

   Forward slashes work on Windows. Repeat once per screen on the ticket's repro path — a few hundred tokens for the whole run. **"Load only the entries" is not a licence to read the file and ignore the rest**: the tokens are spent at the read, not at the attention, and spending them is exactly what this section exists to prevent.

   **Resolve the class name before extracting it (R-CATALOGUE-KEY, measured 2026-09-07).** The keys are exact ExtJS class names and the run is usually holding a screen *label* from the ticket. A guess is silently wrong: `AccountsPayable.view.PayVoucherDetail` returns `null` and the real key is `PayVouchersDetail` — one letter, and the miss is indistinguishable from a screen that was never catalogued. List the candidate keys first — **336 tokens for 28 matches**, measured — and extract the one that matches:

   ```
   node -e "const c=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(Object.keys(c.screens).filter(k=>new RegExp(process.argv[2],'i').test(k)).join('\n'))" "<catalogue>" Voucher
   ```

   Only a **null after a resolved key** is a genuine catalogue miss and falls through to live discovery (step 5).
2. **Navigate by payload:** look the target screen up in `nav\<envKey>.json` and open it via `iRely.Functions.openMenu(payload)`. No menu-hunting through snapshots.
3. **A catalogue hit is a claim, not a fact** — the same discipline R-APP-ALIVE applies to a registry URL. Resolve the control `byName` → `itemId`, then confirm with **one** component query that the itemId exists **and is visible** on the opened form before driving it (an itemId is not unique across the app; a hidden launcher twin satisfies an existence check and swallows every action — always prefer the visible instance).
4. **A name on the collision list is AMBIGUOUS by construction** — resolve it live (visible instance wins), and record which itemId won.
5. **A miss falls back to live discovery** exactly as before this section — and the discovery is **written back** at §1.7a step 7 so it is paid for once.
6. **No catalogue, no nav file → the run proceeds untouched.** These files are an accelerator with a probe in front of every read; they are never a gate, never a STOP, and never an excuse ("catalogue absent" is not a reason to skip §1.7a).

## §1.6e Knowledge base — read what past tickets taught before searching for it again (R-KB-FIRST)

The **i21 JIRA-AI Knowledge Base** (written by `JIRA-AI-Reconcile.md`) holds two layers with opposite truth semantics, and the difference decides how far a hit may be trusted:

| Layer | What it is | How far it may be trusted |
|---|---|---|
| **Earned** — `cases/`, `modules/` | what past tickets taught, with the tickets cited | prior art, exactly like a §1.6 Step 0.1 hit — cite it, and check it the same way |
| **Derived** — `derived/` | an index over the source tree, stamped to one commit | a **pointer**, never a finding. Confirm on this ticket's branch before it enters the analysis |

### 0. Resolve the base — and it is a clone, not a folder that happens to be there (R-KB-RESOLVE, 2026-09-05)

The base is a **git repository**, published private at
`https://github.com/erick-delacruz_irely/i21_AI-JIRAKnowledgeBase`. Resolve its path in this order, and record which source answered:

| # | Source | Notes |
|---|---|---|
| 1 | the `knowledgeBase.localPath` key of `JIRA_AI_CONFIG` | explicit wins, always. **The key is `localPath`** — measured 2026-09-07; a run looking for `path` finds nothing and silently falls through to rung 2 |
| 2 | `<REPO_ROOT>\i21_AI-JIRAKnowledgeBase` | the conventional location beside the module repos — `C:\i21Source\...` on a default install |
| 3 | not present | see below |

**Not present → clone it once, then continue:**

```
git clone https://github.com/erick-delacruz_irely/i21_AI-JIRAKnowledgeBase <REPO_ROOT>\i21_AI-JIRAKnowledgeBase
```

**Present → `git -C <base> pull --ff-only` before the first lookup**, so the run reads what the reconciler last wrote rather than a stale clone. A pull that fails is recorded and the run continues on what is on disk; a stale base is a weaker base, never a broken one.

- **A clone failure is never a STOP** (R-KB-ABSENCE, step 6). No access to the repository, no network, no `git` — record `KB = unavailable (<reason>)`, carry it into the §6.9 `KB-CONSULTED` line as `none (no base)`, and run every gate exactly as a run without a base does. **Do not ask the reporter for anything and do not put this on the Jira**: a missing clone on the analysis machine is our gap, not the ticket's — the same rule as the missing decoder in §1 step 5.
- **Access is per developer.** The repository is private, so a collaborator invite is a one-time operator action per person. Until it lands, that developer's runs are simply base-less, which is the state every run was in before this existed.
- **Never write to the clone** (R-KB-READ-ONLY, step 8) — not a record, not a fix to a record, not a commit. `git pull` is the only write this runbook performs, and it writes only to the working tree.

### 1. What to look up, and with what key

Whatever the ticket already gives you — one keyed extraction each (step 2), before any sweep:

| The ticket gives you | Look in | Returns |
|---|---|---|
| an error code (`80236`) | `derived/_index.json` → `by_error_code` | the **raise sites** (`raised_by`), the module, the `derived` record path, and any past case. **Not the defining function** — measured, no row carries one; the registry function that defines the code appears inside the ~4 KB record, one read later |
| a quoted error message | `derived/_index.json` → `by_message_fragment` | the same, keyed on the sentence a user actually types |
| an object name (`uspICPostInventoryReceipt`) | `derived/_index.json` → `by_object` | its owning module, its `EXEC` callers with counts (**not a caller count — see below**), and every case that touched it |
| a screen (`Inventory.view.InventoryReceipt`) | `derived/_index.json` → `by_screen_namespace` | the screen record, and its server-side objects. **Measured 2026-09-07: this bucket holds exactly ONE key.** It is a route the reconciler has barely populated — expect a miss, and do not spend more than the one lookup on it |
| a module code | `derived/_modules.json` | whether that module has an error registry at all, and how it raises |

**Strip the schema qualifier before an object lookup (R-KB-KEY-CANONICAL).** The index is keyed on the bare object name — measured, **none** of its object keys carries a `dbo.` prefix — while a run that has just read a SQL body is holding `dbo.uspSMCommitListing`. Looking that up exactly returns a **miss**, and a miss is indistinguishable from "nothing was indexed" (R-KB-ABSENCE), so the run shortens nothing and never learns the record was there. `dbo.uspX` and `uspX` are the same object and this one normalisation is explicitly allowed; **nothing else is** — do not stem, truncate or fuzzy-match a name to force a hit, because a neighbouring object's record believed is worse than no record at all.

**`caller_count` is an EXEC count, and it is NOT the blast radius (R-KB-CALLER-COUNT, measured 2026-09-07).** The index resolves callers by matching `EXEC`/`EXECUTE` on a word boundary, which structurally cannot see a scalar function used in a `SELECT` list, a view that references it, or an inline table-valued call. Measured: `fnAPGetVoucherApprovalStatus` carries `caller_count: 0`, and on `27.1Dev` it is consumed by `vyuAPBill.sql` and `vyuAPStraussBill.sql`. **A zero here means "no EXEC site was indexed", never "nothing calls this"** — and a run that sizes the §2.7 blast-radius axis from it reports a regression surface of zero on an object with live consumers, which is the *faster and wronger* failure this section exists to prevent. Read the number as a floor, name it as such, and settle the axis with the `git grep` that axis already specifies. The same caution applies to `caller_modules`: it lists the modules whose EXEC sites were seen, not the modules that depend on the object.

**A row can hit at one layer and miss at the other (R-KB-PARTIAL-ROW).** `tblSMScreen` returns `derived: null` and `caller_count: null` beside a populated `owner_module`, `facts` and `cases` — a table has no component record, but the earned layer still knows things about it. That is a hit at the earned layer and an absence at the derived layer; record it as both, and do not let the null half read as a miss on the whole key.

**Enumerating KEYS is a permitted discovery step; it is not reading the index (R-KB-KEY-ENUM, measured 2026-09-07).** A ticket gives you "the Voucher screen" or "no GL accounts are showing", not an ExtJS namespace or an indexed sentence — and R-KB-KEY-CANONICAL forbids stemming or fuzzy-matching a key to force a hit, which leaves a run with a key it cannot construct and a match it may not make. The way out is to list the **keys** that match a pattern and then extract an exact one:

```
node -e "const i=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(Object.keys(i[process.argv[2]]).filter(k=>new RegExp(process.argv[3],'i').test(k)).join('\n'))" "<base>/derived/_index.json" by_message_fragment "gl account"
```

Measured: **1,284 bytes for 19 matching keys** — the same shape and the same cost as R-CATALOGUE-KEY, and the same discipline. Keys are not records: enumerating them reads names, extraction still reads exactly one row, and **nothing here licenses reading the index**. What stays forbidden is believing a *near* match — enumeration exists to find the exact key, never to substitute a neighbouring one.

**A message lookup does not tell you which layer raised it, and that is the point.** A business rule can be stated in SQL or in the ExtJS client, and the record says which in `stated_in`. Someone quoting an error does not know — so both share one index. **A rule stated only in the client is enforced only in the browser**: it can be bypassed by an import, an API call, or another module writing the same table, which is exactly the shape of a ticket where the rule was violated by *data* rather than by a user.

### 2. Extract the key — never read the index (R-KB-EXTRACT, measured 2026-09-07)

`_index.json` is a lookup table, and it is **532 KB — roughly 130k tokens**, more than most whole runs. `by_message_fragment` alone is 285 KB over 1,437 keys. **Opening it is not the lookup.** A run that reads it spends, on its very first step, precisely what this section exists to save — and "one file read" is the phrasing that invites exactly that mistake, which is why it no longer appears above.

Extract the one key the ticket gave you, and let the file stay on disk:

```
node -e "const i=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(JSON.stringify(i[process.argv[2]]?.[process.argv[3]] ?? null,null,1))" "<base>/derived/_index.json" by_error_code 80236
```

Forward slashes in the path work on Windows; `jq -r '.by_error_code["80236"]'` is the same lookup where `jq` is installed. Substitute the bucket and key the table above names — `by_message_fragment` takes the quoted sentence, `by_object` the bare object name (R-KB-KEY-CANONICAL). **~200 bytes come back, hit or miss**: the record's path, its module, its raise sites. Then read the single file the `derived` path names — about 4 KB — **plus whatever the row's own `facts` and `cases` arrays point at, which steps 4 and 5 oblige you to read.** "Nothing else" means *no other part of the base*, never "ignore the pointers the hit just handed you": the rule corpus behind the index is **1,591 files and 7.0 MB**, and a run touches a handful of them, not one.

**Strip the BOM when the file you parse is a config (R-KB-BOM, measured 2026-09-07).** `%USERPROFILE%\.jira-ai-config.json` is written with a UTF-8 BOM, and a bare `JSON.parse(readFileSync(p,'utf8'))` throws on it — the same idiom works on `_index.json`, which has none, so the failure appears only at base resolution and looks like a missing config. Parse config files as `JSON.parse(fs.readFileSync(p,'utf8').replace(/^﻿/,''))`.

**One extraction already searches every module, so nothing is scoped by module at this rung.** Do not shard the lookup on the ticket's prefix, and do not repeat it per module on a miss: a miss costs exactly what a hit costs, and there is no cheaper subset to try first. The widen that *is* worth doing asks a different question and happens at step 5. Same discipline as R-CATALOGUE-FIRST.

### 3. A derived hit is a CANDIDATE until confirmed on this ticket's branch (R-KB-CONFIRM — mandatory)

Every derived record carries `baseline: { repo, branch, commit, derived }` and a confirm flag — **stored two ways, and anything parsing it must accept both**: the index row carries `"confirm_on_target_branch": true` (boolean), the record's own front-matter carries `confirm_on_target_branch: required` (string). Same instruction, two spellings. **The whole base is stamped `26.3Prod`.** Bodies differ across branches — 4,749 objects differ between `24.2Dev` and that baseline — so a hit describes what the object looks like on `26.3Prod`, which may not be the line this ticket is on.

Confirm before the hit enters the analysis: one `git grep` for that code or message text on `TARGET_BRANCH`, resolved through `refs/remotes/origin/<branch>` (a bare branch name reads a stale local shadow — `24.2Dev` sat 290 objects behind its remote). One file read, replacing the repo-wide search this section saved.

**An object key has no code and no message, so it confirms differently (R-KB-CONFIRM-OBJECT).** Grep the **path** the `derived` record names to prove the object exists on this branch, then grep the **specific literal or statement the record claims** to prove the claim does too — two greps, not one, because an object that exists on the branch tells you nothing about whether it still does what the record says. A record claiming a binding at named line numbers is confirmed by the binding, never by the line numbers, which drift.

**The `repo` label in a record is not a directory (measured 2026-09-07).** Records stamp `repo: i21_Liquibase` while the clone on a default install is `C:\i21Source\Liquibase` — no `i21_` prefix. Resolve the working copy by finding the `derived` path inside it (`logic/stored-procedures/<object>.sql` resolves exactly), not by pasting the label after `C:\i21Source\`.

**A record describing a defect that has since been FIXED can never pass a tip grep, and that is a verdict, not a failure (R-KB-ALREADY-FIXED, measured 2026-09-07).** The base records what a defective body looked like; the branch holds the corrected one. Measured on IC-29794: the base is stamped `26.3Prod` and derived 2026-09-04, the fix merged to that same branch on 2026-08-27, and the statement the record blames — the transfer-order `CASE` on `intTransferorId` — is simply not on the tip. Read literally, the rule above then marks a **completely correct hit** `unconfirmed` and forbids it from the RCA. **Three outcomes, not two:**

| Tip grep | History (`git log -S "<statement>"` on the branch) | Verdict |
|---|---|---|
| present | — | **confirmed** — the pointer holds, it enters the analysis |
| absent | the statement was there and a commit removed it | **already fixed on this branch** — not an unconfirmed hit. Name the commit, and take it to §1.6 Step 0 / Step 0.1, which is where an already-resolved ticket is decided |
| absent | no commit ever carried it | **unconfirmed** — the record describes a body this branch never had, and the clause below applies |

A grep that fails without the history check cannot tell the second row from the third, and they are opposite findings — one says the work is done, the other says the record is wrong about this line.

**An unconfirmed derived hit must not appear in the RCA as a finding.** Using one without confirming makes the analysis faster *and* wronger, which is worse than not having the base at all.

### 4. An earned hit is prior art, and feeds Step 0.1 rather than replacing it

A `cases/` or `modules/` record cites the tickets that taught it. Treat it as §1.6 Step 0.1 output: cite the ticket, read the ticket, and hold it to the same standard as any other prior art. A fact carries `status` (`verified` / `unverified` / `refuted`) and `confidence` (a count of independent corroborations, 0–3).

**A `refuted` fact is kept on purpose.** It records a trap someone already fell into — read it as "this was tried and it was wrong", never as a suggestion.

**The strongest prior art is often not in the base at all — it is a pushed fix branch (R-KB-CODE-PRIOR-ART, measured 2026-09-07).** `cases/` holds eight tickets; the code repositories hold every `<branch>_<JIRA>` branch anyone ever pushed. Before concluding the base is silent on a ticket, run `git log --all --grep="<JIRA>"` and `git branch -r | grep <JIRA>` in the candidate repository — on AP-24914 that is where the real fix was, and the base held nothing. **Read the diff, not the commit message.** That commit's own message named the wrong route — it cited the GL `searchcoa` endpoint while the failing projection was the AR namesake of the same name — and a run that trusted the sentence instead of the changed lines would have chased the wrong view.

### 5. The base is read a SECOND time, at remedy design (R-KB-REMEDY)

Steps 1–4 read the base to find the **cause**, keyed on what the ticket gave you — an error code, a message, an object, a screen. That is one of the two questions the base can answer, and it is not the one the graded corpus says runs get wrong. **Read it again at §2.7, keyed on the objects the candidate remedies would touch**, before a remedy is selected:

| Fact kind | What it decides at §2.7 |
|---|---|
| `constraint` | a rule the module imposes on any change to these objects — the axis IC-29836 failed. **Unresolved on a table the remedy writes to, it is a STOP** (§2.7 step 2, R-MODULE-STANDARD) |
| `conventions` | how this module does this kind of fix — person-owned, prescriptive, and the closest thing to a stated house style for a remedy |
| `known-gap` | a defect already reported and left open on these objects. A remedy landing next to one either closes it or says why not |
| `mechanism` | **what the system actually does to the value a candidate would set** — the kind that decides durability. Measured on AP-24915: the fact that an SM-owned deploy sync rewrites `tblSMScreen.strScreenName` on every build is `kind: mechanism`, and it is the whole reason the data patch could not hold |
| `coupling` | who else binds to the thing a candidate changes — the kind that sets the COVERAGE denominator. On the same ticket it named three consumers binding by display name, so a one-object fix closes 1 of 3 |
| any fact with `status: refuted` | an approach already tried here and found not to hold. **A refuted fact matching a candidate rules that candidate out**, and selecting it anyway carries the §2.5 `NOVEL-JUSTIFIED` burden |

**Read every fact the candidate objects point at, not only the kinds listed above (R-KB-ALL-KINDS, measured 2026-09-07).** The table says what each kind *decides*; it is not a filter. Two blind runs of this step on AP-24915 found that the only two facts in play were `mechanism` and `coupling` — neither was listed, and between them they ruled out one candidate and trebled another's coverage denominator. A run that filtered on the table would have read nothing and recorded `none found`. **A fact's `kind` tells you which axis it feeds, never whether to read it.** What `constraint` alone still controls is the STOP: only an unresolved `constraint` on a written table stops a run (R-MODULE-STANDARD); every other kind scores an axis.

**The `cases/` layer is part of this read (R-KB-CASE-AT-REMEDY).** Object rows carry a `cases` array, and a graded case record is where a remedy of this shape is recorded as having already failed — on AP-24915 the earlier run's patch is graded `WRONG AS REMEDY — cannot hold past the next build`. **A claim graded wrong in a case record rules a matching candidate out exactly as a `refuted` fact does**, and for the same reason: the difference between the two is which file someone happened to write it in, not how firmly it is known.

**A case record for the ticket UNDER ANALYSIS is not independent corroboration (R-KB-SELF-CITE).** The base may already hold a graded record of an earlier run of this same ticket — the AP-24915 facts cite AP-24915 among their sources, so part of their `confidence: 3` is this ticket agreeing with itself. Read it, cite it, and let its **dev-review corrections** carry full weight; they came from outside the run. But never count the run's own earlier conclusion as a second source confirming the first, and say in `KB-CONSULTED` that the case is this ticket's own.

**The module whose rules bind is the OBJECT's owner, not the ticket's prefix (R-KB-WIDEN, 2026-09-07).** Step 5's question is *whose house style governs this change*, and the answer is not settled by the Jira key. `by_object` carries `owner_module` and `caller_modules` for every indexed object, and §1.7d routinely names a writer in another module — on the ticket that gate was built from, the writer is another module's deployment sync. So read in this order, and stop at the first rung that answers:

1. **The ticket's module.** Its `constraint`, `conventions`, `known-gap` and `refuted` facts, for the objects the candidates touch.
2. **Every other module a candidate object actually implicates — by name.** An `owner_module` that differs from the ticket's prefix, a `caller_modules` entry the blast-radius axis already counted, or the §1.7d writer's module. Read that module's facts the same way and satisfy its constraints the same way. A remedy is reviewed by the people who own what it writes to.
3. **Nothing found at either rung → the usual routine** (R-KB-ABSENCE): `MODULE-STANDARD: none found`, and the run continues to §2.7 step 2 on its own reading.

**Widen by name, never by sweep.** A second module qualifies only when the run can point at the evidence that named it. "Nothing in the ticket's module, so read the other 31" is a scan across **32 module directories and 1,591 rule files**, on a miss rate that is high by construction — it costs more than the sweep it was meant to shorten, and it returns nothing the run could act on. **Each module actually consulted gets its own entry in the §6.9 `KB-CONSULTED` block**, so a run that widened and found nothing stays distinguishable from a run that never widened.

Same trust rules as everywhere else in this section: an **earned** record is prior art to cite and check, a **derived** record is a pointer to confirm on this branch (R-KB-CONFIRM), and a **miss means nothing was indexed** (R-KB-ABSENCE) — never that the module has no convention. The cost is one extraction per candidate object, against a fix direction that is otherwise chosen from the run's own reading alone.

### 6. Absence is never a signal (R-KB-ABSENCE)

The base indexes **one branch of 6,216** in `i21_Liquibase`, **none** of `SqlScripts` (which serves every 22.x/23.x customer), and its earned layer is a handful of tickets. A miss means nothing was indexed — never that the object is fine, the rule does not exist, or nobody has seen this before. **Do not shorten a sweep because the base was silent.**

**Some defects have no SHAPE the base could hold, and probing for them is wasted (R-KB-NO-SHAPE, measured 2026-09-07).** Coverage is not the only kind of absence. Every bucket is keyed on a SQL object, a raised message, an error code or a screen — so a defect that lives in the **contract between repositories** has no bucket at all. Measured on AP-24914: the fault is a view in `i21_Liquibase` not exposing four columns that an ExtJS control in `i21_generalledger` asks for, projected by a helper in `i21_GlobalComponentEngine`; the base returned `null` for every candidate object and holds no bucket shaped like *"which columns does this screen ask of this view"*. That is not a reconciliation gap — no amount of indexing this base fills it. **One lookup per key the ticket gives you, then go to the repositories.** A run that keeps re-probing the base for a cross-repo, cross-layer or contract-shaped question is spending lookups on a question the base cannot be asked.

**A miss at the object rung disables the step 5 widen, and the run must notice (R-KB-WIDEN, step 5).** The widen reads `owner_module` off the object row. When that row is `null`, there is no owning module to widen *to* — the routing metadata is missing, not just the facts. Record `KB-CONSULTED: … = none (no key matched)`, settle ownership from the repository the object actually lives in, and do not read the silence as "this module owns it". Measured on AP-24914, whose fix landed in an **AR**-owned view under an **AP** ticket — precisely the case the widen exists for, and precisely the case the base could not route.

### 7. No base, no lookup → the run proceeds untouched

An absent, stale or unreadable base is a slower run, never a STOP and never an excuse to skip a sweep. Every gate in this runbook stands on its own; this one only makes some of them cheaper.

### 8. This runbook never writes to the base (R-KB-READ-ONLY)

One writer per surface: `JIRA-AI-Reconcile.md` writes the base, this runbook writes Jira and the code repositories. A run that learned something does not edit a record — it states the claim in the §6.9 `KNOWLEDGE-DRAFT` block, names the records it read in `KB-CONSULTED`, and the reconciler grades both against what actually merged and what the developer said.

## §1.7 Database acquisition & local restore (SQL Server) — run when FEASIBILITY = DB_REQUIRED-ACTIONABLE (or -BLOCKED once a backup arrives)

Purpose: get a restorable copy of the **reported** database onto the local SQL Server, bring it to the branch's schema level, and use it to (a) reproduce the symptom, (b) prove the root cause, and (c) satisfy §3's dev-DB validation mandate.

**Configuration — `SQLSERVER_CONFIG` (the `sqlServer` section of `JIRA_AI_CONFIG` = `%USERPROFILE%\.jira-ai-runbook-config.json`):**

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
- **No ledger, no registry file, no DB log is maintained.** This runbook writes NO tracking file, index, or log of databases, restores, or servers. Reuse is discovered **fresh each run from live evidence** — the ticket, its siblings, the HD ticket's `Database Copy` tab, and a live `sys.databases` query against the configured `knownServers`. The `knownServers` entries in `%USERPROFILE%\.jira-ai-runbook-config.json` are operator-maintained connection details, not a run-written ledger; the runbook never appends to them. **This rule governs databases, restores, and servers — it is not a blanket ban on the runbook writing its own config.** The single deliberate exception is the `appEnv` node (§1.6c, R-APP-ENV-REGISTRY), which *is* run-written; §1.6c step 4 sets out why an app environment earns a registry when a restored database does not.
- **Never publish local restore details to Jira.** A database restored on the **local workstation / local (Philippines) server** is a private working copy that nobody else can reach — its server name, database name, path, and connection details MUST NOT appear in any Jira comment, RCA, PR, or Confluence page. Record it in the **run output only**. Only a DB on a **shared** server that the team already knows about may be referenced in a comment, and then only by the server/database name the ticket or HD ticket already uses.

**R-DB-PROVENANCE — a comment that cites database evidence MUST say which database it came from (operator 2026-08-18, ref AP-24877).** "No ledger" governs what this runbook **stores**; it never licensed a terminal comment whose evidence cannot be traced to a database. The run output dies with the session, so the comment is the only durable record of which copy was executed against — and on a ticket carrying several DB-bearing HD tickets, `a restored copy of the <customer> database` identifies none of them. State the provenance at the maximum granularity the constraint above permits:
- **Shared `knownServers` database → name it:** `<server> / <dbname>` plus `DB_BUILD_VERSION`. The bullet above *permits* this; this rule makes it **required**. A shared copy is reachable by the reader, so withholding its name costs them the ability to verify the work — and, where a database request is still open on the ticket, the ability to close it.
- **Local restore → never the server or database name** (the constraint above is absolute), but always the **acquisition source**: which HDTN's `Database Copy`, which Jira attachment, which link, or `knownServers sys.databases sweep`; plus `DB_BUILD_VERSION`, and the snapshot date whenever the backup or database name encodes one.
- **More than one DB-bearing HDTN on the ticket → say which one supplied the copy.** A `DB Copy` HDTN and a later `Database request` HDTN are different suppliers with different dates. When §1.7 step 0 found the database by registry sweep and it cannot be tied to any HDTN the ticket lists, write exactly that — `restore source not traceable to a listed HDTN` — and **never** a speculative `may satisfy HDTN-<n>`: a guess about the provenance of your own evidence is worse than an admission, because it invites a reader to close an open database request on the strength of it. (AP-24877 carried HDTN-513390 / 513414 / 513880, cited a restored Huels Oil Company copy on a shared AP server, named neither the server nor the database though both were permitted, and then speculated that the copy "may satisfy" the open request in HDTN-513880.)

**R-DB-CANDIDATE-SET — rank the candidates to pick a primary, and KEEP the rest (operator 2026-08-18, ref AP-24877).** §1.7 step 0 used to commit to the **first** candidate that cleared the acceptance gate and skip the remaining sources, which made "which database did we use" a side effect of scan order rather than a decision. The gate is a per-candidate **filter**, not a comparator: it never takes a second candidate as input, so two copies that both pass are indistinguishable to it. Two changes:

**1. Enumerate before committing.** Complete the whole step-0 scan — description, comments, environment field, siblings (§1 step 7a), and every HD ticket's `Database Copy` tab — and gate **every** candidate it produced, before selecting one. Then rank, most significant key first:
1. **Contains this ticket's reported artifact** (gate check 3). The only one of the three checks that asks about *this* ticket, so it outranks the others.
2. **Newest snapshot** among those that do — by the date encoded in the database/backup name, else the HD ticket's restore date.
3. **Shared `knownServers` over a local restore** — a shared copy costs no restore slot (R-DB-SLOT-LIMIT) and no download.
4. **The HDTN the ticket names most recently**, as the final tie-break.

Set `RESTORE_DB_NAME` and `DB_PROVENANCE` from the winner, and record the ranked set — **including what was rejected and why** — so the comment can say what the primary was chosen *over*. A disclosed choice is auditable; a disclosed accident is not.

**2. A rejected candidate is NOT discarded — it is retained as evidence (this is the half that matters for triage).** The candidate set is a series of snapshots of the same environment **at different dates**, and that time axis is itself diagnostic. Newest is the right default primary because it most likely holds the reported transaction; it is also the copy most likely to have **lost** the evidence — rows get purged or archived, and above all **the customer's own workaround overwrites the defect**. AP-24877's documented workaround is *"manually override the tax amount to zero on each voucher"*: in a snapshot taken after that, the wrong value is gone and the row looks correct, while an older copy still holds the defect intact. Concretely:

- **Absence from the primary is not absence.** Before recording `NOT-REPRODUCED-TXN-ABSENT` (§1.8 Axis A), look for the reported artifact in **every other candidate, oldest included**. That verdict is only honest once the whole set has been checked, and it must name the snapshots checked and their dates.
- **The same record in an older snapshot is not an analogy.** §1.8 forbids substituting a *similar* record for the reported one (`ANALOGY`). Reading the **same** document at an earlier date is a different act — the same artifact, earlier in time — and it is legitimate primary evidence. Label it `CROSS-SNAPSHOT (<db> @ <date> — consulted for <question>)`, never `SUBSTITUTE-DB` (which is for a primary that is not what the ticket supplied) and never silently.
- **A dated pair is a third reproduction axis: _when_ did the value become wrong.** §1.8's axes answer *does the reported transaction fail* and *can it still happen tomorrow*; two snapshots answer *when it started*. Right in the older copy and wrong in the newer → the bad write happened between those dates, which bounds §3.8 `DEFECT_ORIGIN` to a window and, by comparing each copy's `tblSMBuildNumber`, names the build that wrote it. Wrong in **both** → the defect predates the older snapshot, and the customer did **not** hand-correct that row.
- **It calibrates the §3.11 affected-data sweep.** A row wrong in the newer copy but right in the older is a row the defect broke *in that window*; a row right in the newer but wrong in the older is a row **someone already fixed by hand** — which must not be counted as needing the data fix. Without the older copy those two are the same observation, and the sweep's count is wrong in both directions.

**Cost discipline — consulting the set must not multiply restores.** A secondary candidate on a **shared** server is read-only and free: query it directly, it occupies no slot. A secondary that would need a **local restore** is NOT restored speculatively — only when a specific, named question needs it (a `NOT-REPRODUCED-TXN-ABSENT` about to be recorded, an unbounded `DEFECT_ORIGIN`, a sweep count that hinges on hand-corrections), and then through the normal slot pool, `DB_QUEUED` if both slots are full. Never restore a second copy "just in case"; never drop a copy this runbook did not restore.

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
- **Restore known to exist but server unnamed** (e.g. only "database restored" on the HDTN): sweep the `knownServers` registry itself — run the `sys.databases` name search (customer/JIRA pattern) on each registered server before falling through to acquisition (operator 2026-08-06). Record which server matched in the run output **and set `DB_PROVENANCE` so the terminal comment can carry it (R-DB-PROVENANCE)** — a database found this way is by definition not traceable to any HDTN the ticket lists, and the comment must say so rather than imply a restore note produced it. Same acceptance gate applies.
- **R-DB-COLD-SWEEP — the ticket supplies NO database evidence at all: sweep anyway, and say so (operator 2026-08-28, ref SC-9232).** The two bullets above both start from evidence — a restore note that names a server, or one that names none. The commonest case on a QC ticket has neither: no `.bak` attachment, no link, no HDTN `Database Copy` tab, no restore comment, nothing. That is **not** a reason to skip step 0. It is a **cold sweep**, and it is mandatory before any `DB_REQUIRED-BLOCKED` verdict and before any database line in an information request:
  1. **Run it.** `SELECT name FROM sys.databases` against every `knownServers` entry, matched on the ticket's **Customer** field (`customfield_10038`), its environment, and the JIRA key — the same name search the bullet above uses. A shared copy of the reported customer at the reported major version very often already exists because another team restored it for another ticket, and finding it turns a `DB_REQUIRED-BLOCKED` STOP into a run that can actually read data. This is module-agnostic: the sweep matches on customer and version, never on the module the JIRA belongs to.
  2. **Gate it exactly the same way.** All three acceptance checks below apply unchanged. A cold-sweep candidate has no restore note vouching for it, so the gate is the *only* thing standing between it and a wrong-database analysis.
  3. **A cold-sweep candidate is never "this ticket's database", whatever the gate says.** The ticket supplied nothing, so there is nothing for it to be *the same as*. At best it is a copy of the same customer at the same major version, which makes it good for **orientation** — enumerating the validations reachable on the reported path, reading `tblSMBuildNumber`, running the §1.7b deployed-object fidelity diff, checking `tblSMErrorLog`, and establishing whether the reported artifact *shape* exists in that environment at all — and never, on its own, proof of the reported failure.
  4. **Label and provenance are fixed, not improvised.** Set `DB_PROVENANCE = knownServers cold sweep — no database supplied on the ticket (<server>/<dbname>, build <DB_BUILD_VERSION>, snapshot <date or "undated">)`. Gate passed → usable as primary, labelled `COLD-SWEEP-DB`. Gate check 3 failed (the reported artifact is absent) and it is the only candidate → it is **not** discarded: retain it, label it `SUBSTITUTE-DB-COLD`, and carry that label into §1.8 and into the terminal comment. §1.8's ordinary `SUBSTITUTE-DB` label cannot express this case — its sentence is `<what was used> instead of <what the ticket supplied>`, and here the second half is empty, which is exactly how a copy the run found for itself ends up narrated as though the ticket had provided it.
  5. **Disclose the sweep even when it finds nothing.** `cold sweep: <n> knownServers entries scanned, no <customer> database found` is a required line in the run output **and** in the information request. A database request that does not say we already looked reads as though we had not.
- **ACCEPTANCE GATE — a candidate is not this JIRA's database until ALL THREE checks pass (operator 2026-08-10).** `sys.databases` name-existence proves *a* database is there, not that **this ticket's data** is in it. Every candidate reached through §1 step 7a was restored for a DIFFERENT ticket, frequently from a different environment and months apart (ref AP-23288: candidate `WAMA01_0803DAN`, an Aug-3 snapshot harvested from AP-22786 whose environment field reads `Hypercare01` / `Prod01`, while AP-23288's own environment field is EMPTY and its defect was reported 2026-03-12).
  1. **Environment agreement** — the sibling's environment must match the subject ticket's. This is the §1.6 `DB_REQUIRED-ACTIONABLE` test ("a reachable backup of a DIFFERENT company/environment does NOT qualify", ref AP-24402) made operative at the point of reuse; a candidate rejected here leaves the §1.6 verdict at `DB_REQUIRED-BLOCKED`. Subject environment EMPTY and the customer has exactly ONE known environment → accept. Subject EMPTY and the customer has MORE THAN ONE → do **not** guess: record `step-0 DB rejected: environment ambiguous (<list>)` and fall through to step 1.
  2. **Snapshot age vs the reported defect** — when the database NAME encodes a date (the `WAMA01_0803DAN` = 2026-08-03 pattern is common; also `_MMDD`, `_YYYYMMDD`, and `_<initials>` suffixes), compare it against the date the defect was reported. **Snapshot predates the report → reject on that basis:** record `step-0 DB rejected: snapshot <date> predates reported defect <date>` and fall through to step 1. The transaction that demonstrates the bug cannot be in a copy taken before the bug was reported, so letting check 3 discover this instead yields a bare `repro data absent` that hides the real reason. Name carries no parseable date → skip to check 3 and let the query decide.
  3. **Repro-data presence** — run ONE query proving the subject ticket's *own* reported artifact is present (for AP-23288: a posted Cash Refund inside the reported window). Present → accept, recording the query and its row count in the run output. Absent → record `step-0 DB rejected: repro data absent` and fall through to step 1. Never carry an ungated candidate into the step 3 BEFORE run, where a non-reproduction gets misread as "the hypothesis is disproven" when the truth is "wrong database".
  All three pass → this candidate is **usable**. Do **not** stop here: finish gating every other candidate the scan produced, then rank them and select the primary per **R-DB-CANDIDATE-SET** — set `RESTORE_DB_NAME` and `DB_PROVENANCE` from the winner, retain the rest as the dated snapshot series, and skip steps 1–2 entirely. A rejection is not a dead end either: it means this candidate is unproven as the *primary*, and it stays in the set — a copy that fails check 3 for lacking the reported artifact is exactly the copy that may still hold the pre-workaround value (R-DB-CANDIDATE-SET). Only when NO candidate is usable does the run continue down the normal acquisition path.
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

**1. Acquire the backup (in priority order — cheapest first; the staged-archive check leads because a re-download of data already on disk costs hours, R-DB-KEEP-ARCHIVE):**
1. **Already staged locally — ALWAYS check first, before any download (R-DB-KEEP-ARCHIVE).** An archive in `backupStageDir` whose name matches the customer/JIRA/cohort (record which file + its date in the run output). Because slot release now keeps every archive, a cohort processed earlier in the same batch — or in any earlier run — has usually left its archive here, making a re-restore a local extract instead of a multi-gigabyte download. Treat a retained archive exactly like a freshly downloaded one: it still faces the §1.7 step 0 acceptance gate on environment agreement, snapshot age, and repro-data presence, and the step 2.6 version check. A stale archive is a candidate, never an authority.
2. **Jira attachment** — a `.bak` / `.zip` / `.7z` / `.rar` attachment on the issue. Download exactly like §1 image attachments: the Atlassian MCP is 403-blocked on attachment content, so use the API token from `~/.atlassian-token` (`curl -sL -u "<email>:<token>" -o <file> "https://irely.atlassian.net/rest/api/3/attachment/content/<id>"`). Stage into `backupStageDir`.
3. **Link in the ticket** — a SharePoint/network-share/Azure-blob/helpdesk (HDTN) URL in the description, comments, or the **environment field** (ref AP-23349: a `.bak` Azure-blob link with a long-lived SAS token sat in the environment field — common pattern otherwise: a `DB-` line in the description). Download to `backupStageDir`.
   - **SharePoint link + `sharepoint` section configured** → download it directly, using `sharepoint.cookie` as the `Cookie` header. Send the cookie **only** to the host in `sharepoint.tenant`; never to a redirect target on another host (a redirect to `login.microsoftonline.com` means the cookie is stale, not that it should be forwarded there). A response that is HTML rather than the expected binary is a sign-in page, not a backup — treat it as an expired cookie, record the gap, and fall through to asking the operator. Never write the cookie into a log, a Jira comment, or the run output.
   - **Cookie missing or expired** → say so in one line (`sharepoint cookie expired — .bak not fetched; refresh with Setup-JiraAiFix.ps1 -Section sharepoint`) and ask the operator to fetch that one file. Never a STOP on its own; it only removes this acquisition route.
   - **Any other link that needs interactive auth** → ask the operator to fetch it.
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

Resolve the `strVersionNo` you read here through **§1.5a (R-BUILD-RESOLVE)** as well as comparing it on main.major: the release list names the branch that produced that exact build and when it was built, which is strictly more than main.major can tell you — and it is what distinguishes a `26.3DevSucafina` database from a `26.3ProdSucafina` one, where main.major is identical.

```sql
SELECT TOP 1 strVersionNo FROM tblSMBuildNumber ORDER BY intVersionID DESC;
```
- `DB_BUILD_VERSION` = that value (e.g. `24.2.0803.1622`). Take its **main and major** components only — `24.2`.
- Compare against `TARGET_VERSION` (the numeric prefix of TARGET_BRANCH — `24.2` from `24.2Prod`, `26.3` from `26.3DevCTRMFeatures_Sucden`). **Match on `<main>.<major>` ONLY** — build and revision (`.0803.1622`) are expected to differ and are never compared. A customer DB is always some builds behind the branch; that is normal.
- **Match** → continue; record `DB version <DB_BUILD_VERSION> ≈ branch <TARGET_VERSION> (main.major match)` in the run output.
- **Mismatch** (e.g. DB `22.1.…` against branch `24.2Dev`) → **STOP** and report `DB-VERSION-MISMATCH (db <main.major> vs branch <main.major>)`. Do not analyze, do not fix, do not run a data fix against it: the schema and the code disagree, so every BEFORE/AFTER result would be meaningless and any data fix would be written against the wrong shape. Post the §6.5 D triage comment naming both versions, so the operator can request the right backup or correct TARGET_BRANCH.
- `tblSMBuildNumber` missing/empty → record `DB build version not determinable` and continue for a read-only reproduction, but treat it as a **hard STOP for `ISSUE_CATEGORY = DATA_FIX`** (§3.6 requires the build stamp for the template's `@strCurrentBuildNo` compatibility guard).

**3. Root-cause PROOF algorithm (BEFORE/AFTER — this is what turns "plausible" into "proven"):**
1. Script the reproduction from the EVIDENCE_SET — the exact documents/values named in the ticket (worked example, AP: `EXEC uspAPPostBill @billId = <the reported voucher>`, or the report view filtered to the reported document numbers).
2. **BEFORE:** run the reproduction on the restored DB with the pre-fix code/objects → capture the output. It MUST show the reported symptom. If it does NOT reproduce → the hypothesis is disproven; return to §1.6 (possibly INFO_REQUIRED — the ticket's evidence was insufficient or the environment differs).
3. Apply the code fix (§3) and deploy it to the restored DB (`liquibase update` for SQL objects).
4. **AFTER:** re-run the *identical* reproduction → capture the corrected output.
5. The BEFORE/AFTER pair is the proof: BEFORE = Root Cause evidence, AFTER = Acceptance Verification evidence (§6). Include the concrete query + both result sets (or row counts/values) in the §6 comment.

STOP conditions:
- `SQLSERVER_CONFIG` missing → STOP (one-time operator setup).
- Restore fails (disk space, corrupt backup, version mismatch — e.g. backup from a newer SQL Server than local) → STOP and report the exact restore error; ask the operator whether to upgrade the local instance or request a compatible backup.
- Backup unobtainable → INFORMATION REQUEST comment (§1.6) → STOP.
- `DB-VERSION-MISMATCH` at step 2.6 (main.major differ) → STOP with the §6.5 D triage comment.

## §1.7a Runtime reproduction on a resolved app environment (R-RUNTIME-REPRO) — OPTIONAL, only when an APP_ENV resolved alive (§1.6c)

**This runbook never provisions, builds, deploys, or configures an i21 application environment.** §1.7a runs only against an environment that already exists and that **§1.6c resolved and probed alive** — from the operator's parameter, from this ticket, or from the `appEnv` registry — and it exists for one purpose: to reach the symptoms SQL alone cannot prove — screen behavior and field state, ExtJS/UI defects, document/PDF rendering, and the exact client-side error text.

**TRIGGER:** an `APP_ENV` **resolved and probed alive per §1.6c** (parameter, ticket, or `appEnv` registry) AND (`FEASIBILITY = APP_REQUIRED-ACTIONABLE` per §1.6b, OR the EVIDENCE_SET contains a UI-level, render-level, or HTTP-level symptom). Otherwise skip.

**Session — headed once, headless thereafter (runs before step 1).** Work from the `appEnv` entry §1.6c resolved and probed — creating it there first if this environment came off the ticket rather than out of the registry. If its `storageState` file exists and is still valid, launch Playwright **headless** with that state and skip straight to step 1. Otherwise launch **headed**, let the operator complete the login (SSO/MFA included — never automate around it, never brute-force, never guess), then persist `context.storageState()` to the path named in the config, **outside every repository** (user profile, same rule as `sqlServer.password`), record that path and its `obtainedAt` on the entry (§1.6c step 3), and continue headless from there. A login redirect on the first navigation of a later run *is* the expiry signal — re-run the headed capture; do not retry the headless one. Pin an explicit viewport (`1920x1080`, `deviceScaleFactor 1`) so screenshots are comparable across runs, and wait on ExtJS component/store readiness rather than on fixed sleeps. **Headless is the default; headed is the fallback for render-class symptoms** (§1.6b A4 — layout, font metrics, print CSS, PDF generation), where headless Chromium can legitimately differ from what the user saw: re-check those headed before grading anything.

**Concurrent runs — every run drives its OWN browser (R-BROWSER-ISOLATION, operator 2026-09-08).** Two JIRAs worked at the same time are two runs, and on a developer machine that means two agent sessions reaching for the same Chromium. A Playwright MCP server started without flags runs in **persistent-profile** mode on one fixed user-data-dir, and Chromium single-instances that directory: the second run either fails to launch or — far worse — silently steers the browser the first run is already driving, at which point its console, network trace and screenshots are somebody else's evidence and nothing says so.

- **Launch, never attach.** This section's browser is launched by the run itself — a non-persistent `chromium.launch()` plus a fresh `newContext({ storageState })`. Never a persistent profile, never a shared user-data-dir, never a browser this run did not start. Two runs are then two OS processes with no lock between them, and both work. When the only reachable browser is a shared one, it is **claimed under the lease below**, never assumed free.
- **The saved session file is read-shared, write-exclusive.** Replaying `storageState` is a read — any number of runs may do it at once. The headed re-capture is a **write**: hold the lease, write to a temp path in the same folder, then atomic-rename over the target. A half-written session file breaks every later run on that environment, not just this one.
- **Same environment, same login → the second run defers, and says so (operator 2026-09-08).** i21 may single-session a user, so a second login on the same `<envKey>` silently invalidates the first run's replay — which reaches that run as a spurious login redirect and sends it into a wrong headed re-capture. A run that finds the `<envKey>` lease held therefore does **not** log in beside it. It records `app layer deferred — <envKey> held by <JIRA> since <time>; will run once released`, **reports that line in the run output so the operator knows the app layer is queued rather than skipped**, continues into every other layer meanwhile, and **re-claims the lease and runs this section when the holder releases**. Deferral is not a skip. Different `<envKey>`s never wait on each other — different environments, different logins, different browsers, full parallelism.
- **The lease.** `%USERPROFILE%\.jira-ai-harness\locks\<envKey>.lock`, holding the JIRA key, the PID and a timestamp. Taken before the session is opened, released at the end of §1.7a / §1.7c on that environment **including on failure**. A lease whose PID no longer exists, or whose timestamp is older than 30 minutes, is **stale**: break it and record that it was broken and who held it. The wait is bounded — if the holder has not released by the time every other layer is exhausted, record `app layer NOT run — <envKey> held by <JIRA> for <duration>` and grade the run on the layers that did execute. **Never a STOP:** a queued app layer is a slower run, never a failed one.
- **The two merged files are write-exclusive as well.** `nav\<envKey>.json` (§1.6d step 4) and the `appEnv` write-back (§1.6c step 3) are both read-modify-write, and two runs finishing together lose one run's merge in silence — the exact discovery both sections exist to stop paying for twice. Take the same lease (`locks\nav-<envKey>.lock`, `locks\config.lock`), read, merge, write to a temp file, atomic-rename. A lock that cannot be taken means the merge is **recorded as skipped, never forced**.
- **Evidence is written to the session scratch directory, keyed by `<JIRA>`** — the placement rule §1 step 5 already applies to decoded video frames covers this section's screenshots, traces and console dumps too. Two runs capturing `screenshot.png` into one folder is the same collision one layer down, and it is the layer where the evidence actually gets swapped.

1. **Version validation (fail-closed on the evidence, not on the run).** Resolve `APP_ENV_VERSION` from the running app (login/about page, or the version stamp the environment exposes), and record the **full four-part stamp** verbatim as `APP_BUILD_STAMP` — §1.7c step 2 needs all four parts, and this step is about to truncate it. It MUST match, on **main.major only**:
   - `TARGET_VERSION` (the branch being fixed), AND
   - `DB_BUILD_VERSION` from §1.7 step 2.6 (the database the app is pointed at), when a DB is in play.
   Mismatch → **discard everything observed on that environment**, report `APP_ENV version <x> ≠ DB <y> / branch <z> — runtime evidence discarded`, and continue the run on code + DB evidence alone. An environment on the wrong build reproduces (or fails to reproduce) somebody else's bug.
2. **Reproduce** with Playwright driving `APP_ENV`: follow the ticket's repro steps to the failing action, **resolving every menu and control through the §1.6d harness files first (R-CATALOGUE-FIRST)** — open screens via `iRely.Functions.openMenu` with the payload recorded in `nav\<envKey>.json` (capturing that file per §1.6d step 4 the moment this session is logged in, when it does not exist yet), address controls through the catalogue's `byName` map with the one-query visible-instance confirmation of §1.6d step 5, and fall back to live discovery only for what the files do not carry. Capture the **browser console (F12)**, the **network trace** of the failing request/response, the rendered screen state, and a screenshot at the moment of failure. **When the ticket’s only repro is a screen recording, the sequence transcribed from its frames IS the repro path** (§1 step 5, **R-VIDEO-EVIDENCE**) — drive that, and compare this run’s screenshots against the reporter’s frames at the failing action: two captures of the same screen state is the strongest reproduction evidence this runbook can produce short of the raising statement.
3. **Correlate with the database** when one is connected: run an Extended Events / Profiler capture scoped to that database across the failing action, so the client error can be tied to the actual statement and parameters that produced it.
4. Fold the captured error text, payload, and screen state into the `EVIDENCE_SET`, then re-enter §1.6 — a symptom that was `INFO_REQUIRED` because "the error exists only in a screenshot" frequently becomes `STATIC` once the real error text and stack are captured here.
5. **Read-only discipline:** never post, save, approve, delete, or otherwise mutate data on an environment that is not a restored copy under the operator's control. If reproducing genuinely requires a write, do it only against a local restore, and say so in the run output.
6. Any failure of §1.7a — environment unreachable, login fails, version mismatch, repro not reachable — is **never a STOP**. Record it, disclose it in the §6 RCA, and continue.
7. **Write back to the registry (§1.6c step 3).** Record `lastBuildStamp` (the full four-part `APP_BUILD_STAMP` from step 1) with `lastBuildStampAt`, the `storageState` path and `obtainedAt` when a session was captured headed here, `lastAliveAt`, and this `JIRA_KEY` on `seenOn` — and on a failure, `status` plus the transport reason. A run that reproduced on an environment and left the registry untouched has thrown away the only durable record that the environment is alive and what build it is serving. **The same discipline covers the §1.6d harness files:** merge every menu payload this session read into `nav\<envKey>.json` (§1.6d step 4), and every control that had to be resolved by live probing into the catalogue's screen entry — a discovery that stays in the transcript is paid for again on the next ticket.

## §1.7b Deployed-object fidelity check — is the customer running the code we are reading? (R-DEPLOYED-DIFF, mandatory when a DB is reachable)

**TRIGGER:** a database of the **reported** environment is reachable (§1.7 completed, or a `knownServers` connection to it exists) AND **either** the implicated path contains at least one database object (procedure, function, view, trigger, table type), **or** the EVIDENCE_SET contains at least one persisted value the run cannot attribute to a writer (§1.6 Step 2c `DATA_CAUSE`). Skip only when no DB is reachable at all — and say so.

**The trigger is read against the evidence, never against the changeset (R-GATE-NOT-SELF-EXCUSED, operator 2026-08-31).** *“The implicated path”* is an **output** of the analysis; this gate is an **input** to it. A run that has concluded the fix is a UI change and therefore records `not run — no database object in the changeset` has used its own conclusion to switch off the check that would have tested that conclusion. **No gate in this runbook may be recorded `not run` or `N/A` on the grounds that the fix this run selected does not touch that layer**, and this gate may not read `not run` while any stored value in the EVIDENCE_SET is unexplained. The same clause governs §3.4 Proof 1 and §3.11. Ref AP-24960 — all three were excused by the same substitution in a single run, and between them nothing obliged it to explain a voucher amount it had already written down as wrong.

**Why this is its own gate.** The whole run reads the object as it exists **on the branch**. The customer executes the object as it exists **in their database**. Those two bodies are routinely different, and when they are, every static conclusion drawn from the branch is about code the customer is not running. This single check decides which of two completely different tickets you are holding:

| Diff result | What the ticket actually is | Correct outcome |
|---|---|---|
| Deployed body == branch body | A genuine open defect | Continue; author a fix |
| Deployed body is **older** than branch (`DEPLOYED-STALE`) | **A deployment/patch gap — the fix already exists** | Do **not** author a code fix. Identify the JIRA that introduced the newer body and deliver a patch/deploy instruction for that object |
| Deployed body is **newer**, or diverges | A customer-specific hotfix or a branch that is behind | STOP the code fix; report the divergence — the branch is not the authority for this environment |
| Object absent from the DB | Wrong database, wrong module, or a never-deployed object | Re-check the DB is the reported environment before anything else |

**This table reads an object BODY. A stale DATA value routes to §1.7d first (R-STALE-DATA-WRITERS, dev review 2026-08-30).** Nothing writes a procedure body but a deployment, so `DEPLOYED-STALE` on a body means the deployment has not arrived. A configuration row has **many** writers, and the same verdict is ambiguous between *never applied* and *applied then overwritten* — §1.7d is the enumeration that settles it, and it needs no database. **No patch, data-channel re-run or data fix may be recommended for a stale stored value until §1.7d has returned a `DATA_WRITER_VERDICT`**; until it does, the `DEPLOYED-STALE` row above is suspended for that value.

**Procedure:**
1. Enumerate the objects on the implicated path (from §1.6 Step 2 and R-ERROR-CLASS).
2. Script each one out of the reported database — `SELECT OBJECT_DEFINITION(OBJECT_ID('<schema.name>'))`, or `sp_helptext`; for a table type, compare its column list and ordinals via `sys.table_types` / `sys.columns`.
3. Diff each against the branch body: `git show origin/<TARGET_BRANCH>:<path>`. Normalize whitespace/line endings before diffing; compare **statements**, not bytes.
4. Record one line per object: `<object> = SAME | DEPLOYED-STALE | DEPLOYED-NEWER | DIVERGED | ABSENT`, and for anything but `SAME`, the substantive differing statement.
5. **On `DEPLOYED-STALE`, find the owner of the newer body** — `git log -S'<the statement present on the branch but missing in the deployed body>' --oneline -- <path>`. That commit's JIRA key is the fix that has not reached the customer, and it is also `PRIOR_ART` for §1.6 Step 0.1.
6. **When the difference is a stored VALUE rather than an object body — or when the row was never there to diff — stop and run §1.7d before recommending anything.** Record `DATA_WRITER_VERDICT` beside the per-object line; the delivery-gap conclusion is not available until it reads `SINGLE-WRITER-NEVER-APPLIED`.

**Worked example (AP-24899).** The branch had `ALTER TABLE #tmpMiscPOPayables DROP COLUMN intVoucherPayableId, B_intItemId`; the customer's build (24.2.1009.1129) still had `DROP COLUMN intVoucherPayableId` alone, so `INSERT INTO @voucherPayablesMiscPO SELECT * FROM #tmpMiscPOPayables` carried one extra column, shifted onto the table type's identity column, and raised SQL 544. `git log -S` on the corrected statement names **AP-22527** (PR 129516). The whole ticket was a deployment gap: correct outcome = patch the object into 24.2Prod, no code change, no branch, no PR. Instead the run read only the branch — where the fix was already present — concluded the SQL was fine, went looking elsewhere, and landed on the UI.

**Reporting:** the per-object result goes in the run output and in the §6 **Verification status** block. `not run — no DB reachable` is an acceptable value; silence is not.

## §1.7c App-layer deployed fidelity — what code is the application actually serving? (R-APP-DEPLOY-DIFF)

**TRIGGER:** an `APP_ENV` is reachable (`FEASIBILITY = APP_REQUIRED-ACTIONABLE`, or an `APP_ENV` was supplied for any other reason). This is §1.7b for the half of the codebase a database cannot describe. Skip only when no `APP_ENV` is reachable — and say so.

1. **Capture `APP_BUILD_STAMP` — and be clear about what it is.** The running app reports the version it reads from **`tblSMBuildNumber` on the database it is connected to** (§1.7 step 2.6), not from its own binaries. Two consequences this runbook must not paper over:
   - The stamp is a **database-recorded claim about the last full build applied**, not a measurement of deployed code. When the app is pointed at the database already checked at §1.7 step 2.6, `APP_ENV_VERSION == DB_BUILD_VERSION` is a **tautology** and proves only that the app is pointed at that DB. It carries information in exactly one case: when the app is pointed at a *different* database from the one under analysis — then the mismatch says this is not the environment under report, which is worth knowing.
   - **A hand-applied patch does not bump `tblSMBuildNumber`.** The stamp is therefore *structurally blind* to §1.6b **B1 and B2** — the two cases the operator named. A patched environment reports the same version as an unpatched one. A matching stamp is never evidence that a patch is or is not present; that question is answered only by step 3 (served-asset diff) or step 4 (patch provenance), and if neither is available the answer is `PATCH-UNVERIFIED`, not "same version, therefore same code".
2. **Stamp vs. the branch — git has no build numbers.** A branch carries only main.major (`22.1`, `24.2`); there is no commit-level mapping from `22.12.0829.4808` to a SHA anywhere in the repository, and the digits inside a stamp are **not** to be read as a date and compared to commit dates. Without leaving git, the only available comparison is the main.major one §1.7a already performs — nothing finer. **Resolve the stamp through §1.5a first**: the i21 Connect release list returns the branch that produced it *and* its build time, which gives a real timestamp to compare against `git log` on that branch, and tells you whether the environment is behind the newest build on its own branch. For a commit-level answer, bridge through the build system: resolve the stamp to the Azure DevOps build that produced it (the branch’s build definition, matched on build number), read that build’s **source commit**, and compare *that* SHA against the commit carrying the implicated lines (`git log -1 --format='%h %ci' -- <path>`, or `git log -S'<statement>'`). The build’s source commit is an ancestor of the fix commit → **`APP-STALE`**, routed exactly like §1.7b `DEPLOYED-STALE`: the fix exists and has not reached this environment — deliver a deploy instruction, author no code fix. When the stamp cannot be resolved to a build, record `APP-STALENESS UNDETERMINED (stamp <x> not resolvable to a build)`. Never infer staleness from the stamp alone.
3. **Served-asset diff — the app-layer analogue of scripting out a proc.** i21 serves its ExtJS sources over HTTP. For each implicated `.js`, `GET <APP_ENV>/<path>` and diff it against `git show origin/<TARGET_BRANCH>:<path>`, normalising whitespace and line endings and comparing statements rather than bytes. Record one line per file: `<path> = SAME | APP-STALE | APP-NEWER | DIVERGED | ABSENT`. **This needs no build, no deploy, and no source access on the server** — it is the one direct read of app-layer deployed code available to this runbook, and it is cheap. Compiled C#/DLL code stays out of reach: for those files the step-2 build stamp is the only evidence there is, and the ledger says exactly that rather than implying a check that never happened.
4. **Patch-provenance ledger.** For every `Apply patch <JIRA>` helpdesk ticket found by §1.6b B1, record: the patch JIRA, the target environment, whether the HDTN shows it actually applied, and to which build. Anything unconfirmed is **`PATCH-UNVERIFIED`** and is never treated as applied. "We are using the latest patch" is a belief until the HDTN or the served asset says so — on AP-15931 that belief, held in good faith on both sides, is what the three weeks were spent on.
5. **Three-way comparison — prod observes, dev exercises, the branch adjudicates (operator 2026-08-24).** When both `APP_ENV_PROD` and `APP_ENV_DEV` are supplied, run steps 1–4 against **each** and read the three states together. This subsumes the disputed-reproducibility case of §1.6b B4 — one party reproducing and another not *is* a prod/dev divergence — and it answers the operator’s question directly: **does dev already carry a fix that prod has not received?**

   **Key the axis on `REPORTED_ENV_KIND` (§1.5a), not on the words "prod" and "dev".** In the table below, *prod* means **the environment the ticket was reported on** and *dev* means **the environment where the fix is exercised**. That is usually prod vs dev — but a JIRA is often reported on a Dev build, and when §1.5a resolves the reported stamp to a Dev branch both sides are Dev: the useful comparison becomes the reported dev environment against its own branch head, and the deliverable is a **redeploy**, never a customer patch instruction. Resolve the kind before reading the table.

   | `APP_ENV_PROD` | `APP_ENV_DEV` | Branch | Reading | Correct outcome |
   |---|---|---|---|---|
   | Reproduces | Does **not** | Fix present | **Deployment gap** — the fix exists, reached dev, has not reached prod | §1.7b/§1.7c `*-STALE` routing: deploy instruction for the named artifacts. **No code fix, no branch, no PR** |
   | Reproduces | Reproduces | No fix present | **Genuine open defect** | Author the fix; exercise it on dev |
   | Reproduces | Does **not** | No fix present | **Dev carries something the branch does not** — an unreleased hand patch owned by nobody | Run steps 3–4 on dev *before* concluding anything. Identify and attribute that artifact; do not adopt it as "the fix" |
   | Does **not** reproduce | — | — | The reported environment does not show the symptom | Re-check that `APP_ENV_PROD` really is the reported environment (§1.7b), then re-enter §1.6 |

   **Write discipline is asymmetric and non-negotiable.** `APP_ENV_PROD` is **observe-only**: navigate, read, capture, diff assets, read the stamp. §1.8 **Axis A** (the reported transaction) runs there only where it is genuinely read-only. §1.8 **Axis B** (a newly created transaction) is **never** created on prod — it belongs on `APP_ENV_DEV` or a restored copy, and a run that has only prod records `NEW-TXN NOT-ATTEMPTED (production environment — no writes)`, exactly as it does for a shared SQL server. This is the existing never-write-to-a-customer-environment rule made explicit for the two-environment case.
6. **Reporting.** One line per artifact into the run output and the §6 **Verification status** block. `not run — no APP_ENV reachable` is an acceptable value; silence is not. §1.7c is never a STOP on its own — the STOP, where there is one, is taken at §1.8b on a completed elimination ledger. Name the environment each line came from (`prod` / `dev`) whenever both were supplied, and write each environment's build stamp back to the `appEnv` registry (§1.6c step 3) so the next run opens knowing what this environment was last serving.

## §1.7d Stale DATA is not stale CODE — enumerate the writers before recommending a patch (R-STALE-DATA-WRITERS, dev review 2026-08-30, ref AP-24915)

**TRIGGER:** the run is about to blame a wrong, missing or outdated **stored value** on a delivery gap — or to conclude that the stored data is fine and only the code reading it is wrong. Concretely: §1.7b returned `DEPLOYED-STALE` or `ABSENT` against a **data row** rather than an object body · or `DATA_CAUSE` (§1.6 Step 2c) names a value whose corrected form already exists in a delivered changeset · or the root cause is a **predicate that does not match stored data** — a join, filter or lookup comparing a literal in our code against a stored column, where the compared column is the stored value and arms this gate whether or not anything is “wrong at rest” (§3.4 Proof 1, *a comparand is a value*) · or the run is about to recommend a patch, a data-channel re-run, or a §3.6 data fix that writes a configuration value. **Every signal this gate reads is repository text** — no database, no application, no restore. `not run — no DB reachable` is therefore never an answer here; the only acceptable non-answer is `N/A — no stored value in the evidence`, and R-GATE-NOT-SELF-EXCUSED governs that one too.

**Why it is its own gate.** §1.7b's `DEPLOYED-STALE` verdict was built for **object bodies**, where the diff is conclusive: nothing writes a procedure body but a deployment, so *older body* can only mean *the deployment has not arrived*. **A data row has many writers**, and the identical observation is ambiguous between two opposite explanations:

| Observation | Explanation A | Explanation B |
|---|---|---|
| the delivered correction is not visible in the database | the changeset **never ran** — a delivery gap | the changeset **ran and was overwritten** — something re-asserts the old value |

One discriminating question separates them, and neither §1.7b nor §1.6 asks it: **what else writes this value?** The only gate that does ask it is §3.4 Proof 1's origin trace — and the `DEPLOYED-STALE` route **exits before §3**, so the run reaches its recommendation with the check that would have tested it never executed. Explanation A is also the cheaper story and the one a run arrives at unaided: it needs no second object, and the missing value appears to prove it.

**The writer usually belongs to another module, and that is the point.** A module running this runbook does not own the policy governing a shared configuration table and does not know the owning module's rules — nothing in the ticket will tell it, and the object that re-asserts the value carries no marker saying *a rule lives here*. That is why the enumeration below is repository- and organization-wide rather than scoped to `REPO_PATH`, and why its outcome is routed through **§2.6** — whose signal 4, *who writes the bad rows*, is exactly this gate's output — instead of being acted on here. The evidence that settles this class is a **manual trace of the writer**, offline and reproducible; on AP-24915 that trace is what a developer's review produced after two automated runs had missed it.

### 1. Enumerate every writer of the value — organization-wide, not module-wide

For the table and column carrying the defective value:

1. `git grep -niE '(UPDATE|INSERT[[:space:]]+INTO|MERGE)[^;]*<table>' origin/<TARGET_BRANCH>` in **every** repository under `REPO_ROOT`, not only the one this JIRA resolved to.
2. An organization-wide code search (Azure DevOps `search_code`) for the same patterns, because a writer in a repository nobody cloned is the commonest miss — and it is the one most likely to be another module's.
3. The client and service layers as well: an ExtJS store, a Web API controller or an import routine writes configuration rows just as a procedure does.

**A truncated sweep is not an absence (R-SWEEP-NOT-TRUNCATED).** Result caps hide writers, and a capped set read as a complete one produces the exact false negative this gate exists to prevent. When a sweep returns at its limit, re-scope it — narrow the path, split the pattern, drop the noisiest repository and search it separately — and record the scope the final answer rests on. `WRITERS-UNDETERMINED` is an honest verdict; "no other writer found" after a capped grep is not.

### 2. Classify each writer, then read the recurring one's INPUT

| Class | What it looks like | Lifetime |
|---|---|---|
| `ONE-TIME` | a dated data changeset, a delivered patch script, a data fix | executes once, then never again |
| `RECURRING` | a `runOnChange` logic object, a listing or stage refresh, a post-deployment step, a scheduled job, an application save path | re-executes on **every** deployment or every save |

**Standing suspects for configuration tables:** `*CommitListing`, `*UpdateStageListing`, `*Sync*`, `*Seed*`, and anything the build or deployment pipeline invokes by name. A `runOnChange` object is re-executed on every deployment by construction — being *unchanged* does not make it inert.

Then read the recurring writer's **input**, not only its body: where does it get the value it writes? **If that input still carries the stale value, explanation B is proven with no database access at all** — the row was corrected and then overwritten, and it will be overwritten again on the next deployment. This is the proof this gate requires before any verdict, and it is available offline.

### 3. `DATA_WRITER_VERDICT` — exactly one, recorded

| Verdict | Meaning | Route |
|---|---|---|
| `SINGLE-WRITER-NEVER-APPLIED` | the one-time changeset is the only writer of the value | §1.7b's delivery-gap route stands unchanged — patch / deploy instruction, no code fix |
| `RE-ASSERTED (<writer> ← <input>)` | a recurring writer re-asserts the old value from an input that still carries it | step 5 — the patch is transient and may not be offered as the fix |
| `WRITERS-UNDETERMINED` | the sweep could not be completed, or the writers conflict | held exactly like `RE-ASSERTED`: state the ambiguity, recommend nothing as durable |

### 4. When a database IS reachable, read the changeset's execution record — from the CONFIGURED changelog table

Resolve the changelog table name **from the repository** before querying it: `databaseChangeLogTableName` in the Liquibase repository's [`liquibase.properties`](https://dev.azure.com/irely/i21/_git/i21_Liquibase?path=/liquibase.properties) — in `i21_Liquibase` it is `tblSMLiquibaseChangeLog`, with `tblSMLiquibaseChangeLogLock` beside it. **Liquibase's default `DATABASECHANGELOG` exists on no i21 database**, so a check against it reports "no such table" every time, on a perfectly healthy database. Reported as *"Liquibase has never executed here"* that is a fabricated finding — and it was the load-bearing claim of the first AP-24915 analysis. Against the right table, the changeset's own row (`ID`, `AUTHOR`, `EXECTYPE`, `DATEEXECUTED`) discriminates the two explanations directly: `EXECUTED` while the value is still wrong **is** explanation B, proven. Absence of the row supports explanation A but does not close it — a recurring writer found at step 1 still outranks it.

### 5. `RE-ASSERTED` — the one-time correction is structurally transient. Say so, and stop offering it

A one-time correction to a value owned by a recurring writer **can never hold**, and re-applying it is not a fix in any form — not an attached patch, not a data-channel re-run, not a §3.6 data fix. The RCA must say that in those terms rather than repeating the recommendation in a new wrapper. The durable fix is at the writer, and there are three shapes of it; present them as options with their costs, and decide none of them here:

| Option | What changes | Cost |
|---|---|---|
| **Correct the writer's input** | the sync then asserts the value the consumers expect | changes whatever else reads that input — usually user-visible |
| **Exempt the value inside the writer** | the sync runs, this one value is overridden | smallest change; **cite the in-object precedent when one exists** — a writer that already carries an override for another value has settled the pattern |
| **Rebind the consumers** | the synced value stops being load-bearing | largest change, and the only one that removes the coupling for good |

Then run **§2.6 on the artifact each option would touch** — that is the writer's object, not this ticket's. It is usually another module's, so the verdict is normally `FOREIGN-*`: diagnosis delivered, no fix authored here, `ROUTING-REQUIRED`, and **R-NO-REHOME still holds** — this gate moves no ticket and files none.

### 6. A patch may still be delivered — with its expiry written on it

`RE-ASSERTED` does not forbid handing over the correction; it forbids calling it the fix. Where an environment needs relief today, §3.10 may still deliver the script, and the **Deployable patch** line must then carry the expiry in the same sentence: `stop-gap — reverted at the next execution of <writer> (<when that runs>); the durable fix is <the routed option>`. A patch delivered without its expiry is read as a resolution, and the ticket closes on it.

### 7. Re-sweep prior art on the ROW, not on the wording

Once the root cause lands on a **configuration-row value**, the §1.6 Step 0.1 prior-art sweep has already run — and it ran against this ticket's wording, component and object. That sweep does not reach the sibling ticket whose summary names a different screen and whose implicated object is a different file, even when it is the **same table, the same row family, the same writer and the same build**. Re-run it keyed on the row: the table name, the namespace, the stale and corrected values as literal strings, and the writer's own name — over Jira text search and the repositories both. A sibling whose dev review has already identified the writer is the cheapest evidence available to the run. Ref AP-24889 and AP-24915 — one ticket apart, same cohort, same build, same table row family, same sync; the second run repeated the first's conclusion because the sweep was keyed on component and summary.

**Reporting.** One line into the run output and the §6 **Verification status** block: `**What writes this value:** <DATA_WRITER_VERDICT> · <n> writer(s) swept over <scope> · recurring: <each with its owning project, or none> · changelog table <resolved name>: <changeset row or not reachable>`. `N/A — no stored value in the evidence` is an acceptable value; silence is not.

**The build-bump tell — the cheapest discriminator here, and it needs nothing (R-WRITER-BUILD-BUMP).** A delivery gap is closed by the next build. A recurring writer is not. So when the environment took a **newer build during the ticket's life and the symptom did not move**, explanation A is dead and you are looking at a writer. One comparison of the reported build stamp against the current one settles it, before any sweep.

> **The instance this gate was built from.** On the ticket that produced it the writer is **another module's deployment sync** — a job that rewrites the object on every build, carrying its own exemption precedent. Two consecutive runs on that ticket concluded *delivery gap* and recommended a patch that the sync reverts on every build. **The sweep below is what the gate requires**, and it is the only thing that finds a writer of that shape: a writer living in another module's repository is the commonest miss here, and nothing in the object's own body reveals it.

## §1.8 Reproduction gate — did we actually raise the symptom? (R-REPRO, mandatory on EVERY run)

Runs after §1.7 / §1.7a / §1.7b, before §2. **No feasibility verdict exempts it** — see R-STATIC-NOT-EXEMPT in §1.6 Step 2. Its output is the `REPRO` verdict, which §6 must carry verbatim.

**The failure this gate exists to stop (ref AP-24899).** A run can read code, query a database, and write a detailed, well-evidenced RCA **without ever once causing the reported error to happen** — and nothing in the output distinguishes that from a proven diagnosis. AP-24899's RCA cited a restored snapshot, a voucher's `intBillId`, specific column values, and a validation-function result, then graded its acceptance criteria `PASS (static + DB corroboration)`. Not one of those was an execution of the failing path. The error was raised by SQL Server, inside a stored procedure, on a database that was connected and sitting right there. Reproduction was never attempted, and the phrase "PASS (static + DB corroboration)" concealed that rather than disclosing it. A hypothesis is not a root cause until something you did made the symptom appear.

### 1. Pick the layer that can actually raise the symptom

Reproduction is **not** synonymous with driving the UI. Choose by where the symptom is raised, and attempt **every** reachable layer, cheapest first — a missing `APP_ENV` never justifies attempting nothing:

| Symptom is raised by | Reproduce at | Needs |
|---|---|---|
| SQL Server (error number, message from a proc/trigger/constraint, wrong query result) | **The database** — `EXEC` the implicated object with the reported parameters | A restored DB only. No app environment |
| The ORM / service layer (EF save graph, serialization) | The database, by replaying the statement batch the ORM emits; or `APP_ENV` | DB, or DB + app |
| The browser (field blanks, grid renders, client-side error text) | `APP_ENV` via §1.7a | App environment |
| A report/document render | `APP_ENV`, or by executing the report's SP and inspecting the dataset | Either |
| **Schema, contract or compile-time** (parameter-supply and bind errors, column-count/identity shifts, a body that will not compile, a deterministic pure-function defect, a failing repo test) | **The repository itself** — build it, run its tests, or stand a **scratch database up from the repo's own schema** and execute the object there | Nothing but the repo, plus a local SQL Server for the scratch case |

**The trap this table closes:** "the ticket shows a UI screenshot" does **not** make it a UI defect, and "no `APP_ENV` was provided" does **not** make it unreproducible. An error surfaced *in* the browser is very often raised *in* the database. Classify by the raiser, not by where the user saw it. On AP-24899 the surfacing layer was a browser dialog and the raising layer was a stored procedure — the DB-layer reproduction was available the entire time and was never tried.

**R-REPRO-REPO — the repository is a reproduction venue, and it is the one that is ALWAYS present (operator 2026-09-03, ref SC-9232).** Every other row above needs something this run might not have. The repo needs nothing: **Repository scope** already required it to be cloned and fetched before the §1 analysis, so it is on disk before the first gate runs. *Reading* it is never reproduction — but three things built **from** it are executions, and the runbook already performs all three elsewhere without ever counting them here: the compiler (§3 validation), the repo's own tests, and a **throwaway local database created from the repo's own schema** (§3.9 builds exactly this; §3.5 aligns one with `liquibase update`).

Ref SC-9232, and this is the measurement that put the row in the table: the reported failure was a `sp_executesql` parameter-supply error naming a table-valued type. That type is **defined in the repository** (`i21Database/dbo/User Defined Types/ScaleManualDistributionAllocation.sql`, eleven columns), and raising the error needed the type and nothing else — not the stored procedure, not one row of customer data, not an app environment. `CREATE TYPE` from the repo onto any local SQL Server plus a three-line `SELECT` referencing both parameters reproduces it **byte-identically, truncation included**. The customer database supplied the ticket numbers and a four-ticket natural experiment; it was never required for the reproduction. Three runs across six days reported that no environment was available. The venue that could raise it had been cloned before any of them started.

**What a repo reproduction proves, and what it does not.** It proves the defect exists **in the code we read**. It does **not** prove that is the code the customer is running — that is the §1.7b / §1.7c deployed-fidelity question, which stays open and must be said to stay open — and it does not prove this is the defect the reporter hit when the reported artifact was never involved. Hence its own verdict string rather than a share of `REPRODUCED-DB`.

**The converse trap, which this table alone does not close (ref AP-15931).** Everything above pushes toward "it is probably the database." That bias is right on volume and wrong exactly where it costs most, because a symptom the database *cannot* raise will still yield a plausible-looking DB investigation. AP-15931's symptom was a **warning dialog with no text in it**. A stored procedure can return a wrong message; it cannot return the *absence* of a message — that is raised in the client, always. The ticket ran three weeks across six comments, dev unable to reproduce and QA reproducing every time, and closed **`Cannot Reproduce`**. Classify by the raiser in *both* directions: §1.6b Trigger A lists the symptom classes for which no database execution is a substitute, and reaching for the DB on one of those is the same error as reaching for the UI on AP-24899.

### 2. Reproduce on the reported transaction — then on a NEW one

Both axes are mandatory whenever a DB or `APP_ENV` is reachable. They answer different questions, and **the pair is what identifies the defect class**:

- **Axis A — the reported transaction.** Use the exact documents the ticket names (AP-24899: voucher PI-1671, PO-84). Execute the failing path against them and capture the raw result — error number, message, `ERROR_PROCEDURE()`, or the wrong values.
  - **The reported document is not in the provided DB → that is a finding, not a footnote.** Record `NOT-REPRODUCED-TXN-ABSENT` and say which document was missing — but **only after looking for it in every other candidate snapshot, oldest included (R-DB-CANDIDATE-SET)**: the newest copy is the one most likely to have had the evidence purged, archived, or overwritten by the customer's own workaround, so absence from the primary is not absence. The verdict must name the snapshots checked and their dates. **Never silently substitute a similar record.** AP-24899's snapshot did not contain PO-84, so the run reasoned from PO-83 "matching the Book-blank behaviour" — an analogy presented in the RCA with the same confidence as an observation. If you do examine a similar record, label it `ANALOGY (<record> stood in for <reported record>)`; an analogy can motivate a hypothesis and can never grade a criterion `PASS`.
  - **Use the ticket's own database.** When the ticket supplies a backup/link, that is the environment under report. A convenience snapshot of the same customer from a different date is a *different environment* — usable, but declare it: `SUBSTITUTE-DB (<what was used> instead of <what the ticket supplied>)`. AP-24899 supplied two DB links in the description and the run used an unrelated shared-server snapshot without ever saying so.
  - **The ticket supplied NO database at all → `SUBSTITUTE-DB` is unfillable, and that is the trap (ref SC-9232).** Its sentence needs both halves; with `<what the ticket supplied>` empty the label quietly gets dropped, and a copy found by the §1.7 step 0 **R-DB-COLD-SWEEP** registry sweep is narrated as "the database" with nothing telling the reader it was not the reported environment. Use the cold-sweep labels instead: `COLD-SWEEP-DB (<server>/<dbname> — found by registry sweep; no DB supplied on the ticket; acceptance gate PASSED)`, or `SUBSTITUTE-DB-COLD (<server>/<dbname> — found by registry sweep; no DB supplied; reported artifact ABSENT — orientation only)` when gate check 3 failed. Under `SUBSTITUTE-DB-COLD` the reported-transaction axis is `NOT-REPRODUCED-TXN-ABSENT` **by construction**, no criterion may be graded `PASS`, and a similar record read there is still an `ANALOGY` and is labelled as one.
- **Axis B — a newly created transaction.** On the restored copy (or `APP_ENV`), create a fresh transaction by following the ticket's replication steps, and attempt the same failure. This is the axis that tells you whether you are fixing code or fixing data, and it is the axis operators actually ask about: *"can this still happen to the user tomorrow?"*
  - Writes are permitted **only** on a restored copy under our control, and the copy is left rolled back or discarded. **On a shared server, a new transaction is not created** — record `NEW-TXN NOT-ATTEMPTED (shared server <name> — no writes)` and, if the answer matters, request a restorable backup. "Shared server" is a reason to disclose a gap, not a reason to leave the whole gate empty: Axis A read-only execution of a proc inside an explicit transaction that is rolled back is still available, and on AP-24899 it alone would have settled the ticket.

### 3. Read the pair — this is the inference, and it is the point of the gate

| Reported txn | New txn | What it means | Correct handling |
|---|---|---|---|
| Reproduces | Reproduces | Live systemic defect in current code/deployed objects | Fix the code (or deploy per §1.7b). Highest confidence |
| Reproduces | Does **not** | The defect is in the **existing data or the older build that wrote it**; current code no longer produces it | Strong `DATA_FIX` signal (§3.6), and/or an already-shipped code fix — check §1.7b and `PRIOR_ART` before writing any code |
| Does **not** | Reproduces | New-transaction-only — an environment/config/deployment difference, or the reported record predates the defect | Re-check §1.7b (`DEPLOYED-STALE`) and the build stamps before proceeding |
| Neither reproduces | | **The hypothesis is disproven, or the environment does not match** | Do NOT author a fix on it. Re-enter §1.6 — compare build stamps, re-run §1.7b, reconsider the R-ERROR-CLASS candidates you excluded. Report honestly that the symptom could not be raised |
| Reported absent / not attempted | | Nothing has been proven | See the fail-closed rule below |

### 4. `REPRO` verdict (record exactly one; the run output carries this token verbatim, and §6 renders it in plain language with the token appended — R-REPRO-PLAIN)

`REPRODUCED-RUNTIME` · `REPRODUCED-DB` · `REPRODUCED-REPO` (raised by building, testing, or executing against a scratch database stood up from the repo — carries the mandatory rider that deployed fidelity stays open, see R-REPRO-REPO) · `REPRODUCED-BOTH-AXES` (reported **and** new transaction) · `REPRO-ATTEMPTED-DISPROVEN` (executed, symptom did not occur — a major finding, never a silent one) · `NOT-REPRODUCED-TXN-ABSENT` · `NOT-REPRODUCED-NO-ENV` (**both** conditions of R-REPRO-DERIVED met — no DB, no `APP_ENV`, **and** a raising layer the repository cannot host; the only blameless non-reproduction) · `NOT-ATTEMPTED`.

Each verdict carries its axes: `REPRO = <verdict> · reported-txn: <result> · new-txn: <result or why not>`.

**R-REPRO-DERIVED — the verdict is COMPUTED from the ledger, never chosen (operator 2026-09-02, ref SC-9232).** Every verdict above was previously *selected* by the run, which let it pick the label matching its own account of events rather than the one its actions earned. SC-9232 recorded `NOT-REPRODUCED-NO-ENV` — defined one paragraph above as *no DB and no `APP_ENV` obtainable* — on a run whose own step-6 ledger read `DB touched: AG1 / AGSTAR_TE_082826` and `Objects EXECUTED: 0`. The state it was actually in was `NOT-ATTEMPTED`, which the fail-closed rule below bars from posting an RCA at all. Choosing the blameless-sounding string converted a state that **forbids** an RCA into one that **permits** it, and nothing else in the comment contradicted it.

Derive the verdict from the step-6 ledger's own fields — `DB touched`, `Runtime (APP_ENV)`, `Objects EXECUTED`, and whether a runtime action was driven — and record the derivation beside the verdict:

| Ledger state | Derived verdict |
|---|---|
| `DB touched = none`, `Runtime (APP_ENV)` not resolved, **and** the raising layer is one the repository cannot host (data state, deployed state, or render) — **stated with its reason** | `NOT-REPRODUCED-NO-ENV` — **the only route to this string** |
| no DB and no `APP_ENV`, but the raising layer **is** repo-hostable and the repo was not exercised | `NOT-ATTEMPTED` → §6 RCA barred, §6.5 D triage instead |
| an environment was reachable, `Objects EXECUTED = 0`, no runtime action driven | `NOT-ATTEMPTED` → §6 RCA barred, §6.5 D triage instead |
| built, tested, or executed on a scratch DB stood up from the repo, and the symptom occurred | `REPRODUCED-REPO` — deployed fidelity still open |
| the failing path was executed; reported artifact absent from every candidate snapshot | `NOT-REPRODUCED-TXN-ABSENT` |
| the failing path was executed and the symptom did not occur | `REPRO-ATTEMPTED-DISPROVEN` → STOP on the hypothesis, re-enter §1.6 |
| the failing path was executed and the symptom occurred | `REPRODUCED-DB` / `REPRODUCED-RUNTIME` / `REPRODUCED-BOTH-AXES` |

**“No environment” is now a two-part claim, and the second part is the one that gets skipped.** `NOT-REPRODUCED-NO-ENV` requires not only that no DB and no `APP_ENV` resolved, but that the symptom belongs to a class the **repository cannot raise** (R-REPRO-REPO) — written out with its reason, never assumed from the absence of a database. Data-state, deployed-state and render symptoms qualify and stay blameless. A schema, contract, compile-time or deterministic-logic symptom does **not**: the repo was on disk before the run began, so declining to use it is `NOT-ATTEMPTED`. Where the venue itself is unavailable for a concrete reason — no local SQL Server in `sqlServer` config, a build that cannot be produced — record that reason; a disclosed gap is honest, an unexamined one is not.

**A verdict that contradicts the ledger printed beneath it is a §3 FAIL, not a wording choice.** This check is arithmetic over values the run has already written down: it needs no new evidence, no environment and no execution, and it is the one gate in this section that cannot be satisfied by reasoning.

### 5. Fail-closed rule (R-REPRO-FAILCLOSED)

- **`NOT-ATTEMPTED` is forbidden as a terminal state whenever a DB or `APP_ENV` was reachable.** A run that had an environment and did not use it may **not** post a §6 RCA. It posts the §6.5 D triage comment instead, stating what was reachable and was not exercised. A wrong RCA on a customer ticket costs more than an honest "not yet proven": on AP-24899 it produced a pushed branch (`24.2Dev_AP-24899`) touching an unrelated UI file, a claimed defect lineage across five branches that would have fanned out five wrong propagation PRs, and a duplicate of an RCA that already existed.
- **`NOT-REPRODUCED-NO-ENV` does not block delivery** — a genuinely static defect with no obtainable environment is still fixable — but it **downgrades the language**: see R-VERDICT-HONESTY in §6. The Root Cause section is titled as a hypothesis, and no criterion may be graded `PASS`.
- **`REPRO-ATTEMPTED-DISPROVEN` is a STOP on the current hypothesis**, not on the run. Return to §1.6. This is the runbook's cheapest correction and the one AP-24899 never got.

### 6. Evidence ledger — make it impossible to *not* know what we did

The reason AP-24899's RCA could not be audited is that "we queried the database" and "we executed the failing path" were indistinguishable in it. Every run therefore records this ledger, and §6 carries it:

```
DB supplied:     <what the TICKET provided: attachment | link | HDTN <n> `Database Copy`> | NONE - cold sweep run (<n> knownServers entries scanned; <found <server>/<dbname> | nothing found>)
DB touched:      <`shared <server>/<dbname>`, or `local restore` — never a local restore's server/db name> · build <DB_BUILD_VERSION> | none
DB provenance:   <DB_PROVENANCE — which HDTN's Database Copy / attachment / link / `knownServers sweep — not traceable to a listed HDTN`> · <SUBSTITUTE-DB note if any> | n/a
Snapshots:       <the ranked candidate set: primary + each retained copy with its date, and why each was not primary> | single candidate
Cross-snapshot:  <CROSS-SNAPSHOT (<db> @ <date> — consulted for <question>) for each one actually queried> | none
Objects read:    <n> (<names>)
Objects EXECUTED: <n> (<names, with parameters>)      <- the line that separates proof from reading
Errors captured: <error number/text, and ERROR_PROCEDURE() when available> | none
Writes made:     none | <what, on which restored copy, rolled back?>
Reported txn:    <document(s)> — present? executed? result?
New txn:         created? | not attempted (<reason>)
Runtime (APP_ENV): <version> — <baseUrl> · resolved from <parameter | ticket | registry> · <alive | unreachable> | not resolved (parameter, ticket and registry all empty)
Recordings:      <VIDEO_EVIDENCE — per recording: <id/file> <duration> -> <n> frames read · what they yielded> | DECODE-FAILED (<ffmpeg error>) | STOPPED-NO-DECODER (run halted, nothing posted) | none supplied
```

**`Objects EXECUTED: 0` combined with a reachable database is exactly the AP-24899 failure mode**, and it is now visible on the face of the run instead of buried under the word "corroboration". Never describe reading a table as reproducing a symptom.

**`DB touched` / `DB provenance` are the AP-24877 half of the same problem.** Before them, the only value this line ever carried was a substitute note, so a run that used the ticket's own database recorded its identity **nowhere** — and once the session ended, "which of this ticket's three HD tickets supplied the copy we executed against" was unanswerable. Both lines are governed by **R-DB-PROVENANCE** (§1.7) and both are carried into the terminal comment, whichever one §6 / §6.5 selects.

## §1.8b Is the application genuinely required? — the elimination gate (R-APP-ELIMINATION)

**TRIGGER:** §1.6b recorded `APP_REQUIRED = YES` **and** §1.6c resolved no live `APP_ENV` from any of its three sources — parameter, ticket, registry. Runs after §1.8, because it consumes §1.8's execution results — it cannot run earlier and must not be attempted earlier.

**The rule (operator 2026-08-24).** *"i21 app absence would not purely stop until we tested and verified that an app is required."* A missing app environment never stops a run on the strength of a classification. It stops the run only after the cheaper layers have been **executed** and **shown not to raise the symptom** — and the comment it posts must say what was tested, what each test produced, and why the conclusion follows. A STOP that cannot show its work is indistinguishable from a run that gave up, and it will be read as one.

### 1. The elimination ledger

One row per layer. Fill it from work already done — §1.6 Step 2, §1.7, §1.7b and §1.8 have produced all of it; this gate assembles rather than re-runs:

| Layer | Reachable when | What is executed | What is recorded |
|---|---|---|---|
| Static code read | always | the implicated path on `TARGET_BRANCH` | the mechanism found, and **why it does not account for the reported observation** |
| Database — implicated objects | §1.7 completed | `EXEC <object>` with the reported parameters (this **is** §1.8 Axis A) | error number, `ERROR_PROCEDURE()`, message, or result set — or the literal `no error raised, result correct` |
| Database — deployed fidelity | §1.7b ran | script-out + diff, per object | the §1.7b ledger verbatim |
| Service / HTTP | a request can be replayed from the evidence | the replayed request | status code + payload |
| Other R-ERROR-CLASS candidates | always | each candidate raiser considered | the evidence that excludes it |

A layer that was reachable and left **unexercised** makes the STOP unavailable — the same fail-closed logic as R-REPRO-FAILCLOSED. Go and exercise it.

### 2. Decision

| Ledger state | Verdict | Action |
|---|---|---|
| Some row **raised the symptom** | app not required to establish the root cause | Drop to `APP-FIDELITY UNVERIFIED (<signals>)` and continue. The app may still be wanted to *confirm* the fix — that is a §6 disclosure, never a stop |
| No row raised it, but a reachable layer is unexercised | **not yet determinable** | **No STOP.** Exercise it, then re-enter this gate |
| No row raised it, every reachable layer was exercised, and the symptom belongs to a §1.6b **Trigger A** class that the remaining layers structurally cannot raise | **`APP_REQUIRED-PROVEN`** | Post the ENVIRONMENT REQUEST below and **STOP** |
| No row raised it, every reachable layer exercised, but the symptom is **not** a Trigger A class | hypothesis is disproven, not blocked | Re-enter §1.6 per §1.8 `REPRO-ATTEMPTED-DISPROVEN`. Do not request an environment to rescue a dead hypothesis |

Every `no error raised` row is a `REPRO-ATTEMPTED-DISPROVEN` **at that layer** — a finding, never a silent one, and it is precisely what makes the environment request credible rather than a shrug.

### 3. The ENVIRONMENT REQUEST comment

**Before posting, re-run §1.6c steps 1–2.** An environment recorded by an earlier run on this customer may already answer the request, and one probe is what it costs to find out. Asking for a URL that is already on file — or asking for one without noticing the file's entry is dead — is the cheapest failure this gate has. If the registry yields a live environment, do not post: go run §1.7a / §1.7c against it.

Post ONE comment via `addCommentToJiraIssue` (contentFormat markdown), add `JIRA-AI-NeedInfo` additively, then STOP. The ledger is **not optional** — a request without it is the thing this gate exists to prevent:

```
# Environment Request — automated analysis (JIRA-AI)

Automated analysis on branch `<TARGET_BRANCH>` could not raise the reported symptom on any
layer available to it, and has established that the remaining layer is the i21 application
itself.

**What was tested, and what it produced**
| Layer | What was executed | Result |
|---|---|---|
| Code (`<TARGET_BRANCH>`) | <the implicated path> | <mechanism found; why it does not explain the observation> |
| Database | `EXEC <object>` with <the reported parameters> | <error/result, or "no error raised, result correct"> |
| Deployed objects | script-out + diff of <n> object(s) | <SAME / DEPLOYED-STALE / … per object> |
| <other layers exercised> | … | … |

**Why the application is required**
<the §1.6b Trigger A row, in one plain sentence, tied to what the table above shows —
e.g. "the reported symptom is a warning dialog with no text in it. The validation procedure
was executed with the reported vendor and returned its message correctly, so the message
exists at the database layer and is lost between there and the screen. No SQL execution can
observe that, because the defect is the absence of rendered text.">

**What is needed**
1. A URL for an i21 environment running <TARGET_VERSION> where this reproduces
   (a test/copy environment is preferred — no writes are made to a production environment).
2. Login credentials, sent through the normal credential channel — not posted on this ticket.
3. <when §1.6b Trigger B also fired> The exact build applied there (the four-part
   `tblSMBuildNumber` stamp), and whether the patch from <patch JIRA> was applied to it,
   and on what date.

**What will be done with it**
<the specific navigation and capture that would settle it — so the request names an
experiment, not an errand>
```

Dedupe as for the DB request: one per customer cohort; an unanswered equivalent already on the thread is reported (`awaiting environment since <date>`), never re-asked.

### 4. Why this is allowed to be a STOP (R-APP-BLOCKED-STOP)

This narrowly supersedes the blanket *"a missing app environment is never a STOP"* (operator 2026-08-07) — and only for `APP_REQUIRED-PROVEN`, which by construction cannot be reached without an executed, published elimination ledger. The 2026-08-07 rule was written when `APP_ENV` was an optional accuracy booster for screenshot-only tickets, and it remains correct everywhere else in this runbook. What has changed is that the STOP is now **earned by evidence rather than asserted by classification**: continuing past a proven `APP_REQUIRED` would mean publishing a root cause derived entirely from code that was never executed against the reported behaviour — the same failure R-REPRO-FAILCLOSED already forbids when a database was reachable and went unused.

## §2 Check the acceptance criteria

Extract and cache `ACCEPTANCE_CRITERIA` from the Jira issue.

1. Read the **Acceptance Criteria** from the Jira (a dedicated field, a section in the description, or an explicit checklist in the comments). Capture each criterion as a discrete, testable item — and **cache its exact wording**, character for character, alongside the normalized form. §6 quotes the ticket's own words back to the reader (R-AC-VERBATIM), so a criterion that was only ever stored as this run's summary of it cannot be quoted later. Record where each one came from — the field, the description section, or the comment author and date.
2. IF no acceptance criteria are present or they are ambiguous/untestable:
   - Derive candidate acceptance criteria from the issue description and expected behavior, and record that they were **derived** (not authored on the ticket). Mark each derived item individually: a ticket often states one criterion and leaves three implied, and a list that carries a single blanket label loses which is which. This per-item mark is what §6's **Criteria source** line is built from (R-AC-PROVENANCE), and a derived criterion may never be presented as the reporter's requirement.
   - If the intent still cannot be determined well enough to implement and test -> this is `FEASIBILITY = INFO_REQUIRED`: post the §1.6 **INFORMATION REQUEST** comment (dedupe guard applies) listing the missing items, then STOP and report that acceptance criteria are missing/insufficient.
3. Normalize `ACCEPTANCE_CRITERIA` into a numbered checklist. Each item MUST be verifiable by a concrete executable check (a query result, a screen behavior, a value, a log line, a `liquibase update` result) — something this run can actually execute and quote, not something a reader is asked to take on trust.

4. **DATA_FIX form (ISSUE_CATEGORY = DATA_FIX).** The acceptance criteria of a data fix are always at least these, derived even when the ticket states none — each is verifiable by a query result in the §3.6 dry run:
   1. The rows the ticket reports are corrected (name the documents).
   2. The number of rows changed equals the number of rows the analysis identified as having the issue — no more (Standard 1).
   3. Master/detail rollup, application-total and GL integrity still hold for every affected record (Standards 2–4, whichever apply — each resolved per **Module resolution**, and any that does not apply to this module recorded as `N/A` with its reason).
   4. The script is idempotent and non-committing as delivered (`@ysnCommit = 0`, `<DATAFIX_LOG_TABLE>` guard intact).

RESULT OF §2:
- `ACCEPTANCE_CRITERIA` = numbered, testable checklist. This drives both the implementation (§3, or §3.6 for a data fix) and the **Acceptance Verification** block (§6).
- Each item carries three things §6 cannot reconstruct afterwards: its **verbatim wording** as the ticket states it, its **provenance** (`stated` + where, or `derived`), and its **normalized testable form**. A criterion cached without them forces §6 to paraphrase, which R-AC-VERBATIM forbids.
- **The criteria are an INSTRUCTION, not evidence (R-PREMISE).** Nothing in this section establishes that the behaviour they ask to change is actually wrong — a well-formed, testable, satisfiable criterion rests just as comfortably on a false claim as on a true one. §2.4 adjudicates the claim beneath them before any remedy is considered, and it may end the run.

## §2.4 Premise gate — is the reported behaviour actually WRONG? (R-PREMISE) — mandatory gate before §2.5

**Purpose:** §1.8 proves the symptom **occurs**. Nothing before this point asks whether it is **wrong**. Reproducing "the field shows 100" says nothing about whether 100 is correct — and §2 turns the ticket's acceptance criteria into the thing to satisfy, when **acceptance criteria are an instruction, not evidence**. A run that treats them as evidence delivers a faithful fix for a defect that does not exist, and every gate downstream passes it, because each one checks that the fix is *correct*, never that a fix was *needed*. Ref: an RK ticket delivered to its acceptance criteria and overturned at dev review with *"the reporter's issue is not an issue"* — no gate in this runbook could have caught it, because none of them was asking.

**TRIGGER:** every run that reaches §2. The gate classifies first and exits on the common case, so a self-evident defect costs one recorded line.

### 1. Is the premise in dispute? — `SYMPTOM_CLASS`

From the EVIDENCE_SET, classify into exactly one:

- **`SELF-EVIDENT`** — wrong whoever is asked: an unhandled exception or error dialog; **a failed invariant the SYSTEM enforces or that is established independently of this ticket** (out of balance, master/detail rollup broken, GL not balancing); corrupted or orphaned rows; a duplicate where a key forbids one; a blank or absent render; a hang or timeout; or an output that contradicts **the ticket's own attached evidence**. The behaviour is its own authority.

  **The invariant clause is the loophole this classification is most often lost through (measured on RM-13191).** Every premise-dependent ticket asserts an invariant — *"Book Value must equal Calculated Book Value"*, *"the sub-book should not appear before the filled date"* — because asserting one **is** what having a premise means. A run that accepts the ticket's own assertion as the invariant classifies the case `SELF-EVIDENT`, skips this entire gate, and arrives at exactly the outcome the gate exists to prevent. **An identity qualifies here only when something other than the ticket says it must hold**: the schema enforces it, an existing check or test asserts it, the module's published standards state it, or it is arithmetic (a total against its own lines). *Two named quantities ought to be equal* is a **claim**, and it goes to the ladder.
- **`PREMISE-DEPENDENT`** — wrong only if someone's expectation is right: a computed value, a label, a sort order, a default, a rounding or precision, whether a field or row is shown, when something happens relative to something else, or which of two defensible readings a rule takes.

`SELF-EVIDENT` → record `PREMISE = CONFIRMED (self-evident: <class>)` and continue at §2.5. The rest of this section does not run.

**A ticket asserting a value is wrong is `PREMISE-DEPENDENT` however confidently it is stated, and whoever states it.** Confidence is not authority; neither is seniority, nor being the customer.

### 2. The authority ladder — `PREMISE_AUTHORITY`

Walk in order, stop at the first rung that answers, and record which rung answered and what it said. **A1, A1b, A2 and A3 can refute the ticket. A4–A5 can only contest it** — and A1b refutes only under the two conditions in its own step (a covering version, and a positive showing rather than an omission).

**A1 — a specification page, baselined on this branch.** Specifications live on iNet, one Confluence space per module (`RM` = i21 Risk Management, `AP` = i21 Purchasing, …), resolved from **the repository this run already resolved** — never from the Jira project key.

1. Scope, then search the current version: `space = <MODULE_SPACE> AND type = page AND text ~ "<screen | object | computation>"`. Confluence indexes **only the current version** — history is never searchable, it is fetched (step 5).
2. **Pin what you cite: page id *and* version number.** A page is mutable; a verdict citing a title is unfalsifiable a month later.
3. Read the page's **baseline table** where it has one — `Baselined on <branch>`, plus the per-branch `verified <date>` / `not verified` grid.
4. **A page is authority only on a branch it is baselined and verified for.** Baselined on the ticket's branch → A1 answers. Baselined elsewhere, or carrying no baseline table at all → the page is a **pointer to confirm against the code**, never authority on its own, and **A1 does not answer**. Measured 2026-09-08: **1 page of 3,710** in `RM` carries a baseline table, so *pointer* is the expected outcome today and *authority* is the exception. A page becoming authority is what baselining buys.
5. Where the code's date matters — the page changed around the disputed construct's introduction — fetch the page **as it stood** then, by id and version, and read the diff. **An edit after the code is ambiguous in both directions:** the specification may have moved on (the code is stale — a real defect), or someone may have updated the page to describe what the code already did (documentation catching up — no authority at all). The edit's author and comment decide which. **The timestamp alone never does**, and a run that orders the two dates and stops has proved nothing.

**Transport — steps 1–4 and step 5 are not reachable the same way (measured 2026-09-09).** Steps 1–4 work through any Confluence search the host offers. **Step 5 does not**: the Confluence MCP tool accepts a page id but **no version**, so a run holding only that tool cannot read a page as it stood, will skip the check without noticing, and lands on `UNVERIFIED` where authority was in fact available. The history reads go through the REST API with the stored service credential — `GET /wiki/rest/api/content/<id>/version` for the list, then `GET /wiki/rest/api/content/<id>?status=historical&version=<n>&expand=body.storage` for the body of that version. Verified on `RM/701006713`: `v1` (2026-08-28) 14,173 bytes, no baseline table; `v2` (2026-09-08) 15,629 bytes, baseline table present. **That pair is the worked example of the ambiguity above** — the page changed *after* the code it describes, and the diff shows the edit **added a baseline table** rather than altering a rule: documentation catching up, no authority moved. A run comparing the two dates and stopping would have called the code stale. No credential configured → record `A1 partial — current version only, history not reachable` and continue; **never report an unread history as an unchanged one.** The credential is read from the configured location and never echoed into a comment, a command line the transcript captures, or a repository.

**A1b — a customer SOP the reporter cited (R-SOP-EVIDENCE, §1 step 6a).** An `SOP-<n>` named on the ticket resolves to the customer's signed-off procedure: the screens in order, the configuration, the expected values, and a screenshot of each step's end state. It ranks **above A2** — a consultant specified this process *for this customer* and the customer accepted it, where a test assertion only records what the code currently emits — and **below A1**, because it describes a business process rather than the module's specification.

1. **Version is to an SOP what baselining is to a specification page.** The record carries `strVersionNo`; compare it with `TARGET_BRANCH` as resolved at §1 step 6a. Covering the ticket's line → **A1b answers**. Written against a materially older line → the SOP is a **pointer to confirm against the code**, exactly as an unbaselined page is, and **A1b does not answer**.
2. **An SOP may refute only by positively documenting different behaviour — never by silence.** These documents show the happy path and their coverage is uneven (measured: one step of `SOP-1334` carries 70 images, another 449 characters). *The SOP does not mention this* is therefore worth nothing, and reading an omission as a refutation is the R-SOP-ABSENCE failure. A step that positively shows the disputed field, dialog or total holding a different value, on a covering version, refutes; anything less contests.
3. **Cite the step, not the SOP.** Record `SOP-<n> step <k> (<strScreenLink>) — <what it shows>` plus the version compared. An SOP number alone is as unfalsifiable here as a page title without a version.
4. **Where the SOP supports the ticket it is strong confirmation and cheap** — it is the one rung that arrives pre-resolved to screens, which is why §1 step 6a fetches it before §1.6 classifies. Where it was cited but could not be read, A1b is **not reachable** (`A1b not reachable (SOP cited, unread — <ladder failure>)`), which is a gap in the run, not evidence against the ticket.

**A2 — an assertion in a test.** A Zephyr case, unit test or golden-set expectation asserting the **current** output. Whoever wrote the assertion specified the behaviour. Confirm it is present on `TARGET_BRANCH`.

**A3 — an invariant the requested change would break.** Where the disputed value participates in an identity that must hold — a balance, a rollup, a position equal to the sum of its legs, a total equal to the sum of its lines — compute it both ways under §3.9's discipline **before any code is written**. Current behaviour satisfying the invariant while the ticket's expectation breaks it refutes the ticket outright. This is the one rung that needs no document, and in accounting- and position-shaped modules it is usually the cheapest.

**A3b — when the disputed quantity is DERIVED, check the magnitude of its inputs before accepting either side (R-PREMISE-MAGNITUDE, measured on RM-13191).** A money value computed as `price × quantity` — a valuation, an exposure, an extended cost, a market value — carries a units contract, and a unit-scale error in the input produces an output that is arithmetically perfect and physically absurd. **Neither the reported value nor the expected value is trustworthy until the inputs are plausible.** Take the disputed figure apart, divide it back out, and read the per-unit number against the unit it is stored in: RM-13191 reported a ~173M USD book value against a 12,000 KG coffee lot, whose settlement price resolves to **≈3,909 USD/KG** — a per-tonne price sitting in a per-kilogram field, off by three orders of magnitude. Nothing in the report's logic was wrong; the input was. **A run that reproduces a huge number, confirms the code produces it, and never divides it by the quantity has proved only that the arithmetic works.** Where the per-unit figure is implausible for the commodity, currency or UOM, the premise is not merely unverified — the reported *cause* is refuted, the ticket becomes a data question, and the run routes to §1.7d and §3.6 rather than changing a computation that was correct all along.

**A4 — deliberateness: was this behaviour someone's decision?** **Delegates to §3.8 step 1** (`DEFECT_ORIGIN`) — invoked here with a **different input** and a **different meaning**, and both are stated whenever it is used:

- *Input.* §3.8 pickaxes the construct that **causes a proven defect**. Here nothing is proven and no root cause is pinned: the input is the construct that **produces the disputed behaviour**. Where the run cannot yet name one, record `A4 not reachable (no construct isolated)` and go to A5. Never guess a construct in order to reach a verdict.
- *Meaning.* At §3.8 an origin names a **regression**. Here the same origin names a **decision** — but only when the originating ticket's own acceptance criteria **asked for this behaviour**. Read them. An origin whose ticket says nothing about the disputed behaviour is not evidence of intent, and reporting it as such confirms the very premise this gate exists to test.
- *Reuse.* A `DEFECT_ORIGIN` resolved here is cached and **reused** by §3.8 rather than re-pickaxed. Two reads reaching different answers silently is a defect in the run.
- **The relocation trap is more dangerous here than at §3.8 (R-PREMISE-LINEAGE).** A plain pickaxe walks simplified history and stops silently at a moved, split or regenerated path — the AP-24914 case, where the real introducing change stayed invisible through two prior analyses. At §3.8 that costs a wrong regression attribution. **Here a false "no origin found" reads as "nobody decided this deliberately", which pushes the verdict toward proceeding** — the gate fails in exactly the direction it exists to prevent. Run it with `--full-history` across **both path generations**, as §3.8 requires, and record an unresolved search as `A4 inconclusive`, **never** as `no deliberate origin`.

**A5 — consistency.** Do the module's other implementations of the same computation agree with the current behaviour, or with the ticket? Reuse §2.5's sibling enumeration where the same object exists on other lines, and add peer objects computing the same quantity. Current behaviour agreeing with its peers, against one ticket, is evidence — and *the ticket's screen is the outlier* is the reading to **test** first, never the one to assume.

### 3. `PREMISE` verdict — record exactly one

| Verdict | Earned by | What it licenses |
|---|---|---|
| `PREMISE-CONFIRMED` | `SELF-EVIDENT`, or any rung supporting the ticket | continue at §2.5; the authority is named in §6 |
| `PREMISE-REFUTED` | **A1, A1b, A2 or A3** contradicting the ticket (A1b only on a covering version, and only by a positive showing) | **STOP before §2.5** — no branch, no commit, no code. §6.5 E PREMISE CHALLENGE comment carrying the authority |
| `PREMISE-CONTESTED` | **A4 or A5** only, with no A1–A3 authority settling it | **STOP.** Same comment, shaped as a decision request: name the deciding ticket, its author and its acceptance criteria, or the peers that agree, and ask the BA and module owner to choose |
| `PREMISE-UNVERIFIED` | nothing on the ladder answered | conditioned on blast radius — step 4 |

**A4 and A5 may never produce `REFUTED`.** "Someone decided this in 2023" and "eight peers agree" both raise the burden on the ticket; neither settles whether the decision was right. Refusing a customer's ticket on that basis is a judgement this runbook does not hold.

### 4. `UNVERIFIED` is conditioned on blast radius, never on confidence

Run **§3.7 tier 1** now — the static caller graph, which needs no database and no fix — against the object a remedy would most likely touch.

| Blast radius | Disposition |
|---|---|
| **Contained** — no dependent outside the prospective changeset, and the change is reversible by a revert | continue at §2.5 as `PREMISE = UNVERIFIED-PROCEEDING`; the RCA carries the assumption (step 5) |
| **Wide** — a dependent outside it, a shared or cross-module object, a contract change, or anything §2.6 routes elsewhere | treat as `PREMISE-CONTESTED` and **STOP** |

Stated once so it is not re-litigated per run: being wrong on a contained change costs a deleted feature branch, and dev review is the checkpoint that catches it. Being wrong on a wide one costs a propagation cleanup across every line §3.8 would have mapped, plus the customers already on them.

### 5. A proceeding run must say what it assumed (R-PREMISE-ANCHOR)

On `UNVERIFIED-PROCEEDING` the §6 RCA **opens** with the assumption — before the mechanism, in one sentence a reader can reject without reading the fix:

```
**Premise not verified.** This fix assumes <the disputed behaviour> is incorrect. No specification,
test or invariant confirms that: <what the ladder searched and returned>. If the current behaviour
is correct, no fix is needed and this change should be discarded rather than reviewed.
```

**Its position is part of the rule, not presentation.** A reviewer handed a complete, plausible RCA and a pushed branch grades *the fix*; they do not re-open whether a fix was needed. Burying the assumption beneath the mechanism is precisely what makes that anchoring effective.

### 6. Absence is never a signal (R-PREMISE-ABSENCE)

An empty module space, a page with no baseline table, a module whose specifications were never written, a suite that does not cover this, an inconclusive pickaxe, **an SOP that was never cited or could not be read** (R-SOP-ABSENCE): **none of these is evidence the reporter is right.** `UNVERIFIED` is not `CONFIRMED` and may never be reported as one. **Absence is never a signal** — and do not shorten any sweep because the ladder was silent. Every gate after this one stands on its own.

### 7. This gate never writes to iNet (R-PREMISE-READ-ONLY)

One writer per surface. The gate reads specification pages and cites them; it edits none, creates none, proposes none. What the run learned about a specification goes into the §6.9 `KNOWLEDGE-DRAFT` block as a claim to be graded — including, especially, *this page has no baseline table and should have one*.

### Result of §2.4

- `SYMPTOM_CLASS` · the `PREMISE` verdict · `PREMISE_AUTHORITY` = the rung that answered, with its citation (`iNet <space>/<page id> v<version>`, test id, invariant, `DEFECT_ORIGIN`, or the peer objects) — or `none — <what was searched>`.
- `REFUTED` and `CONTESTED` are **terminal for the run**: no §2.5, no branch, no code.
- Carried into §6 (the mandatory **Premise** line), §6.9 (`PREMISE-CONSULTED`), and §2.7, where a refuting authority is a constraint.

## §2.5 Sibling-line alignment — is this fix a port? (R-ALIGN-TO-SIBLING) — mandatory gate before §3

**Why this gate exists (AP-24880, 2026-08-21).** The run diagnosed the unbalanced voucher GL correctly — the AP Clearing debit must use the accrued load-shipment/receipt basis, not the voucher total — and then **authored a novel fix for it**. It did not need to. `fnAPGetVoucherDetailDebitEntry` on the WaMa/CTRM line already carried the load-shipment-cost branch, and the Sucden 26.3 line had simply never received it. The correct implementation existed, on a sibling branch, in the same file, and the run never looked; its own fix was rejected on review and replaced by the port. **A correct diagnosis followed by an invented fix is still a wrong delivery.**

Nothing else in this runbook asks the question. **§1.6 Step 0.1** searches tickets and object history for *this defect* — it finds nothing when the sibling code is merely **more complete** rather than carrying a fix for this JIRA. **§3.8 `FIX_COVERAGE`** does read the object across branches, but it runs after §3.7 — after the fix is already authored — and its vocabulary (`DEFECT` / `PARTIAL` / `FIXED` **for this defect**) has no state for "that line has a branch we were never given"; its step 6 boundary is one-directional besides, treating other lines as gaps to report rather than as code to import. The §1.5 sibling-family tiebreak compares *artifact presence* to pick a base branch, not object bodies. Neither fires when a branch is just behind.

**TRIGGER:** every run whose CHANGESET will alter a **logic object** (SP / function / view / trigger) or a code artifact that also exists on another active line. Skipped with a disclosure for `DATA_FIX` (§3.6 authors a script, not an object body) and for an object that exists on `TARGET_BRANCH` only. **Runs BEFORE the §3 implementation**, on the implicated-path object set §1 already established — that is the whole point: after authoring, the answer changes nothing.

**Fail-closed on the sweep, never on the verdict.** Reaching §3 without a recorded `ALIGN_VERDICT` for every changed logic object is a **§3 FAIL** (same treatment as §3.4). The verdict itself never stops a run — `NOVEL-JUSTIFIED` is a legitimate outcome, it just has to be argued in the RCA rather than arrived at by omission.

### 1. Enumerate the sibling lines (`SIBLING_LINES`)

1. Fresh `git -C <REPO_PATH> fetch --prune`, then list the candidate branches from `git ls-remote --heads origin`: every active line that could carry this object — the mainline `<ver>Dev` / `<ver>Prod` families, every customer family in CUSTOMER_BRANCH_ALIASES, and the adjacent versions above and below `TARGET_VERSION`.
2. Keep the ones that actually hold the file: `git cat-file -e origin/<branch>:<path>`. A branch without the object is `N/A`, not a gap.
   - **Exclude any branch that is a DESCENDANT of `TARGET_BRANCH` (R-SIBLING-NOT-DESCENDANT).** `git merge-base --is-ancestor origin/<TARGET_BRANCH> origin/<sibling>` true means the sibling already contains this line's own future — including, on a re-run or a late sweep, this ticket's own fix. Diffing against it reports the answer back to you as precedent. A sibling is a **parallel** line, never a downstream one.
3. **Search BOTH repos (R-LB-24.1-TARGET).** The same logical object lives in `i21_sqlscripts` for < 24.1 and `i21_Liquibase` for ≥ 24.1; a one-repo sweep will report "no sibling carries this behaviour" when the richer body is sitting in the other repo.
4. Record `SIBLING_LINES` = the branches kept, with their repo. Zero kept → `ALIGN_VERDICT = N/A (single-line object)` and this gate is complete.

### 2. Diff the **body**, not the defect construct

This is the step §3.8 does not perform. Pickaxing the defective construct answers "was this defect fixed there"; that is the wrong question here.

**Diff the CONSUMERS as well as the object (R-ALIGN-CONSUMERS, operator 2026-08-31).** The sibling sweep is not only about the object being fixed. When a line is symptom-free, the difference that makes it so is as often in the **file that consumes** the object — the view, viewmodel or controller that chooses which store, endpoint or xtype to bind — as in the object itself. Add every consumer on the implicated path to the diff set and classify it the same way. Ref AP-24914: `VoucherViewModel.js` binds the account fields, 24.1 and 24.3 bound them differently and did not show the symptom, and a sweep restricted to the failing endpoint could not see that — the run fixed the endpoint instead of the binding, in another team's repository.

```
git -C <REPO_PATH> diff origin/<TARGET_BRANCH>:<path> origin/<sibling>:<path>
```

Classify each sibling by what the diff shows, ignoring the Liquibase wrapper lines (changeset header, `--comment:`, rollback) — those differ by construction and are never evidence of behaviour:

- `IDENTICAL` — same body; nothing to learn here.
- `SIBLING-AHEAD` — the sibling carries branches / predicates / expressions / parameters that `TARGET_BRANCH` does not. **This is the finding this gate exists for.**
- `TARGET-AHEAD` — we carry behaviour the sibling lacks (a coverage gap for §3.8, not a port source).
- `DIVERGED` — both directions; read the sibling-ahead half.

### 3. Decide: port, or novel fix with a reason

Read every `SIBLING-AHEAD` hunk against the **mechanism** §1/§3 pinned — not against the symptom, and not by name-matching a JIRA key. Then record exactly one `ALIGN_VERDICT`:

| Verdict | When | What it obliges |
| --- | --- | --- |
| `PORT-AVAILABLE` | a sibling hunk implements the behaviour whose absence **is** the root cause | The fix is a **port**. Take the sibling body as the starting point — not a fresh edit next to it. Set `PORT_SOURCE = <repo>/<branch>` and run step 4. The RCA MUST name the branch aligned to. |
| `NO-SIBLING-BEHAVIOUR` | every sibling is `IDENTICAL` / `TARGET-AHEAD`, or the ahead hunks are unrelated to the mechanism | Author the fix. Say in the RCA that the sweep ran and found nothing — `none` is only reportable after step 2 actually ran on every branch in `SIBLING_LINES`. |
| `NOVEL-JUSTIFIED` | a sibling holds the behaviour and this run authors something different anyway | **Requires an explicit written justification in the RCA**, naming what the sibling body does that ours deliberately will not, and why the sibling body is unsuitable here (wrong basis, a dependency that cannot land — step 4 —, a contract this line cannot take). A bare preference is not a justification; the AP-24880 failure mode is exactly this verdict reached silently. |
| `N/A (single-line object)` | step 1 kept no sibling | Nothing further. |
| `NOT-RUN (<reason>)` | `DATA_FIX`, or the object has no repo history | Disclose it. Any other reason is a §3 FAIL, not a `NOT-RUN`. |

A port is **not** self-certifying. `PORT-AVAILABLE` changes where the code comes from; it changes nothing about the proof burden — §3.4 (origin trace + reachability), §3.7, §3.9, §3.10 and §3.11 all still run on the ported body exactly as they would on an authored one. A body that is right on the sibling line can still be wrong here.

### 4. Port-dependency check (R-PORT-DEPS) — a port drags its prerequisites with it

A sibling body is more complete because *other work landed there*. Lifting it wholesale imports that work too — half of a feature whose companion changes are not on this branch, arriving under this JIRA's key where nobody is looking for it. AP-24880 again: the aligned body carried an **AP-20381** portion whose companion fixes are not on the Sucden 26.3 line. It was stripped by hand, correctly, with nothing in this runbook to guide the call and nothing requiring the call to be recorded.

The runbook's only dependency check lives in the §3 **TECHNICAL DEBT GATE** and is gated on `ISSUE_CATEGORY = TECHNICAL_DEBT` — so it did not run for AP-24880, which is a `BUG`. **For a ported hunk it runs regardless of `ISSUE_CATEGORY`:**

1. **Enumerate what the hunk references.** Every JIRA key named in the sibling's `--comment:` line and in any comment inside the ported region; and every object, column, UDT, table, parameter, config key and changeset the ported statements touch.
2. **Verify each prerequisite exists on `TARGET_BRANCH` by CONTENT, on the branch.** Objects/columns must resolve exactly (the §J exact-binding check applies — a renamed-but-self-consistent identifier is a MISSING DEPENDENCY). For each referenced JIRA key, prove its own change is present: `git log -S "<the construct it introduced>" origin/<TARGET_BRANCH> -- <path>`, **never `--grep`** — the §1.6 revert-detection rule applies here too, and a revert commit matches the grep as well as the fix does.
3. **Decide per portion of the hunk, smallest separable unit first:**
   - every prerequisite present → **PORT** it.
   - a prerequisite is missing and the portion is **separable** from the fix → **STRIP** it and record `<portion> — excluded: <JIRA/object> not on <TARGET_BRANCH>`.
   - a prerequisite is missing and the portion is **not separable** from the fix → **STOP**. Report a blocked port naming the missing prerequisite and what would unblock it (that prerequisite landing here, or an operator decision to widen scope). Do not ship half a feature to make a voucher balance, and do not paper over the gap by hand-writing a local substitute for the missing prerequisite — that is a novel fix wearing a port's clothes, and it goes through step 3's `NOVEL-JUSTIFIED` row or not at all.
4. **Record every decision in `PORT_EXCLUSIONS`.** Mandatory in the §6 RCA whenever `ALIGN_VERDICT = PORT-AVAILABLE`; `none — body taken whole` when nothing was stripped. Both directions matter: a silent strip is indistinguishable from an oversight at review time, and a silent non-strip ships the half-feature.

### 5. Result of §2.5

- Cache `SIBLING_LINES`, `ALIGN_VERDICT`, `PORT_SOURCE`, `PORT_EXCLUSIONS`. All four are carried into the §6 RCA (**Sibling alignment** / **Port exclusions** lines) and, for a port, onto the §6.7 handoff.
- **PASS** — continue to **§2.6** (the ownership gate), then to §3 and implement, from the ported body when there is one. A port does not carry ownership with it: a body ported from a sibling line is still subject to §2.6 on the line it lands on.
- **FAIL** (no verdict recorded for a changed logic object) — this is a §3 FAIL: return to step 1. Do not branch, do not push, do not post an RCA.
- **STOP** (step 4 blocked port) — no branch, no push; report the blocked port and the missing prerequisite via the §6.5 triage comment.
- When the port lands, validate it on the reported data **per account, not on the batch total** — a balanced batch is reachable by a wrong distribution, so a debit/credit-shaped acceptance criterion is only satisfied when the individual accounts are right. (AP-24880: AP Clearing debited 2,500,000 = 5,000 × 500.00 accrued basis, cost adjustment −750,000, sum 1,750,000 = the AP credit. The totals alone would have passed a wrong distribution too.)

## §2.6 Object ownership gate — may this run change this object? (R-OBJECT-OWNERSHIP) — mandatory gate before §3

**Why this gate exists.** A JIRA's project says where the **symptom** was reported; it does not say who owns the **object that must change**. Shared framework and utility objects are routinely consumed by a module that does not maintain them, and an edit committed on a `<module>_<JIRA>` branch silently asserts ownership the module may not have: the reviewers who know the object never see the change, and the modules that depend on it discover it at runtime. **This runbook does not modify a repository file or database object that another module owns** (operator 2026-08-28). It analyzes it, fixes it *as an artifact*, and hands the artifact to the owner.

**RUN POINT — before §3 authors anything.** Ownership used to be settled in §3.8 step 5, which answered the question too late to act on: by then the foreign object had already been edited, and the only remaining choice was whether to disclose it. Every signal this gate reads — the file's path, its callers, its commit history — is **static**: no database, no application, no reproduction is required, and all of it is available the moment §1 step 4 names the implicated objects.

**SCOPE.** `CANDIDATE_CHANGESET` — every artifact the fix is *about to* touch (repository file or database object), taken from the §1 step 4 analysis and the §2.5 alignment. Reading is never gated: this section restricts **writes**, never understanding, and it never narrows the analysis, the reproduction, or the RCA. **Plus `ROOT_CAUSE_WRITER`** — the object that writes the value the defect turns on, which is evaluated for ownership even when this run will not touch it (step 3a).

### 1. Establish the owner from evidence, never from the project key

For each artifact in `CANDIDATE_CHANGESET`, resolve all four signals. Record each one with its numbers — a signal asserted without its count is not evidence.

| # | Signal | How it is read | What it says |
|---|---|---|---|
| 0 | **Repository** | is the artifact in **another project's repository** at all (a different repo under `<REPO_ROOT>` from the one this JIRA resolves to)? | **this one signal is dispositive on its own** — a repository boundary is categorically stronger evidence than a path inside our own repo, and it yields `FOREIGN-EXTERNAL` without a second signal (operator 2026-08-31) |
| 1 | **Location** | *within this repository* — is the file under a module-owned path, or a shared one (e.g. `i21Database/dbo/Functions`, `logic/functions`)? | a shared path is the first signal, never the verdict — shared paths hold plenty of single-module objects |
| 2 | **Caller distribution** | count referencing objects by observed prefix (`uspAP*` / `fnIC*` / …), repo-wide plus `sys.sql_expression_dependencies` when a DB is connected | the module owning the clear majority is the de-facto owner |
| 3 | **Change history** | the JIRA key on **every** prior commit to the file (`git log --follow --format=%s -- <path>`) | **a file only ever changed under one project's keys belongs to that project**, whatever project is reporting now |
| 4 | **Who writes the bad rows** | the object that actually produces the defective data (§3.4 Proof 1's `w0` when it is already known) | may be a different module from the one that surfaces the symptom |

`OBJECT_PREFIX` (Module resolution) is the cheap tripwire that sends you here: an implicated path whose objects carry a prefix **other than** the ticket's own project is the signal — report it, never normalize it away.

### 2. Verdict — `OWNERSHIP_ROUTE`, one per artifact

| Verdict | Condition |
|---|---|
| `OWNED` | **no** signal points to a project other than `JIRA_PROJECT`. Absent evidence is not a foreign signal: a file this run's own JIRA creates has no history and no callers, and that is `OWNED`, not undetermined |
| `FOREIGN-SHARED` (**Tier 1**) | the artifact is **in this repository**, and **two or more** signals point to the same other project, **at least one of them signal 2 or 3** — the two that are hard evidence. This JIRA's own project is among the consumers. Location alone never carries it |
| `FOREIGN-EXTERNAL` (**Tier 2**) | **signal 0 fires** — the artifact lives in another project's repository — **or** every readable signal names the same other project and this JIRA's project has no consumer relationship to the object. Signal 0 carries this verdict alone |
| `UNDETERMINED` | the signals **conflict** (e.g. shared path + foreign caller majority, but this project's keys throughout the history), or signals 2 and 3 are both unreadable |

**`UNDETERMINED` is held exactly like `FOREIGN-EXTERNAL` — fail-closed on the write, never on the analysis** — and is reported as `UNDETERMINED`, never dressed up as either answer. An object whose owner nobody can name is precisely the object an unreviewed edit does the most damage to. An operator may lift a hold for a specific run; the runbook never lifts it for itself.

### 3. What each verdict changes — and what it does not

**Two tiers, two behaviours — decided from the signals, never from a prompt (operator 2026-08-31).** The old gate had one behaviour for both, and it was wrong in both directions: it held a shared object this project genuinely consumes, and it authored a fix for a wholly foreign one.

| Verdict | Repository | §4 / §5 | Fix authored? | Handoff |
|---|---|---|---|---|
| `OWNED` | ours | run normally | yes, in the repo | `READY-FOR-PR` |
| `FOREIGN-SHARED` (Tier 1) | ours | **run** — branch, commit, push | yes, in the repo | `READY-FOR-PR` **carrying the ownership marker** (§6.7). **The owning project's reviewer is a REQUIRED reviewer, and no PR may be raised until that is set** — this runbook raises none, so the obligation travels on the handoff line and is stated in the RCA. The alternative, stated as an option for the reader, is to hand the pushed branch to the owning team to raise under their key |
| `FOREIGN-EXTERNAL` (Tier 2) | **theirs** | **skipped** — no branch, no commit, no push | **no** — stop at the diagnosis | `ROUTING-REQUIRED` |
| `UNDETERMINED` | either | **skipped** | **no** | `ROUTING-REQUIRED` |

**No mid-run prompt, ever (R-NO-OWNERSHIP-PROMPT, operator 2026-08-31).** This gate self-decides from the signals and records the decision. A run never asks the operator whether to branch, commit, push or hand off a held artifact — not in a scheduled run and **not in an interactive one either**, which is where the rule was previously silent. A question put mid-run re-opens a decision the evidence has already closed, and the answer is not reproducible on the next run. Note that **no pull request is created by this runbook in any branch of this gate** (§6.7) — a prompt offering one is offering something the runbook cannot do.

**Neither tier stops the understanding.** Reproduction (§1.8), root cause, origin trace (§3.4), regression impact (§3.7) tier 1 and lineage (§3.8) run in full on both. Items 1–6 below describe the **held** route — Tier 2 and `UNDETERMINED`:

1. **Nothing under `REPO_PATH` is modified, and no fix is authored (operator 2026-08-31, superseding the author-outside-the-repo rule).** A `FOREIGN-EXTERNAL` run **stops at the diagnosis**: full reproduction, root cause, origin trace, lineage and evidence — naming the owning project, the exact artifact and lines, and the introducing commit — and then nothing further. No working-tree edit, no assembled `<JIRA>Patch.sql`, no diff. The owning team writes its own fix from the analysis, which is the part they actually need and cannot cheaply reproduce. A fix authored here costs the run its most expensive hours and produces a change the owning reviewers did not ask for and this project cannot merge: ref AP-24892 — 59 minutes and 105M input tokens spent authoring nine-field diffs plus Architect metadata for an `i21_entity` view, on a ticket whose analysis was the whole value. **`UNDETERMINED` is held the same way.**
2. **Fail-closed proof, at the end of §3:** `git -C <REPO_PATH> status --porcelain` must show **no** entry for any held path. A held path found modified is a **§3 FAIL** — revert it (`git -C <REPO_PATH> checkout -- <path>`), report it, and re-author into the patch. "I edited it only to test it" is exactly the failure mode this check exists to catch: an untracked scratch edit is one `git add -A` away from being committed.
3. **§4 and §5 are skipped for the held artifacts** — no branch, no commit, no push. A run whose `CANDIDATE_CHANGESET` is entirely held produces **no `<FEATURE_BRANCH>` at all**.
4. **Mixed changeset — separable or not.** When some artifacts are `OWNED` and others held: if the owned part is a **complete, correct change on its own**, it proceeds normally through §4/§5 and the held part ships as the patch + routing note. If the two are **inseparable** — the owned edit is meaningless, or wrong, without the held one — **the whole run holds**: no partial branch. A half-fix pushed under this JIRA's key reads as delivered and is not.
5. **§3.10 does not run for a held artifact (operator 2026-08-31).** It used to be mandatory here — that followed from authoring the body, which Tier 2 no longer does. The §6 patch line reads `N/A — artifact held by §2.6 (<verdict>); no fix authored, diagnosis delivered`. §3.10 remains mandatory in the §1.7b `DEPLOYED-STALE` case and for `OWNED` / `FOREIGN-SHARED` database objects, which are authored normally.
6. **§6 still posts the full RCA** (see the §6 PRE-REQ), carrying the **Object ownership** block: the verdict, all four signals with their counts, the routing options, and a plain statement that the fix is delivered as an applyable artifact awaiting the owning module's review rather than as a commit.

### 3a. The root-cause writer is in scope even when this run will not touch it (R-WRITER-OWNERSHIP, dev review 2026-08-31; ref AP-24889)

`CANDIDATE_CHANGESET` answers *may we edit this file*. It does not answer *whose behaviour caused this*, and on a consumer-side fix those are two different objects: the edited one is ours, the causing one is somebody else's. A gate reading only the changeset therefore returns a clean `OWNED` and clears the run on the very ticket where ownership decides the remedy.

**So resolve signals 0–3 for `ROOT_CAUSE_WRITER` as well** — the object that writes the value the defect turns on (§3.4 Proof 1's `w0`, or the recurring writer §1.7d named) — even though no edit is proposed for it. The four signals are static; it costs the same reads.

| `ROOT_CAUSE_WRITER` | Reading | What changes |
|---|---|---|
| `OWNED`, or no writer distinct from the edited object | cause and cure are both ours | nothing — proceed as normal |
| any `FOREIGN-*` or `UNDETERMINED` | **the cause is another module's behaviour and our object is a victim consumer** | `DIRECTION-UNDECIDED` — below |

**`DIRECTION-UNDECIDED` holds neither the write nor the branch.** The edited object is ours; §3, §4 and §5 run normally and the fix is pushed. What it holds is the **claim**. A consumer-side change to a value another module asserts is one of at least two defensible remedies, and choosing between them is that module's call, not this run's:

1. **The RCA states the options and self-selects none.** At minimum: *the writer is wrong, and is corrected or exempted at source* (their change) versus *the writer is right, and every consumer bound to the old value moves* (our change — applied across **all** of those consumers, which the RCA must enumerate). A fix applied to one of five bindings is a divergence, not a standard, and shipping it as though the question were settled is what this rule exists to stop.
2. **The pushed branch is a candidate, not the fix.** §6.7 carries the `decision-required` marker and no PR is raised until the owning module answers.
3. **The question is asked once.** When a sibling ticket already waits on the same decision (§1.7d step 7 is what finds it), point at it rather than re-opening it here.
4. **R-NO-REHOME still holds** — this gate moves, creates and reassigns nothing.

### 4. The ticket does not move (R-NO-REHOME)

**This gate re-homes nothing.** It does not create a ticket in another project, does not change `<JIRA>`'s project, does not reassign it, does not transition it, and never drops the analysis. `<JIRA>` stays exactly where it is, with the full root cause, the evidence and the patch on it. What the gate produces is a **routing question for a human**, stated in the RCA with the evidence behind it:

- raise the change under the owning project's key and link back to `<JIRA>`; or
- keep it here and have the owning module review the patch; or
- route the whole ticket.

**The runbook does not decide this and does not act on it.** Ownership is also never a substitute for the analysis: this gate may not send a run back to `CANNOT-FIX`, and it may not be invoked before the defect is understood. The §1.6 failure mode — an early "not our module" verdict producing a won't-fix → reopen loop — is not cured by moving the ownership check earlier; it is cured by keeping it a **write gate** rather than a **work gate**.

### 5. Result of §2.6

- Cache `OBJECT_OWNER` and `OWNERSHIP_ROUTE` per artifact, with the four signals and their counts. All of it is carried into the §6 RCA (**Object ownership** line), the §6.6 label and the §6.7 handoff.
- **All `OWNED`** — continue to §3 unchanged. Record `ownership: OWNED (<signals>)` in the run output. A run that reaches §3 without a verdict per candidate artifact is a **§3 FAIL**, the same way a missing `ALIGN_VERDICT` is: the check is worthless once the edit exists.
- **Any `FOREIGN-*` / `UNDETERMINED`** — take the tier routing above, and re-confirm the verdict against §3.8's lineage once it runs (it reads the same commits; a disagreement between the two is a run defect, not a footnote).
- **Any `FOREIGN-*` verdict on a symptom raised by a screen or object this project owns — return to §3.4 Proof 1 BEFORE authoring anything** (R-ORIGIN-BINDING, operator 2026-08-31). *Our screen, their file* is not primarily an ownership fact; it is evidence that the causal chain was followed one hop too far and the run is standing on a symptom layer. Re-run the origin trace with that in mind and record the outcome. Ref AP-24914 — the AR-owned endpoint was where the error was *raised*; the wrong choice was made in the AP-owned viewmodel that bound to it, and the foreign verdict was the tell nobody read.

> **Worked example — AP-22786.** The eventual fix landed in `fnMultiply`: a shared path (signal 1), **214 callers — 143 IC, 9 AP** (signal 2), and **every prior change an IC ticket** (signal 3). Three signals, two of them hard evidence, all naming IC on an `AP-` ticket. The object is **in our own repository** and AP is genuinely one of its consumers (9 of 214 callers), so under the tier split (operator 2026-08-31) this is **`FOREIGN-SHARED` — Tier 1**, not Tier 2: the fix is authored, branched and pushed as normal, and what the verdict adds is the obligation that **IC's reviewer is required before any PR is raised**, carried on the §6.7 handoff and stated in the RCA. Under the *old* ordering ownership was settled in §3.8 after the push and merely disclosed; under the first version of this gate the object was held entirely, which was stricter than the evidence warranted for a shared object we consume. Contrast **AP-24892**, where the artifact was an `i21_entity` view in **another repository** — signal 0, `FOREIGN-EXTERNAL`, Tier 2, diagnosis only and no fix authored.

## §2.7 Remedy selection — which fix, and why not the others (R-REMEDY-SELECT) — mandatory gate before §3

**Why this gate exists (measured across the graded corpus, 2026-09-05).** Of the six graded tickets on which a remedy was actually delivered or recommended, **four fell short — and not one of them fell short because the run misread what the system does.** Every failure was a choice about *which fix to make*. Nothing in this runbook asks that question. §1.6 through §2.6 establish the cause, the port question and the write permission; §3 then says *"implement the minimum change that satisfies each acceptance criterion"*, and every gate after §3 validates a change that already exists. The choice itself — writer or consumer, code or data, this site or every site — is made in the gap between them, unrecorded and unreviewed, and that is where the accuracy is lost:

| Ticket | What the run got right | What the remedy got wrong |
| --- | --- | --- |
| CT-17302 run 1 | the price-delete revert behaviour, described accurately | **Wrong layer.** It carried the contract's pricing type through the delete procedure. The value was never lost in the database — it was lost at the consumer, which decides "is this HTA" from a *status* field. QA failed, and run 2 fixed the client |
| AP-24915 | the dropdown binds by screen name, and the row is misnamed | **Not durable.** A patch on a configuration row that another module's deployment sync re-asserts on every build |
| IC-29836 | the paired quantity and UOM columns, and the rows that predate the fix | **Below the module's own standard.** Template-compliant, Standards 1–4 clean, and the IC developer rated it *"half baked and did not follow the IC standards"* |
| CT-17265 | the translation namespaces the columns resolve through | **Incomplete coverage.** The fix closed the visible columns; six hidden ones and Ship Via took three developer follow-ups |

Every one of those is answerable **before** the fix is authored, from evidence this run already holds. None of them is answerable afterwards by any gate in §3.

**TRIGGER: every run that will author, port or recommend a remedy.** That includes a `DATA_FIX` (§3.6 chooses a script over a code change, and that *is* the selection), a Tier-2 diagnosis-only run whose RCA recommends a remedy it will not author, and a `§3.10` patch delivered beside a code fix. Skipped only when the run delivers no remedy and recommends none — an information request, a `CANNOT-FIX`, or a `REPRO-ATTEMPTED-DISPROVEN` stop. Runs **after §2.6** (ownership can rule a candidate out) and **before §3 authors anything**: after authoring, the answer changes nothing, which is the §2.5 lesson applied to the layer rather than to the source.

### 1. Enumerate the candidates (`REMEDY_CANDIDATES`) — at least two, at different layers

The candidates are already on the record. Build the list from work the run has done, not from fresh searching:

| Source the run already has | The candidate it yields |
| --- | --- |
| the **write chain** the analysis established in §1.6 Step 2 — `w0` (the statement that creates the row), then every statement that assigns the value | one candidate **per statement in the chain**: fix at `w0`, or at a later carry point |
| the **binding** or the **comparand** — the file that chose the endpoint, store or xtype, or that compares our literal against somebody's stored value | the **consumer**, as distinct from the object that raised the failure |
| §1.6 Step 2c `DATA_CAUSE`, and §1.7d `DATA_WRITER_VERDICT` where a database was reachable | correct the **stored data**, versus change the **writer** that produces it, versus change the **reader** that binds to it |
| §2.5 `ALIGN_VERDICT = PORT-AVAILABLE` | the **sibling body**, which is a remedy with a working precedent behind it |
| §1.6 Step 2a surviving `ERROR_CLASS` candidates | one remedy per surviving producer, when more than one was left unexcluded |

**A DUPLICATE-EXECUTION defect has no carry gap, and the chain rule must not be applied to it (R-CHAIN-NOT-FOR-CONCURRENCY, measured 2026-09-06).** §3.4 Proof 1's algorithm asks, of each statement, *"was the correct value available and not assigned?"* — it is written for a value that is **missing or wrong**. When the defect is that `w0` ran **twice** and every value it wrote is individually correct — a double post, a re-entrant save, a race — there is no carry gap to find, no `wi` to name, and the rule below would send a compliant run back to §1.6 in a loop it cannot leave. **For this class the chain is the EXECUTION path, not the write chain:** name the statement that admits the second execution, and enumerate candidates at each layer that could refuse it (the caller that fires it, the entry point that accepts it, the object that performs it). Record `ORIGIN_TRACE = N/A — duplicate execution, not a carry gap; entry point = <the statement that admits the second run>` and continue. Everything else in this gate applies unchanged.

**The write chain is IDENTIFIED here and PROVEN in §3.4 (R-CHAIN-BEFORE-CHOICE).** §3.4 Proof 1 is the fail-closed record — it tests the statement this run actually changed against `w0`, and it necessarily runs after there is a changed statement to test. But the chain itself is analysis, not validation, and **choosing a layer without knowing what the layers are is the failure this gate exists to stop.** So build the chain here, by the procedure Proof 1 specifies, and carry it forward: Proof 1 then confirms the authored fix sits where this gate said it should. A run that reaches §2.7 unable to name `w0` has not finished §1.6 Step 2 — go back rather than choosing among layers it has not identified.

**A single-candidate enumeration is not an enumeration (R-REMEDY-ONE-CANDIDATE).** Same rule as R-ERROR-CLASS, one layer up: the first remedy that would make the symptom go away is a *candidate*, not the decision. When the list genuinely holds one entry, record **why no other layer can carry it** — the chain has one statement, or the value has one writer and it is ours — and that sentence is the enumeration. "Nothing else occurred to the run" is not.

**The site where the symptom surfaced is a candidate, never the default.** It is where the reporter was standing, and CT-17302, AP-24842 and AP-24914 are all runs that fixed it because it was the first thing they read.

### 2. Score every candidate on the four axes — each one a check, not an opinion

These are the four properties the measured failures lost. Each is answered from evidence the run holds or with a single command:

| Axis | The question | How it is answered — one line of evidence, recorded |
| --- | --- | --- |
| **DURABILITY** | does the correction survive the next deployment, build and sync — **and can it be gone around?** | **When the defect is behavioural rather than a stored value**, `DATA_WRITER_VERDICT` returns `N/A` and this axis is *not* thereby satisfied: it becomes **can a caller reach the defect without passing the guard?** Enumerate the object's other callers and answer with the count, not with prose. A guard the server also enforces is durable; one it enforces **non-atomically** is not, and saying which is the whole answer. §1.7d `DATA_WRITER_VERDICT`. A candidate that writes a value some recurring writer re-asserts is `NOT-DURABLE` and may not be selected as *the fix* (it may still ship as a labelled stop-gap — §1.7d step 6, §3.10). **A code change is not automatically durable**: a client-side guard on a rule the server does not enforce is bypassed by an import, an API call, or another module writing the same table |
| **COVERAGE** | how many sites of this mechanism does it close, of how many that exist? | `git grep` the mechanism's construct across the implicated objects **and their consumers** on `TARGET_BRANCH` — the count is the denominator, and it is carried to §3.4 Proof 4, which fails the run if the CHANGESET closes fewer than it claims. **For a `DATA_FIX` the sites are rows, not statements**, and §3.4 does not run: the denominator is the §3.11 affected-data sweep, and the same rule holds — a script that corrects the reported documents and leaves the rest of the population is a partial delivery, said so here rather than discovered later |
| **BLAST RADIUS** | who else executes this object, and what breaks if its contract moves? | the caller count, **and it is settled by `git grep` on `TARGET_BRANCH`, never by the index alone**. `by_object` may carry `caller_count` / `caller_modules` from §1.6e, but those count **EXEC sites only** and miss every function, view and inline call (R-KB-CALLER-COUNT, §1.6e step 1) — a measured `0` sat on an object with two live consumers. Treat the index number as a floor, and answer the axis with a grep of **every call shape, not just `EXEC`**. A candidate whose callers span other modules inherits §2.6 and §3.7, and that cost belongs in the comparison rather than in a surprise at review |
| **PRECEDENT** | has this module already said how this is done here? | §2.5 `ALIGN_VERDICT` (a sibling body that works is precedent), §1.6e module facts of kind `constraint` and `conventions`, any `refuted` fact naming this approach, the module's published standard where it has one (R-MODULE-STANDARD), and the prior art §1.6 Step 0.1 already swept. **A `refuted` fact matching a candidate rules that candidate out** — selecting it anyway needs the same written justification `NOVEL-JUSTIFIED` needs in §2.5 |

**An ABSENT standard is not an unresolved constraint (R-MODULE-STANDARD-ABSENCE, measured 2026-09-06).** Read literally, the STOP below turns silence into a blocker: a module whose standard was never published, or whose addendum says nothing about these objects, would leave every constraint permanently "unresolved" and **every data remedy an unconditional STOP**. That is not what the rule is for. **A constraint must have been READ to be unresolved:** no addendum for this module, or an addendum carrying nothing about these objects, is `MODULE-STANDARD: none found (<no addendum | no constraint for <objects>>)` and the run **continues**. The STOP below fires only on a constraint that was actually **read and not satisfied** — a rule someone wrote down, not the silence where one might have been.

**Where the module states a standard this runbook does not carry, the module wins (R-MODULE-STANDARD).** The org-wide Data Fix Standards, the Liquibase standard and the acceptance criteria are the **floor**, never the ceiling. IC-29836 passed every check this runbook makes and still failed the module's own rule about lot quantities and valuation. Before selecting a remedy that writes to a table any `constraint` fact names, read that fact and satisfy it, or record `MODULE-STANDARD: <fact> — <how it is satisfied | why it does not apply>`. Where the module has published an addendum (§3.6 PRE-REQ), it is read the same way. **"The module" is the one that OWNS the object being written, not the one in the Jira key (R-MODULE-STANDARD-OWNER, §3.6; also R-KB-WIDEN, §1.6e step 5)** — a remedy that writes another module's table answers to that module's constraint, and its `owner_module` is in the index beside the caller count this gate already reads. **An unresolved module constraint on a table the remedy writes to is a STOP, not a disclosure.**

**A §2.4 authority is a constraint on this selection (R-PREMISE).** Where the premise gate reached `CONFIRMED` on the strength of a specification page, a test or an invariant, that authority describes behaviour the fix must **preserve**, not merely behaviour the fix was allowed to change. A candidate that would violate it carries the same written justification `NOVEL-JUSTIFIED` needs — naming the authority, its citation, and why departing from it is correct here. Where the gate reached `UNVERIFIED-PROCEEDING`, prefer the candidate that is **cheapest to reverse**: the premise may yet be overturned at dev review, and reversibility is the axis that costs nothing to have been wrong about.

**A remedy that makes the acceptance criterion true BY CONSTRUCTION is not a fix (R-REMEDY-TAUTOLOGY, measured on RM-13191).** Some candidates satisfy a criterion by removing the possibility of failing it rather than by correcting a mechanism: assigning one compared quantity to the other so a difference column is structurally zero; filtering out the rows that differ; coercing an output to the literal the ticket expects; widening a tolerance until the observed gap fits inside it. Each of these **passes §3, passes the Acceptance Verification, and proves nothing** — the criterion has become unfalsifiable, so the check meant to confirm the mechanism can no longer fail. RM-13191 shipped precisely this, and its own RCA said so: *"for priced inventory the report now uses the same Book Value in both columns, so the Difference is zero"* — on a report whose purpose is to show that difference, while the real cause was a settlement price stored at roughly 1000× its true scale. **Test every candidate with one question: if the reported mechanism were entirely absent, would this change still make the criterion pass?** Yes → the candidate is tautological, and it may not be selected. Its appearing as the **best-scoring** candidate is a signal about the ticket rather than about the code: **re-enter §2.4 carrying it as evidence**, because a criterion satisfiable by assignment is almost always a criterion resting on a premise nobody checked.

**The listed patterns are signals to run the test, never the verdict — counter-example RM-13207.** There the criterion *was* a filtering requirement (records with a Value Date after the As Of date must not appear) and the correct remedy *is* a filter, applied to the accrual paths of `uspRKDailyTraderPNLCosts` which had been omitting a cutoff the estimated-cost path already applied. Run the question on it: with the reported mechanism absent — those paths already filtering — the change is a **no-op**, not a pass. **A remedy that is inert when the defect is absent is not tautological, whatever it looks like.** That is the whole discriminator, and it is what separates RM-13207's filter from RM-13191's assignment, which made the criterion pass whether or not anything had ever been broken.

### 3. Select, and record what was rejected

Record exactly one `REMEDY_VERDICT`, and **every rejected candidate with the axis that rejected it**:

```
REMEDY_VERDICT = <layer>:<object/artifact> — selected
  durability: <DURABLE | NOT-DURABLE (<writer>) | N-A (<why>)>
  coverage:   <n of m sites — the m sites named>
  blast:      <caller count, modules>
  precedent:  <PORT (<branch>) | CONVENTION (<fact>) | NONE — first of its kind here>
REMEDY_REJECTED = <layer>:<object> — <axis> — <the observation that rejected it>; …
```

- **A remedy that belongs at a second layer is a COMPANION, not a rejection (R-REMEDY-COMPANION, measured 2026-09-06).** The axes routinely split: coverage and durability favour the deeper fix while blast radius and precedent favour the shallower one, and the honest engineering answer is often *both, in sequence*. Filing the deeper change under `REMEDY_REJECTED` to satisfy "exactly one verdict" **misreports it on a customer-visible ticket** — a reader sees that the run considered the deeper defect and dismissed it, which is the opposite of what happened. Record it instead as `REMEDY_COMPANION = <layer>:<object> — <what it closes that the selected remedy does not> — <this run | a separate ticket>`, and carry it into the RCA beside the selection. One remedy is still *selected*; the companion says what is knowingly left open, which is what §3.4 Proof 4 and the coverage gaps already oblige elsewhere.
- **The rejected list is the deliverable half.** A selected remedy with nothing rejected beside it is indistinguishable from a remedy nobody chose, and it is what leaves a reviewer re-deriving the whole question. It is also what the §6 RCA quotes and what the dev review grades.
- **Rejected on an axis, not on a preference.** "Simpler", "more targeted" and "less invasive" are not axes. If the reason cannot be attached to durability, coverage, blast radius or precedent, the candidate was not scored — score it.
- **A remedy this run selects but will not author** (Tier-2 hold, blocked port, `DATA_FIX` awaiting sign-off) is recorded here exactly the same way. What changes is who applies it, not whether the choice was made and shown.

### 4. Result of §2.7

- Cache `REMEDY_CANDIDATES`, `REMEDY_VERDICT`, `REMEDY_REJECTED`. All three are carried into the §6 RCA (**Remedy selection** line) and into the §6.9 `RUN-GATES` block.
- **PASS** — continue to §3 and implement the selected remedy. `COVERAGE` is carried to §3.4 Proof 4, which proves the CHANGESET closed the sites this gate counted.
- **FAIL (fail-closed on the enumeration, never on the choice)** — reaching §3 without a `REMEDY_VERDICT`, or with a single candidate and no recorded reason why only one layer can carry it, is a **§3 FAIL**: same treatment as a missing `ALIGN_VERDICT`, and for the same reason. The choice itself never stops a run — a novel, single-site, first-of-its-kind remedy is a legitimate outcome; it just has to be argued rather than arrived at by omission.
- **STOP** — an unresolved module constraint (step 2, R-MODULE-STANDARD) on a table or object the selected remedy writes to. Report it and the fact that states it; do not author around it.

## §3 Apply the acceptance criteria (implement + validate) — BEFORE the branch push

Implement the change in `REPO_PATH` so that every item in `ACCEPTANCE_CRITERIA` is satisfied. Then validate. **Only if every applicable check passes with no issue** does the runbook continue to §4.

**ROUTING — any artifact held by §2.6 (`OWNERSHIP_ROUTE` = `FOREIGN-EXTERNAL` or `UNDETERMINED`):** the held artifact is **not edited in `REPO_PATH`, and no corrected body is authored for it** (operator 2026-08-31, superseding the author-into-a-patch routing). Tier 2 stops at the diagnosis, so §J binding, §3.9 and §3.10 have nothing to run against and are recorded `N/A — artifact held by §2.6`. `CHANGESET` contains the `OWNED` and `FOREIGN-SHARED` artifacts — the latter are authored in the repository like any other, with the owning project's reviewer required on the §6.7 handoff; when `CHANGESET` is empty, §4 and §5 are skipped and the RCA is the deliverable. When an `OWNED` edit is **inseparable** from a held one, the whole run holds (§2.6 step 3.4) — no partial branch.

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
- **Sibling-line alignment (§2.5) — MANDATORY before this section authors anything, for every changed logic object.** §3 step 1 says "implement the minimum change"; §2.5 is what establishes whether that change should be **written** or **ported**. Reaching this gate without an `ALIGN_VERDICT` per changed logic object is a **§3 FAIL** — the check is worthless once the fix exists. When `ALIGN_VERDICT = PORT-AVAILABLE`, the §2.5 step 4 port-dependency check (R-PORT-DEPS) is part of this gate **whatever the `ISSUE_CATEGORY`**, and an inseparable missing prerequisite is a STOP, not a disclosure.
- **Remedy selection (§2.7) — MANDATORY before this section authors anything, and it is the gate step 1 above assumes has already run.** "The minimum change that satisfies each acceptance criterion" presumes the layer is settled; §2.7 is what settles it, and it is the only gate that asks whether the *right* fix was chosen rather than whether the chosen fix is correctly built. Reaching this gate without a `REMEDY_VERDICT` — or with one candidate and no recorded reason why only one layer can carry it — is a **§3 FAIL**. Its `COVERAGE` count is the input to §3.4 Proof 4, and an unresolved module constraint (R-MODULE-STANDARD) on a table the remedy writes to is a STOP here, not a disclosure.
- **Origin trace & reachability (§3.4) — MANDATORY for every code/logic CHANGESET, and it runs BEFORE every other check below.** The other gates all assume the fix is in the right place; §3.4 is the only one that tests that assumption. It fails the run when the changed statement is not where the value is lost (Proof 1), when no changed statement is on the reported repro's execution path (Proof 2), or when a fall-through in the touched conditional chain was found and left unreported (Proof 3). A §3.4 FAIL returns the run to §1 — it is never downgraded to a disclosure.
- **Client-tree placement (§3.4a) — MANDATORY whenever the CHANGESET touches a client-side asset, and it runs alongside §3.4, before every other check below.** i21 module repos carry two near-identical ExtJS trees; `universal/` is the served one from **23.1 up**, `app/` is all there is on 22.x and below. A `.js` fix in the tree the branch does not serve compiles, reviews, merges, propagates and changes nothing — and §3.4 Proof 2 will not catch it, because the statement is reachable inside a file nothing loads. A §3.4a FAIL returns the run to §3 to move the fix and re-prove §3.4 on the new path.
- **Regression impact (§3.7) — mandatory when CHANGESET contains a SQL logic object or a code artifact with resolvable callers.** The §3 proof above establishes that the *reported* case is now correct; it says nothing about every other row the same object serves. §3.7 closes that: tier 1 (static caller graph + contract gate) is fail-closed and always runs; tier 2 (golden-set differential) runs when a §1.7 database is available and produces a review-blocking finding on any unexpected delta. **§3.7 requires no application environment** — see below.
- **Object ownership (§2.6) — MANDATORY, and it is the last check before §4.** Every artifact in `CANDIDATE_CHANGESET` carries an `OWNERSHIP_ROUTE`; reaching this gate without one is a **§3 FAIL** (same rule as a missing `ALIGN_VERDICT` — the check is worthless once the edit exists). Then prove the hold held: `git -C <REPO_PATH> status --porcelain` must show **no** entry for any `FOREIGN-EXTERNAL`/`UNDETERMINED` path. One that appears is a **§3 FAIL** — revert it (`git -C <REPO_PATH> checkout -- <path>`) and report it; do **not** re-author it into a patch, because Tier 2 authors no fix (operator 2026-08-31). A `FOREIGN-SHARED` path is expected here — it is fixed in the repository like any owned artifact, and its obligation is the required reviewer on the §6.7 handoff, not a write hold. This runbook does not modify a file or database object another project owns without that project's review.
- **Acceptance verification:** confirm each `ACCEPTANCE_CRITERIA` item is satisfied by the implemented change. Record, per criterion, the three things the §6 block needs: **which change addresses it** (the object/file from the CHANGESET and the behaviour that is now different — R-AC-WHATCHANGED), **how it was checked** (the query run, the screen driven, the `EXEC` issued), and **the concrete evidence** (result, screen behavior, value). A criterion this changeset deliberately does not implement is recorded here as such, with the reason — it becomes `NOT ADDRESSED` in §6, never `NOT TESTED`.

TECHNICAL DEBT GATE (when ISSUE_CATEGORY = TECHNICAL_DEBT):
1. Linter pre-check: run static validation for all changed files; record output.
2. Dependency check: identify every dependency the change requires (types, base classes, interfaces, endpoints, routes, ExtJS classes/components, stored procedures, views, Liquibase tables/columns/changesets, config keys) and verify each exists in the repo or is part of CHANGESET. For UDT/table/column dependencies apply the exact-binding check — a renamed-but-self-consistent identifier is a MISSING DEPENDENCY.
3. Continue only if there are **no new linter errors** AND **all dependencies resolve**; otherwise STOP.
4. **This dependency check is not TECHNICAL_DEBT-only when the change is a port.** Any hunk taken from a sibling line runs step 2 above under §2.5 step 4 (R-PORT-DEPS) for every `ISSUE_CATEGORY`, `BUG` included — plus the referenced-JIRA prerequisite test and the mandatory `PORT_EXCLUSIONS` record, which this gate does not have.

RESULT OF §3:
- **PASS (no issue):** continue to §4 — **unless every candidate artifact is held by §2.6**, in which case there is nothing to commit: go straight to §3.10 (mandatory), then §6, and skip §4/§5.
- **FAIL:** STOP. Report the failing check(s) / unsatisfied acceptance item(s) and the offending file(s)/identifier(s). Do not create the feature branch or push.

## §3.4 Origin trace & reachability proof (R-FIX-AT-ORIGIN) — mandatory gate before §4

**Why this gate exists (AP-24842, 2026-08-12).** The run found a procedure that *could* explain the symptom — a final voucher's `dblGross` was never assigned in `uspAPProvisionalFinalize` — changed it in the two places the assignment was missing, and shipped an RCA asserting that as the root cause. Both statements were wrong for this ticket: the row was created by a **different** procedure, `uspAPDuplicateBill`, whose `MERGE` column list omitted `dblGross` — so the value was already lost before `uspAPProvisionalFinalize` ever ran. Worse, one of the two edited statements is **not on the reported repro's execution path at all** (its enclosing block requires `ISNULL(@receiptId,0) = 0`, and the repro has a receipt), so it could not have affected a single row. The assigned developer identified the real origin and fixed it in one place.

The run stopped at the **first layer that explained the observation** instead of tracing the value to where it originates, and never asked whether the statements it changed actually execute. Neither error is caught by §3.7, §3.8 or §3.9 — those all assume the fix is in the right place. This gate is the missing check.

**Scope:** runs for every CHANGESET containing a code or logic change (ISSUE_CATEGORY = BUG or TECHNICAL_DEBT). Skipped for DATA_FIX (§3.6 is terminal). All three proofs are **fail-closed**: a FAIL returns the run to §1 — do not branch, do not push, do not post a §6 RCA.

### Proof 1 — ORIGIN TRACE (fix where the value is lost, not where it is observed missing)

Mandatory whenever a **value defect** appears **anywhere in the causal chain this analysis establishes** — not only when the *reported* symptom is one: a field is NULL / empty / zero / stale / wrong on a record that should have carried it. Reported symptoms are frequently behavioural (*“cannot unpost”*, *“the tabs freeze”*); the moment the analysis names a stored value as the proximate driver, this proof is armed — including by its own Root Cause paragraph.

**Scoped to the defect, never to the changeset (R-GATE-NOT-SELF-EXCUSED).** A run may not record `ORIGIN TRACE = N/A` on the grounds that the fix it selected contains no value assignment. Ref AP-24960 — *“Origin trace: N/A as a value-write chain — the fix is the Unpost/save guard, not an assignment of dblAmountDue”*, written on a ticket whose proximate cause was a stale `dblAmountDue` the same RCA had already reported twice.

**A binding is a value (R-ORIGIN-BINDING, operator 2026-08-31).** When the symptom is *“the consumer called E and E failed”* — E being an endpoint, a store, an xtype, a service alias, a view name — the defective value is **E itself**, and `w0` is the statement that **CHOSE** E, not E's own body. Trace one hop upstream to the file that made the choice, and ask whether that choice was ever different: on a symptom-free sibling line (§2.5), or earlier in this file's own history (§1.6 Step 0.1). Stopping at E fixes where the failure was *raised* instead of where the wrong choice was *made*. Ref AP-24914: the run proved by HTTP bisection that the AR endpoint threw, and fixed the AR endpoint — re-legalising a Voucher store binding that AP-13793 had already ruled wrong once.

**A foreign fix artifact is itself a symptom-layer signal.** When §2.6 returns any `FOREIGN-*` verdict for the artifact this fix would change, while the symptom is on a screen this project owns, **re-run this proof before authoring anything**: *our screen, their file* usually means the chain was followed one hop too far. Record the re-check and its outcome in `ORIGIN_TRACE`.

**A comparand is a value (R-ORIGIN-COMPARAND, dev review 2026-08-31; ref AP-24889).** When the root cause is *“the predicate does not match the data”* — a join, a filter, an `IN` list or a lookup key comparing a literal in our code against a **stored** column — the defect has two sides, and this proof runs on the **data** side as well as the code side. The literal belongs to this repository; the value it is compared against is somebody's **write**, and `w0` is the statement that wrote it. `N/A — read-path defect, no stored value is wrong` answers a question nobody asked: *nothing is wrong at rest* is not *nothing wrote this*. Enumerate the writers of the compared column exactly as §1.7d does for a stale one — the recurring-writer suspects are identical — because the writer settles three things the RCA otherwise gets wrong: **who owns the remedy** (§2.6 step 3a), **whether the consumer-side change is a fix or a mask**, and **which lines actually carry the symptom** (§3.8 step 2 item 4). Ref AP-24889 — the run proved a view matching `strScreenName = 'Purchase Order'` against a row named `'Purchase Orders'`, recorded the origin trace as a read-path defect with nothing wrong at rest, and shipped a consumer-side fix as settled; the plural name was being re-asserted on every deployment by another module's sync, which made the whole fix direction a cross-team decision nobody had taken.

```
Let V = the defective field, R = the record carrying it.

1. WRITER(R) = the statement that CREATES R — the INSERT / MERGE…INSERT / SELECT…INTO that
   first materializes the row. NOT the statement that later updates it.
2. WRITE CHAIN W = [w0 = WRITER(R), w1, w2, …] in execution order: every statement that
   creates or assigns V on R, from creation through commit.
3. For each wi in order, ask: was the correct value of V available to wi?
      available AND not assigned  -> wi is a CARRY GAP
      not available               -> skip
4. ROOT CAUSE = the FIRST wi that is a CARRY GAP.
   Every later wi is a SYMPTOM LAYER. A change there is drift, not a fix.
5. If the carry gap is w0 AND w0 is a shared helper (duplicate / copy / clone / import
   routine called by several workflows), the fix belongs in w0, and the RCA MUST enumerate
   the other callers that carry the same defect today.
```

- **FAIL-CLOSED:** a value defect may not be closed while `WRITER(R)` is unexamined. If the run never opened the object that creates the row, this gate FAILS — "the column is left at its default NULL" is a statement about `WRITER(R)`, and asserting it without reading `WRITER(R)` is a guess.
- **Sibling-column tell:** when a peer field of the same kind IS carried correctly (worked example, AP: `dblNetWeight` was, `dblGross` was not), the statement that carries the peer **is** `w0`. Find the peer's assignment; the defect is a missing entry beside it. This single check would have located `uspAPDuplicateBill` in one step.
- **N>1 SMELL (hard warning):** if the same assignment must be written in **more than one place** to make the symptom go away, the fix is at the wrong layer. Stop, return to step 1, and look for the common ancestor of those places. Two or more edits of the same assignment may only survive into CHANGESET when the RCA states explicitly why no common ancestor exists.

- **“No surviving child row” is not “no event” (R-ORIGIN-DELETED-CHILD, operator 2026-08-31).** A stale scalar on a parent row whose explaining child rows are **absent** is the signature of a write that happened and a reversal that could not run — not of a write that never happened. Before `WRITER-UNIDENTIFIED` may be recorded, all three of these run: (a) **identity gap** on the child table — `IDENT_CURRENT('<child>')` against `MAX(<id>)`; a gap is deleted rows; (b) **script the reversal path** and test whether it restores the parent by `INNER JOIN` to those child rows — a join-dependent reversal cannot survive their deletion, and that is the mechanism; (c) **arithmetic identity** — does the stale value equal the correct value minus a single child's amount? Ref AP-24960: `dblAmountDue` 1,062.50 = 18,763.69 − 17,701.19, exactly one payment schedule; `uspAPUpdateBillPayment @post = 1` performs that subtraction, both reversal paths `INNER JOIN tblAPPaymentDetail`, 0 detail rows survive for the voucher, and `IDENT_CURRENT` 41173 against `MAX` 40456 showed 717 deleted detail identities. The run that recorded *“WRITER not identified (no payment/prepaid rows)”* had read the absence and stopped.

Record `ORIGIN_TRACE` = `<W as an ordered list> | root cause = <wi> | other callers of w0 = <list or none> | binding re-check = <outcome or N/A> | writer = <object.statement, with the arithmetic> or WRITER-UNIDENTIFIED (<which of a/b/c ran>)`.

- **The chain was built at §2.7, not here (R-CHAIN-BEFORE-CHOICE).** §2.7 needs `W` to enumerate its candidates — a layer cannot be chosen among layers nobody has identified — so this proof's job is to **confirm** that the statement the CHANGESET actually touches is the `wi` that gate selected. A disagreement between the chain recorded here and the one §2.7 scored is a finding, not a re-write: it means the analysis moved after the choice was made, and the choice has to be re-made on the corrected chain.

### Proof 2 — REACHABILITY (prove each changed statement actually runs)

```
For each statement s changed by CHANGESET:

1. GUARDS(s) = every enclosing IF / ELSE IF / ELSE / CASE / WHERE / JOIN predicate between
   the entry point and s.
2. Bind each guard to the REPORTED REPRO's real data — the JIRA steps plus the row values
   read in §1 / §1.7. Not to a hypothetical row.
3. Classify s:
      ON-PATH       every guard evaluates TRUE for the repro
      OFF-PATH      some guard evaluates FALSE for the repro
      UNDETERMINED  a guard depends on data the run could not read
4. At least ONE changed statement MUST be ON-PATH. If every changed statement is OFF-PATH,
   the change cannot affect the reported case -> FAIL.
5. Every OFF-PATH statement is either REMOVED from CHANGESET, or justified in the RCA as
   deliberate coverage of a named sibling path — never left silent.
6. UNDETERMINED is NOT a pass. Either read the data that binds the predicate, or downgrade
   the run to a §6.5 triage comment naming the predicate that could not be bound.
```

- **Zero-row corollary (changed UPDATE / DELETE / MERGE):** state which rows the statement matches for the repro. For every variable in its predicate, confirm that variable is **assigned on the repro's path**. `WHERE <col> = @var` with `@var` unassigned on that path matches zero rows and is the canonical silent no-op — this is exactly how the AP-24842 edit in the load-detail block was dead code.
- A statement that is ON-PATH but whose row count is zero fails this proof the same way.

Record `REACHABILITY` = per changed statement: `<file>:<line> = ON-PATH | OFF-PATH (<guard that fails>) | UNDETERMINED (<predicate>)`.

### Proof 3 — VARIABLE ASSIGNMENT COVERAGE (fall-through defects in the code being touched)

While walking `GUARDS(s)`, audit the enclosing conditional chains themselves:

```
For every variable @v CONSUMED AFTER an IF / ELSE IF chain but ASSIGNED ONLY INSIDE it:

1. Is the chain exhaustive — does it end in a bare ELSE? If yes -> OK.
2. If not, try to construct an input that makes EVERY branch false:
      unsatisfiable -> OK; record the proof
      satisfiable   -> FALL-THROUGH DEFECT
3. For a fall-through defect, report the concrete input that reaches it AND the first
   statement downstream that misbehaves on the unassigned value (zero-row no-op, NOT NULL
   violation, misleading engine error, or a write that lands with a NULL key).
4. An OUTPUT parameter is ALWAYS in scope: callers routinely bind it with Direction=Output
   and no Value, so it enters the procedure as NULL. Never assume the caller seeded it —
   open the caller and check.
```

- A fall-through defect found here is **reported even when it is not this ticket's defect** — under **Related defects found** in the §6 RCA, or as a §6.5 triage comment when the run delivers no fix. Finding it and staying silent is a gate failure.
- The **safe remedy is a fail-closed guard**, never a behaviour change: assert the variable before the consuming tail and raise an actionable error. That converts a silent no-op or a cryptic engine error into a diagnosable one without enabling an untested path. **Whether the fall-through case *should* be supported is a product decision — escalate it, never invent it.**

Record `FALL_THROUGH` = `<none>` or `<variable> @ <file>:<line> — reachable when <condition> — first misbehaviour: <statement>`.

### Proof 4 — PATTERN COVERAGE (R-PATTERN-COVERAGE) — did the fix close every site of this mechanism, or only the reported one?

**Why this proof exists (ref CT-17265).** Proofs 1–3 all reason about the site the fix touched. None of them asks how many *other* sites carry the same defect in the same files. The translated-columns fix was correct at every place it changed and still shipped incomplete: six columns hidden by default in the same view, and a shared lookup resolved through a second namespace, needed three developer follow-ups after delivery. The run had the mechanism; it never counted the sites.

**Scope:** runs whenever §2.7 recorded a `COVERAGE` count — that is, every code or logic CHANGESET. This proof is where that count is *proved* rather than estimated.

```
1. SITES = every occurrence of the mechanism's construct, on TARGET_BRANCH, across:
      - the object(s) the fix changed,
      - every file §2.5 step 2 classified as a CONSUMER on the implicated path,
      - the SERVED_TREE only, for client assets (§1.6 Step 2 item 0).
   Search the CONSTRUCT and the INVARIANT, never the message or the symptom
   (R-ERROR-TEXT-NARROWS applies here too: one wording is not one site).
2. For each site: CLOSED by this CHANGESET | OPEN | NOT-A-SITE (<why it is exempt>).
3. |CLOSED| must equal the COVERAGE numerator §2.7 recorded. A disagreement is a
   FAIL of this proof, in either direction:
      fewer closed  -> the fix is narrower than the run claimed
      more closed   -> the count was wrong, so the denominator is untrusted; re-run step 1
4. Every OPEN site is either brought into the CHANGESET, or named in the RCA under
   "Related defects found" with the reason it is deliberately out of scope
   (a different mechanism, another module's object under §2.6, a deliberate
   narrowing the acceptance criteria state). Never left silent.
```

- **Hidden, default-off and rarely-rendered sites count.** A grid column hidden by default, a screen variant, a second namespace for the same lookup, and a code path only one customer's configuration reaches are all sites. They are exactly the ones a symptom-driven search misses, because the reporter could not see them either.
- **`NOT-A-SITE` needs the reason on the record.** It is the exemption that makes the count honest, and an unexplained one is how a denominator quietly shrinks to match the fix.
- This proof never widens scope across branches — `FIX_COVERAGE` in §3.8 owns the version lines, and the repo boundary in §3.8 step 6 is unchanged. Proof 4 is about **this branch, these files**.

Record `PATTERN_COVERAGE` = `<closed> of <total> site(s) — closed: <list> · open: <list or none> · not-a-site: <list with reasons or none>`.

### Result of §3.4

- **PASS:** all four proofs pass (or are recorded not-applicable with the reason) → continue to §3.5 / §3.7.
- **FAIL:** STOP and return to §1 with the finding. Do not create the feature branch, do not push, do not post a §6 RCA. Report which proof failed and the specific statement/variable/site involved. A Proof 4 failure returns the run to §3 (widen the CHANGESET, or correct the count) rather than to §1 — the fix is in the right place, there is simply less of it than was claimed.

## §3.4a Client-tree placement — is this `.js` in the tree the branch actually serves? (R-JS-CLIENT-TREE) — mandatory gate before §4

**TRIGGER:** the CHANGESET contains any client-side asset (`.js`, view/metadata `.json`, `.scss`/`.css`, `.html` template) in a module repository under `<REPO_ROOT>`. Skipped with a disclosure for a pure SQL / data-fix changeset. Runs **with §3.4 and before every other §3 check**, and is fail-closed for the same reason: it decides whether the fix is in a directory anything executes.

**The defect class it exists to catch.** i21 module repositories carry **two parallel ExtJS client trees whose file names are almost entirely the same** — the legacy `app/` tree and the modern `universal/` tree. On `AP` `origin/24.1Dev` the two share **455 basenames** across 466 and 524 files: `AddInvoiceViewController.js`, `Approval.js`, `Base.js`, every `common/combo/*.js` — so a `git grep` for the symptom's symbol returns the dead file as readily as the live one. A fix authored into the tree the branch does not serve **compiles, reviews, merges, propagates and changes nothing**. There is no build error, no failing test and no bind error to say so, and §3.4 Proof 2 does not catch it either — the changed statement *is* reachable, inside a file the application never loads.

**The version boundary** (verified 2026-08-29 across `AP`, `i21_generalledger`, `i21_inventory`, `i21_accountsreceivable`, `i21_cashmanagement`, `i21_SystemManager`): `universal/` first appears at **23.1** and is present on every line from 23.1 up; on **22.x and below it does not exist** and `app/` is the only tree there is. Commit history says the same thing about which one is alive — on `AP` `origin/26.1Dev` since 2024-01-01, `universal/` took **575** commits and `app/` **15**.

**Detect the tree from the branch; use 23.1 only as the cross-check.** A branch is the authority on its own layout, so the threshold is never hardcoded — it is the sanity test that catches a wrong reading.

1. **Enumerate the client trees on `TARGET_BRANCH`**, never from the working copy (which may be sitting on another branch): `git ls-tree --name-only origin/<TARGET_BRANCH>` → record which of `universal`, `app` exist. Record `CLIENT_TREES`.
2. **Pick `SERVED_TREE`:**
   - Both present → **`universal`**. This is the 23.1-and-up shape.
   - Only `app` present → **`app`**. This is the ≤ 22.x shape.
   - Neither present → this repository has no two-tree split; record `N/A — no app/universal split on <TARGET_BRANCH>` and skip the rest of this gate.
   - **Cross-check against `TARGET_VERSION`.** `SERVED_TREE = app` on a branch ≥ 23.1, or `universal` on one < 23.1, is a **contradiction between the branch and the known boundary** — STOP and reconcile before editing anything, rather than picking whichever is convenient. The right fix in the wrong tree is precisely the outcome this gate exists to prevent.
3. **Confirm with activity, not with belief.** `git log origin/<TARGET_BRANCH> --since=<24 months ago> --oneline -- <tree>/ | wc -l` for each tree present. The served tree is the one taking the commits; a `SERVED_TREE` with an order of magnitude **fewer** commits than its sibling is a §3.4a FAIL, not a footnote — re-derive before proceeding.
4. **Check every changed client file against `SERVED_TREE`.** For each client path in the CHANGESET:
   - Path begins with `<SERVED_TREE>/` → **`PLACED`**.
   - Path begins with the other tree → **`MISPLACED`**. Find the counterpart in `SERVED_TREE` — by basename first, then by the construct the fix touches (`git grep -n '<symbol>' origin/<TARGET_BRANCH> -- <SERVED_TREE>/`) — **move the fix there and re-run §3.4 on the new file**. Reachability was proved against the wrong file and does not carry over.
   - No counterpart exists in `SERVED_TREE` → this is **not** automatically a licence to edit the dead tree. Prove the file is loaded: a reference reachable from a served entry point (`app.js`, `ExtJsLoaderConfig.js`, a `universal/packages/local/*/package.json`, a `requires` / `uses` / `xtype` chain), or — when an `APP_ENV` is reachable — the §1.7c step 3 served-asset diff, which answers it directly (`ABSENT` means the application does not serve it). No such proof → **`UNPROVEN`**, and a §3.4a FAIL.
   - **Editing both trees is not the safe compromise.** It doubles what a reviewer must verify, ships a change into a tree nobody exercises, and destroys the evidence of which edit actually removed the symptom. Change the served one; where the dead tree genuinely also needs it, that is a separate, disclosed, separately justified hunk.
5. **This governs reading as much as writing.** A root cause traced through `app/…` on a 23.1+ branch was read out of a file the customer never loads — the analysis is void even where the fix would have been correct. Whenever §1 or §3.4 quoted a client file, restate the quotation against `SERVED_TREE` before the RCA relies on it.

Record `CLIENT_TREE_PLACEMENT` = `<SERVED_TREE>` + one line per changed client file (`PLACED` / `MISPLACED → moved to <path>` / `UNPROVEN`), plus the two commit counts that settled it.

### Result of §3.4a

- **PASS:** every changed client file is `PLACED` in `SERVED_TREE`, or the repository has no split and the `N/A` was recorded → continue.
- **FAIL:** any `MISPLACED` file left unmoved, any `UNPROVEN` file, or the step-2 branch/version contradiction → STOP, return to §3, move the fix, re-run §3.4. Never push a client fix whose tree was not settled: this is the one defect class this runbook can ship that **passes review, merge, propagation and QA while changing nothing the customer sees**.

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

## §3.6 Data fix authoring, validation, test and rollback (R-DATAFIX) — whenever a data issue is proven, on ANY issue type

**Purpose:** produce a data-fix script that corrects the reported rows, prove on the real database that it corrects exactly those rows and nothing else, and **leave the database unfixed** — the same discipline §3.5 applies to schema changes. Deployment to the customer is a separate, human-owned act.

**SCOPE — the issue type does not gate this section (operator 2026-08-31).** This section is reached two ways: `ISSUE_CATEGORY = DATA_FIX`, **or** any other issue type on which §3.11 proved rows are already wrong. Nothing in the PRE-REQs below depends on the issue type — they ask for a usable database, a matching build and the policy sources, all of which a `Bug` satisfies. A run that has proven bad rows delivers the script **on the ticket in hand**; it does not withhold it pending someone else raising a `Data Fix` JIRA. What does **not** change with the issue type: the script ships with `@ysnCommit = 0`, the template's log / idempotency / TRY-CATCH machinery stays intact, the database is left unfixed, and **Senior BA sign-off remains the gate** — this runbook never self-approves and never applies a data fix. Where a code fix ships alongside, the RCA takes the §6 **COMBINED form**.

**PRE-REQ (all mandatory — any miss is a STOP):**
- `FEASIBILITY = DB_REQUIRED-ACTIONABLE` and §1.7 has produced a usable database (R-DATAFIX-DB — a data fix is never authored without the data).
- §1.7 step 2.6 passed: `DB_BUILD_VERSION` is known and its `<main>.<major>` matches `TARGET_VERSION`.
- The policy sources have been read and are applied in full: **Data Fix Standards (All Modules)** (page 705168896 — the baseline this section restates), the **JIRA Datafix Template** (page 434602044), and **the addendum for `MODULE_PREFIX`** where one is published (Accounts Payable's is the **Data Fix Guidelines**, page 503382346). Record which pages were read; where the module has no addendum, record that too rather than silently reading another module's. **A module with no published addendum is not a module with no standard (R-MODULE-STANDARD, §2.7).**  Read the knowledge base's facts of kind `constraint` and `conventions` for `MODULE_PREFIX` and for every table this script writes to (§1.6e step 5), and satisfy each or record why it does not apply. Ref IC-29836 — the script passed the template, passed Standards 1–4, and was rejected as *"half baked and did not follow the IC standards"*, because IC requires a lot-quantity change to be checked against valuation data and processes and nothing in the org-wide baseline says so. An unresolved constraint on a table the script writes to is a **STOP**.

  **Read the OWNING module's standard and facts, not just `MODULE_PREFIX`'s (R-MODULE-STANDARD-OWNER; also R-KB-WIDEN, §1.6e step 5).** A data fix that writes another module's table answers to **that** module's addendum and its knowledge-base `constraint` / `conventions` facts, not only to the one the ticket is filed under. Name each module whose standard was consulted, the ticket's own included, and record the one that had nothing published — each module consulted gets its line in the §6.9 `KB-CONSULTED` block. A widen that found nothing and a widen that never happened produce identical scripts, and only one of them is a gap.

  **The STOP fires on a constraint READ AND NOT SATISFIED, never on an absent one (R-MODULE-STANDARD-ABSENCE, §2.7 step 2).** No published addendum for this module, or an addendum carrying no constraint for these tables, or no base / no `constraint` fact for these tables, is `MODULE-STANDARD: none found (<no addendum | no constraint for <tables> | base absent>)` and the script **proceeds**. Silence where a rule might have been is not an unresolved rule (R-KB-ABSENCE), and reading it as one turns every data fix on a module without a published addendum into an unconditional STOP.
- **Module resolution** has produced `MODULE_PREFIX` and `DATAFIX_LOG_TABLE`; and for every table the fix will write to, either its `MASTER_TABLE`/`DETAIL_TABLE` pair and `ROLLUP_RULE`, or an explicit `N/A` with the reason. An unresolved `ROLLUP_RULE` on a table the fix writes to is a STOP, not an `N/A`.

### 1. Author from the template — never from scratch

The script MUST be the JIRA Datafix Template verbatim, with only the designated regions filled in. The template supplies, and the delivered script must retain unmodified:
- the `<DATAFIX_LOG_TABLE>` create/alter block (audit trail) — **retargeted to this module's own log table**, `tbl<MODULE_PREFIX>DataFixLog`. The data-fix log is **per module**: each module keeps its own audit trail, so the template's shipped table name is replaced with the resolved one, never kept. Step 1a below is how it is resolved, and how it is created when the module has none yet,
- `BEGIN TRY / BEGIN TRANSACTION … END TRY / BEGIN CATCH … ROLLBACK` (automatic rollback on any error),
- the **idempotency guard** — an existing `<DATAFIX_LOG_TABLE>` row for this `@fileName` raises and aborts, so the fix cannot be applied twice,
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

Everything the fix does goes inside the template's `BEGIN DATA FIX HERE` region, in this order (the standards page, "Standards 1–4"):

### 1a. Per-module data-fix log — resolve it, and create it when the module has none

The data-fix audit trail is **per module**: `tbl<MODULE_PREFIX>DataFixLog`. Accounts Payable has
`tblAPDataFixLog`, Inventory has its own, and a module applying its first data fix has none yet. The
template ships one module's name; that name is not authority for this run.

1. **Discover before deciding.** `SELECT name FROM sys.tables WHERE name LIKE 'tbl%DataFixLog'` on the
   connected database. The result is the only authority on what exists. Record the full list in the run
   output — it is also what step 3 copies a column definition from.
2. **A log table already exists for `MODULE_PREFIX` → use it exactly as it is.** Do not rename it, do not
   "correct" its casing, do not add a second one alongside it. If the existing name does not match
   `tbl<MODULE_PREFIX>DataFixLog`, **use the name that exists** and report the deviation: that table is
   the record of every data fix the module has ever applied, and a parallel one silently splits the
   audit trail in two, leaving each half's idempotency guard blind to the other.
3. **No log table for this module → the script creates it**, under exactly `tbl<MODULE_PREFIX>DataFixLog`,
   with the **same column definition as an existing module's log table on this same database**. Script one
   out and copy it — `strJIRAId`, `strAuthor`, `strRemarks`, `strBuildNumber`, `dtmDateExecuted`,
   `strFileName`, plus its key/identity column and their exact types. Matching an existing table is the
   requirement, not a nicety: a log with different columns is not a comparable audit trail, and nothing
   that reads across modules can read both.
   - The create is **`IF NOT EXISTS`-guarded and sits outside the fix's own transaction**, exactly where
     the template's block already is. It must be re-runnable: whoever applies this script to the customer
     database may run it after someone else's fix has already created the table.
   - The create is the one piece of the script that is **not** rolled back by the step-4 dry run, and that
     is correct — an empty audit table is not a data change. Say so in the delivery comment rather than
     letting a reviewer discover a surviving object after a run that promised to leave the database
     unfixed.
   - **No `tbl%DataFixLog` table anywhere on the database to copy from → STOP.** Authoring the first
     data-fix log schema for the whole product is an operator and Senior BA decision, not an automated
     one. Report the situation and the DDL you would propose; do not execute it.
4. **Every reference in the script points at the resolved table** — the create/alter block, the
   idempotency guard, the `@fileName` lookup, and the log `INSERT`. A guard left pointing at another
   module's table asks "has *that* module already applied a fix with this filename", which is always
   false: the fix then applies twice, silently, and the audit trail records neither attempt correctly.
   This is what fail-check S16 tests.
5. **One fix writes to exactly one log table.** When the affected tables span modules, `MODULE_PREFIX`
   comes from the primary table the analysis keys on, and the other modules are named in `@strRemarks` so
   their owners can find the fix from the single place it is recorded.

### 2. Standards 1–4 (mandatory, from Data Fix Standards (All Modules), page 705168896) — module-neutral form

Standards 2–4 exist because business data in i21 is **relational and derived**: a header carries a
rollup of its lines, a settlement document carries a rollup of what it settled, and a posted document
carries a balanced pair of GL entries. Those three invariants hold in every module — only the table and
column names differ. So each Standard below states the *invariant*, and the tables, columns and formula
it is checked against come from **Module resolution** on this run's own schema.

**Never map a Standard onto a table by name resemblance, and never carry a formula over from another
module.** Both produce a check that runs, passes, and proves nothing — the failure R-DATAFIX exists to
stop.

- **Standard 1 — row-count validation** *(module-independent)*. The **first result set** is the analysis
  script: it identifies the rows with the issue, captures `@numberOfRecordsWithIssues = @@ROWCOUNT`,
  prints the count, and **prints the identifiers** of every affected record — the module's own business
  keys, the ones the ticket and QC recognise (the document number a user would read off the screen, not
  the surrogate `int` id). Every DML then captures `@@ROWCOUNT` immediately, and a mismatch against the
  analysis count `RAISERROR`s and rolls back.

- **Standard 2 — master/detail rollup integrity.** *Applies when the fix touches any quantity/amount
  column on a table that participates in a header/line relationship.*
  Resolve `MASTER_TABLE` / `DETAIL_TABLE` from `sys.foreign_keys` and `ROLLUP_RULE` from the module's own
  posting/recalculation procedure (**Module resolution**). Then verify **before commit** that, for every
  affected master row, the rollup column still equals `ROLLUP_RULE` evaluated over that row's details.
  Tolerance `0.01` on money and quantity (i21 financial columns are `NUMERIC(18,6)`, so an exact
  comparison fails on representation alone). Any variance → `RAISERROR` + rollback.
  - The fix may touch the **detail** side, the **master** side, or both — the check is the same, and it is
    required in all three cases. A fix that corrects a detail row and leaves its header rollup stale is
    the single most common way a data fix creates a second defect.
  - No FK relationship on the connected schema → Standard 2 is `N/A`, and the comment says which table
    was examined and that no header/line relationship was declared for it.
  - *Worked example (AP):* the fix touches `dblTotal` on `tblAPBillDetail`; `sys.foreign_keys` resolves the
    master to `tblAPBill`, and `uspAPUpdateBillTotal` supplies `ROLLUP_RULE` = header total equals
    `SUM(detail total + tax)` per voucher.

- **Standard 3 — application / settlement total integrity.** *Applies when the fix touches an amount or
  quantity on a document that **settles or applies against** another document.*
  Most modules have such a second-level relation — a payment applied to bills, a receipt applied to
  invoices, a shipment applied to a contract, an issue applied to a work order. Resolve the applied-total
  column and its application table the same way (FK graph + the procedure that maintains the total), then
  verify the applied total reconciles to the sum over its applications, tolerance `0.01`. Any variance →
  `RAISERROR` + rollback.
  - The module has no settlement/application layer, or the fix does not touch one → `N/A`, stated.
  - *Worked example (AP):* touching an amount on `tblAPPaymentDetail` requires
    `dblAmountPaid = SUM(dblPayment + dblInterest - dblDiscount)` to still hold across the payment's
    details on `tblAPPayment`.

- **Standard 4 — GL integrity for posted transactions.** *Applies when any affected row is posted and the
  fix changes a quantity/amount.*
  Determine posted state from the module's own flag (commonly `ysnPosted = 1` — confirm the column exists
  on the affected table rather than assuming it). Resolve `GL_MODULE_NAME` **from the data**, not from the
  module's display name: `SELECT DISTINCT strModuleName FROM tblGLDetail WHERE strTransactionId IN (<the
  affected documents>)`. Then, for each affected `strTransactionId`, verify
  `SUM(dblDebit) = SUM(dblCredit)` over active entries (`ysnIsUnposted = 0`, `strModuleName =
  <GL_MODULE_NAME>`), tolerance `0.01`, **and** that the module-side GL total reconciles to the new
  header total. Any variance → `RAISERROR` + rollback.
  - **Why `GL_MODULE_NAME` is read from the data and never written as a literal:** the string stored in
    `tblGLDetail` is set by whichever procedure posted the row, and it does not reliably equal the Jira
    project's module name. A guessed literal matches zero rows, `SUM(dblDebit) = SUM(dblCredit) = 0`, and
    the Standard passes trivially on an empty set — the most dangerous possible outcome for this gate.
    **A Standard 4 check that matched zero GL rows is a FAIL, not a PASS**: report the zero-row match and
    resolve the correct value before proceeding.
  - Affected documents have no GL rows at all → `N/A` with that stated, never an assumed balance.
  - **Preferred approach for posted records:** unpost → fix → repost **through the same stored procedures
    the application uses**, rather than writing to `tblGLDetail` directly. This is module-independent and
    is the rule regardless of which module owns the document. Only fall back to a direct GL update when
    unpost/repost is genuinely not feasible; state that reason in the delivery comment, and Standard 4
    then becomes non-waivable.
  - *Worked example (AP):* an affected posted voucher resolved `GL_MODULE_NAME` to
    `'Accounts Payable'` from its own `tblGLDetail` rows.

**Recording the Standards.** Each of 2–4 is reported as `PASS`, `FAIL`, or `N/A — <reason>`. `N/A` is a
legitimate verdict for a module that lacks the structure a Standard describes; it is **not** legitimate
as shorthand for "did not check", and it is not available for a Standard whose structure exists but whose
derivation was not completed — that case is a STOP (see the `ROLLUP_RULE` rule in **Module
resolution**).

### 3. Additional fail-checks (R-DATAFIX extensions — validated statically on the authored script before it is ever executed)

Each is a hard FAIL: fix the script and re-validate. These exist because an automated author needs guardrails a human reviewer would otherwise supply by eye.

| # | Check | Rule |
|---|---|---|
| S5 | **No unbounded DML** | Every `UPDATE`/`DELETE`/`INSERT…SELECT` must be keyed to the analysis result set (a `#tmpDataWithIssues`-style temp table of primary keys, joined explicitly). A DML with no key-bound `JOIN`/`WHERE` is an automatic FAIL, however correct its intent looks |
| S6 | **Single scope resolution** | The analysis SELECT and the DML must resolve the **same key set** — the DML joins the temp table the analysis populated. Two independently-written predicates that "should" match are a FAIL (they drift, and Standard 1's count assertion then passes on the wrong rows) |
| S7 | **No schema DDL against business objects** | No `CREATE`/`ALTER`/`DROP` on any business object. The ONLY DDL permitted is the template's own `<DATAFIX_LOG_TABLE>` block — **including the `IF NOT EXISTS` create of `tbl<MODULE_PREFIX>DataFixLog` when this module has no log table yet** (§3.6 step 1a). Business-object schema change belongs in Liquibase (§3.5), never in a data fix |
| S8 | **No mass-destructive constructs** | No `TRUNCATE`, no `DELETE FROM <table>` without a key predicate, no `UPDATE` without a `FROM`/`WHERE` binding, no writes across a linked server or another database, no `sp_MSforeachtable`, no dynamic SQL that builds a DML statement from unvalidated input |
| S9 | **Pre-image capture** | Before the DML, `SELECT` the full pre-image of every row about to change into a printed result set (keys + every column the fix will modify, old value labelled). This is the human's undo path and QC's before/after reference; a fix that cannot show what it overwrote is not deliverable |
| S10 | **Posted-record guard** | If any affected row is posted (the module's own posted flag — commonly `ysnPosted = 1`; confirm the column exists on the affected table) and the fix touches an amount/quantity, Standard 4 verification MUST be present in the script. Its absence is a FAIL — not a warning. A Standard 4 block present but matching **zero** `tblGLDetail` rows is equally a FAIL: `GL_MODULE_NAME` was guessed rather than resolved from the data |
| S11 | **Build stamp populated** | `@strCurrentBuildNo` = `DB_BUILD_VERSION` (§3.6 step 1). Blank or hardcoded-to-something-else is a FAIL |
| S12 | **Ships with `@ysnCommit = 0`** | The delivered artifact MUST have `@ysnCommit = 0`. Never hand over a script that commits on first execution — the person applying it to the customer database makes that decision, deliberately, after their own dry run |
| S13 | **§J binding still applies** | Every column/identifier the script references resolves exactly against the live `CREATE TABLE` / `CREATE TYPE` definition on the connected DB (the §3 fail-closed rule, unchanged). A data fix authored against a column that does not exist on this customer's build fails here, not at the customer. **This is also the check that catches a table or column carried over from another module** — the most likely provenance of an identifier that binds nowhere |
| S14 | **No credentials, no customer PII beyond keys** | Printed result sets carry document identifiers and the amounts under repair — never passwords, tokens, or bulk personal data |
| S15 | **Every Standard 2–4 verdict is derived, not assumed** | For each of Standards 2, 3, 4 the script (or the delivery comment) must show **where the verdict came from**: the FK query that resolved the master/detail pair, the procedure that supplied `ROLLUP_RULE`, the `tblGLDetail` query that resolved `GL_MODULE_NAME`. A bare `PASS` or `N/A` with no derivation behind it is a FAIL — it is indistinguishable from a check copied out of another module |
| S16 | **Log table resolved, never inherited** | Every log-table reference in the script — create/alter block, idempotency guard, `@fileName` lookup, log `INSERT` — names `tbl<MODULE_PREFIX>DataFixLog` as resolved in §3.6 step 1a. A script still carrying the template's shipped name from another module is a FAIL. So is a create that is not `IF NOT EXISTS`-guarded, or whose columns do not match an existing module's log table on the same database |
| S17 | **Not a sync-owned value** | A script whose DML writes a value some **recurring writer** re-asserts (§1.7d `DATA_WRITER_VERDICT = RE-ASSERTED`) is a FAIL unless it is delivered as a labelled stop-gap beside the durable route — the correction cannot survive that writer's next execution, and shipped without the label it reads as a resolution. Run §1.7d before authoring any data fix that writes a configuration value |

### 4. Test the data fix on the restored database, then roll back (mandatory)

The proof runs on the §1.7 database. The template's own transaction is the rollback mechanism — the fix is exercised in full and then undone.

1. **Dry run (`@ysnCommit = 0`) — the primary test.** Execute the complete script. Inside the transaction, before the template's tail rolls it back, capture:
   - the analysis result set — the affected-row count and the printed identifiers,
   - the S9 pre-image,
   - each DML's `@@ROWCOUNT` and the Standard 1 assertion result,
   - the Standard 2 / 3 / 4 verification result sets (each must return zero imbalance rows),
   - the **AFTER state of the reported documents** — re-run the §1.7 BEFORE reproduction *inside the open transaction* so the corrected values are observed on the very rows the ticket names. This is the acceptance evidence.
   Then let the template `ROLLBACK`. Confirm `PRINT 'ROLLBACK TRANSACTION'` appeared, and **verify the rollback actually took**: re-run the analysis query after the script ends — the same rows must still be reported as having the issue, and `<DATAFIX_LOG_TABLE>` must contain no row for `@fileName`. A dry run that left data changed is a critical failure: report it immediately and explicitly (never silently).
2. **Scope proof.** Assert `rows affected == rows with issues` (Standard 1) AND that the affected key set equals the analysis key set exactly. A fix that corrects the reported document but touches N other rows is a FAIL, no matter how plausible those N look.
3. **Idempotency check (local restores only, optional).** The `<DATAFIX_LOG_TABLE>` guard only engages when `@ysnCommit = 1`. To prove it, on a **local** restored copy only: run once with `@ysnCommit = 1`, then run a second time and confirm it aborts with `DataFix already applied …`. Then **drop or re-restore that local copy** so no fixed state survives. **Never on a shared `knownServers` database** — the §1.7 shared-server rule stands: a committed data fix on a shared restore corrupts other people's testing.
4. **Failure handling.** Any assertion that raises, any imbalance row, any count mismatch → the script is not deliverable. Revise and re-run from step 1. Do not deliver a data fix whose own assertions have not been observed passing on real data.
5. **The database is left unfixed.** After §3.6 the restored/connected DB is in its pre-fix state, exactly as §3.5 leaves a Liquibase DB rolled back. The actual correction happens when a human applies the script to the customer database.

### 5. Impact analysis and QC briefing (the standards page, "Impact analysis and QC briefing")

Assemble, from what the run actually established:
- **Linked program JIRA** — the code fix that stops the defect recurring (§1.6 Step 2.9.2). If none exists, say so explicitly and state that one is required.
- **Impact Analysis** — which tables/columns change, how many rows, and **which modules consume them: `CONSUMING_MODULES`, taken from the §3.7 tier 1 dependency scan** (`sys.sql_expression_dependencies` plus the repo-wide reference search), never from a remembered list of downstream areas. Plus what was verified to be unaffected. Ground every claim in a query result from step 4. When tier 1 could not run, say so and state the coverage limit instead of naming modules on plausibility.
- **Cross-module owners** — when the affected data is consumed by another module, name the owning team as a required reviewer/approver.
- **QC test pointers** — the areas to test, *not just the symptom column*. Derive them from `CONSUMING_MODULES` and from whichever Standards applied: if the fix changed amounts and removed/added GL entries, the briefing must name the affected documents' GL entries and every rollup or balance downstream of them, not merely the field the customer reported. *(Worked example — AP: an amount change on a payment obliges QC to check the payment's GL entries and the vendor's prepayment balance.)*

### 6. Senior BA review is the gate — this runbook does not self-approve

Per the review gate on the standards page (page 705168896, "Senior BA review is the gate"), a **Senior BA** reviews the script against Standards 1–4 and the fail-checks and posts PASS / NEEDS REWORK / FAIL on the JIRA, and **QC does not begin testing until that sign-off exists**. Where the module publishes an addendum, its own standards are reviewed alongside the baseline. This runbook delivers the artifact and the evidence into that workflow; it never records a verdict on its own behalf, and never states or implies that the data fix is approved.

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
| `UNEXPECTED-DELTAS` | Tier 2: rows outside the defect class changed | **Not a §3 FAIL** — the fix stands, but this is a **review-blocking finding**: named in the RCA with keys and values, label `JIRA-AI-RegressionFlag`, and carried on the §6.7 handoff line so the PR is not auto-completed blind |
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

**When §2.4 already ran this search, reuse its answer (R-PREMISE).** The premise gate's A4 rung invokes this same procedure earlier, on the construct that produces the *disputed behaviour* rather than the one causing a *proven defect* — a different input, and there a found origin means a **decision** rather than a **regression**. Where that read resolved a `DEFECT_ORIGIN` for the same construct, take it: do not re-pickaxe, and where the two constructs differ, say so rather than letting one silently overwrite the other. Two reads of the same history reaching different answers, unremarked, is a defect in the run.

1. Reduce the defect to the shortest string unique to it — the *defective* form, not the surrounding object. (Ref AP-22786: `FLOOR(@factor1)` inside the `@p1` assignment, not `fnMultiply`.)
2. Pickaxe the file's history on `TARGET_BRANCH`, oldest match last:
   `git -C <repo> log --oneline -S "<construct>" origin/<TARGET_BRANCH> -- <path>`
   Use `--follow` when the file may have been renamed. The **earliest** commit that added the construct is the introducing change.
   **Relocations defeat the default pickaxe (R-LINEAGE-RELOCATION, operator 2026-08-31).** `git log -S` walks first-parent simplified history and silently stops at a path that was moved, split or regenerated — which is exactly what a screen re-arrangement or a tree migration does. Run the pickaxe with **`--full-history` across BOTH path generations** (the current path and every prior one `git log --follow --name-status` reveals), and read the two histories together. Then treat the relocation itself as a suspect: **a relocation commit whose content is not carried over verbatim is a candidate introducing change**, and its diff must be read, not assumed to be a move. Ref AP-24914 — the binding regressed inside the AP-22443 / AP-22608 relocation commits; the default pickaxe stopped at the new path and reported the construct as original there, so the real introducing change stayed invisible through two prior RCAs.
3. Extract the JIRA key from that commit's message/PR and read it — cache `DEFECT_ORIGIN` = `<key> | <summary> | <commit> | <date> | <author>`.
4. **Confirm the origin actually reaches this branch:** `git merge-base --is-ancestor <commit> origin/<TARGET_BRANCH>`. A construct that merely *looks* like the one on another branch is not the origin of this one.
5. No JIRA key in the commit message, or the history predates the current repo → record `DEFECT_ORIGIN: not determinable` and continue. This section never stops a run.
6. **Two dated snapshots bound the origin before the pickaxe does (R-DB-CANDIDATE-SET).** When the candidate set holds copies from different dates, read the affected value in each: correct in the older and wrong in the newer confines the introducing write to that window, and each copy's `tblSMBuildNumber` converts the window into a build range — which turns step 2's pickaxe from a whole-history search into a check of the commits in that range. Wrong in the oldest copy available means the origin predates the whole set; say so rather than implying the oldest snapshot dates the defect.

### 2. Map existing fixes across the active lines (`FIX_COVERAGE`)

1. Pickaxe for the **corrected** forms as well as the defective one, across every repo/branch that could carry the object. **Mind the repo split (R-LB-24.1-TARGET):** the same logical object lives in `i21_sqlscripts` for < 24.1 and in `i21_Liquibase` for ≥ 24.1 — a lineage that stops at one repo will report a false gap.
2. For each active version line, classify: `DEFECT` (original form) · `PARTIAL` (a fix exists but does not close every failure mode — see step 3) · `FIXED` · `N/A`.
3. **Verify by CONTENT, never by commit-grep** (the §1.6 revert-detection rule applies here too): read the actual construct on each candidate branch. A `git log --grep` hit proves a commit mentioning the key exists, not that the fix is present — a revert matches too.
4. **Where the symptom is data-dependent, grade `predicate present × writer present` — never predicate presence alone (R-COVERAGE-WRITER-CONDITIONED, dev review 2026-08-31).** When §3.4 Proof 1 or §1.7d identified a writer that must **also** be present for the symptom to appear, a line carrying the defective construct but not the writer does not reproduce, and grading it `DEFECT` overstates the coverage a propagation decision rests on. The extra evidence is one `git grep` for the writer per line. Ref AP-24889 — the menu-name sync is present on 24.2Dev, 26.2Dev, 26.2Prod, 26.3**Prod** and 27.1Dev and absent on 25.2Dev, 26.1Dev, 26.1Prod, 26.3**Dev** and 24.3Dev, so two branches of the same release line grade differently and no reading of the view's own text can show it.

### 3. Never call a line "fixed" from source text alone — build a counterexample (fail-closed)

A fix that *looks* like it addresses the cause may close only part of it. Prove it empirically:

1. Derive the **failure condition** from the root cause (the exact operand range, data shape, or state that triggers it).
2. **Construct an input that actually satisfies that condition** and run it against the supposedly-fixed line. Do not reuse the reported case — the reported case is often *not* the boundary, and a well-chosen-looking example that misses the condition will falsely clear a still-broken line.
3. Only a counterexample that **passes** on that line justifies `FIXED`; one that still reproduces makes it `PARTIAL`, and that is a finding for the RCA.

> Ref AP-22786: the forward line's `LEN(REPLACE(CAST(FLOOR(@factor1) AS NVARCHAR(38)),'-',''))` strips the sign character but leaves the `FLOOR`-away-from-zero half open. A first counterexample (`−999999.5`) came out symmetric and would have wrongly cleared 26.x/27.1 — its product has too few decimals to reach the precision overflow. The operand that *does* satisfy the condition (`−999999.70166666670 × 0.799`, integer part just under a power of ten, ≥ 6 significant decimals) still reproduces the defect on 27.1. Same class of trap as testing a fix on the wrong branch.

### 4. The build-vintage caveat (report it whenever behaviour differs by line)

When the changed object behaves differently across lines, **a reviewer testing on their own database will get a different answer than the run did** and may conclude there is no defect. Whenever `FIX_COVERAGE` is not uniform, the RCA MUST carry a short "check which database/branch you are on first" table mapping vintage → observed behaviour, so a good-faith verification attempt does not produce a false negative. (Ref AP-22786: the same two `SELECT`s return a symmetric result on a 26.x database and an asymmetric one on every Walter Matter 22.1 database.)

### 5. Object ownership — confirm the §2.6 verdict against the lineage (R-OBJECT-OWNERSHIP)

Ownership is **decided in §2.6, before §3 edits anything** — that is the gate, and it is what keeps this runbook from modifying a file or database object another module owns. This step is its confirmation pass, because §3.8 step 1 has just read the one thing §2.6 leans on hardest: the JIRA key on **every** prior commit to the file. **A file only ever changed under one project's keys belongs to that project**, whatever project is reporting now.

1. Re-read signal 3 (change history) from the lineage this section just built, and re-check it against the `OWNERSHIP_ROUTE` §2.6 recorded.
2. **Agreement** — carry `OBJECT_OWNER` into the §6 **Object ownership** line with all four signals and their counts.
3. **Disagreement** — a §2.6 `OWNED` verdict that this history contradicts is a **run defect, not a footnote**. If nothing has been committed yet, return to §2.6 and re-run the gate on the fuller evidence. If §4 already committed the object, **do not push** (or, if §5 already pushed, say so plainly in the RCA and name the branch to retract) and route it as §2.6 step 4 describes.

Everything else about ownership lives in §2.6: the four signals, the verdicts, the write hold, the patch route, and **R-NO-REHOME** — no ticket is created in another project, `<JIRA>` is never re-homed, reassigned or transitioned by this runbook, and the analysis is never dropped.

> This is NOT a route back to `CANNOT-FIX`. Ownership is a **write gate, not a work gate**: the defect is still reproduced, root-caused, fixed as an artifact and proven on a database — never replaced by an assertion that it belongs to someone else (the failure mode §1.6 guards against; ref AP-22786, where an early "not an AP issue" verdict produced a won't-fix → reopen loop, and where the eventual fix landed in a function whose 214 callers are 143 IC / 9 AP and whose every prior change was an IC ticket).

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

## §3.10 Deployable patch artifact — the fix as something a human can apply today (R-PATCH)

**Purpose:** a pushed branch helps nobody until the build ships. When the fix lives in database objects, the run that authored it can also hand over a script that corrects the customer's environment now — assembled from the validated object bodies, executed against a real database, and proven before it leaves. This section produces that artifact. It never deploys it: applying a patch to a customer database is a human-owned act, exactly as §3.6 leaves the data fix to a human.

**TRIGGER:** `CHANGESET` contains at least one database object — stored procedure, function, view, trigger, or table type — whether the repo artifact is a Liquibase changeset wrapping that object or a raw SqlScripts `.sql` on a pre-24.1 branch (`IS_PRE_LIQUIBASE_BRANCH = true`).

**§2.6 held artifacts do NOT reach this section (operator 2026-08-31).** A `FOREIGN-EXTERNAL` / `UNDETERMINED` artifact has no authored body to assemble — Tier 2 stops at the diagnosis — so the §6 patch line reads `N/A — artifact held by §2.6 (<verdict>); no fix authored, diagnosis delivered`. This section stays **MANDATORY, never `N/A`** for the §1.7b `DEPLOYED-STALE` case, where the patch is the entire deliverable. `OWNED` and `FOREIGN-SHARED` database objects are authored in the repository and reach this section normally.

**NOT APPLICABLE — and say so, never silently:**
- A CHANGESET of only application artifacts (C#, TypeScript, `.config`, report definitions) has no applyable script; those changes reach the customer through a build and nothing else. The §6 line then reads `N/A — no database object in this changeset`, verbatim.
- `IS_DATAFIX_CASE = true` is N/A too: the data-fix script IS the deliverable (§3.6), and authoring a second artifact for the same ticket is how two divergent scripts end up in circulation.

An omitted §6 patch line is a **STOP**, in both directions — the trigger fired and no patch was produced, or the trigger did not fire and the N/A was left off. A gate nobody can see a verdict for is a gate that has already rotted.

**RUN POINT.** §3.10 assembles and executes **before §4**, so the execution result in step 3 is part of the §3 evidence and a patch that will not compile is caught before anything is committed — the same placement §3.5's case-C execute-then-restore already uses. Two fields complete later: the header `Commit:` line is filled in once §4 has produced the SHA, and delivery (step 4) happens with the §6 comment, which exists only on a successful §5 push. A patch is never delivered for a run that did not push.

### 1. Assemble `<JIRA>Patch.sql` from whole object bodies — never from the diff

The patch is **each changed object's complete body as the validated CHANGESET leaves it** — the same content §4 commits and §5 pushes — in dependency order: table types → scalar/table-valued functions → views → procedures → triggers. Each body terminated with its own `GO`. A diff hunk is not a patch — a hunk cannot be executed, and hand-stitching one into a body is how an object reaches a customer in a state no branch ever held.

Header block, first lines of the file:

```sql
/* ============================================================
   <JIRA> — deployable patch
   Objects:        <one line per object, schema-qualified>
   Target branch:  <TARGET_BRANCH>      Feature branch: <FEATURE_BRANCH>
   Commit:         <the §4 commit SHA — recorded once §4 has run>
   Coded against:  build <DB_BUILD_VERSION, or "not established — no DB was available">
   APPLY ONLY to a database on build <TARGET_VERSION>.x. Re-runnable.
   This patch replaces object code. It changes no data and no schema.
   ============================================================ */
```

The build line is not decoration. A procedure body from a `24.2` branch applied to a `22.1` database binds against columns that may not exist there, and the failure surfaces at the customer as an error-207 class break — the very thing §J exists to prevent.

### 2. Fail-checks (validated on the assembled script before it is delivered)

Each is a hard FAIL: fix the script and re-validate.

| # | Check | Rule |
|---|---|---|
| P1 | **Bodies come from the validated files, and are re-verified against the commit** | Each body is the complete object as it stands in the validated CHANGESET file under `<REPO_PATH>` (for a Liquibase changeset, the object body that changeset installs) — and once §4 has run, re-verified against `git show <FEATURE_BRANCH>:<path>` so the delivered patch provably matches what was committed. Never hand-assembled, never reconstructed from a diff hunk, never lifted from an editor buffer |
| P2 | **Object set == CHANGESET set** | Every database object the CHANGESET touches is present, and nothing else is. A missing object is the dangerous failure: the patch applies cleanly, the customer believes they are fixed, and the half-patched interaction can behave worse than the untouched original |
| P3 | **No data DML, no schema DDL** | A patch replaces code. `UPDATE` / `INSERT` / `DELETE` against a business table belongs in §3.6; `ALTER TABLE` / `CREATE TABLE` belongs in Liquibase (§3.5). Their presence here means the wrong artifact is being built |
| P4 | **Idempotent and re-runnable** | `CREATE OR ALTER` where the object supports it, else the object's required `IF EXISTS … DROP` + `CREATE` form. Executing the patch twice must leave the database exactly as executing it once — the person applying it will run it again when they are unsure whether it took |
| P5 | **Executed when a database is reachable** | See step 3. `not executed — no database available` is an acceptable delivered state; an unexecuted patch presented as a tested one is not |
| P6 | **§J object binding** | Every column, parameter and identifier the bodies reference resolves exactly against the live `CREATE TABLE` / `CREATE TYPE` definitions on the connected database. Unchanged fail-closed rule — a patch that binds against a column absent from this customer's build fails here, not at the customer |
| P7 | **No credentials, no environment specifics** | No server names, no connection strings, no `USE <database>`, no customer database name. The patch is applied by someone already connected to the right database (R-DB-LEDGER-REUSE) |

### 3. Execute it, prove the symptom is gone, then put the database back

When a database is reachable (the §1.7 restore, or a `knownServers` connection to the reported environment):

1. **Save the pre-fix bodies.** The §1.7b scripted-out originals already exist — reuse them. If §1.7b did not run, script every object in the patch out of the connected database now, to `<liquibaseLogDir>\<JIRA>\prefix-<object>-<UTC timestamp>.sql`. **No pre-image, no execution** — there is no restore path without it.
2. **Apply the patch.** Every object must compile clean: no bind error, no missing dependency, no warning masking an unresolved reference. Capture the console output.
3. **Re-run the §1.8 reproduction on the reported transaction.** The symptom must be gone. This is the acceptance evidence for the patch, and it is a different claim from "the branch contains a fix" — it is the claim that *this script, applied this way,* corrects the reported case.
4. **Restore the pre-fix bodies.** Re-apply the step-1 definitions and confirm the reproduction raises the symptom again. **The database is left unfixed**, exactly as §3.5 leaves a Liquibase DB rolled back and §3.6 leaves a data fix rolled back. A failed restore is a review-blocking finding, reported immediately and explicitly — never noted quietly, never left for the next run to discover.

On a **shared `knownServers` database** the restore is what makes this permissible (the §1.7 shared-server rule stands): the mutation is removed. If the pre-image cannot be captured, or the restore cannot be verified, do not execute — deliver the patch labelled `not executed — shared database, no safe restore path`.

When no database is reachable at all, the patch is still assembled, still validated against P1–P4 and P6–P7 as far as static checking allows, and delivered labelled `not executed — no database available`. State which of P6's bindings could not be confirmed.

### 4. Deliver

1. Save to `<liquibaseLogDir>\<JIRA>\<JIRA>Patch.sql`, with the execution console output alongside it as `patch-apply-<UTC timestamp>.log`.
2. **Attach the `.sql` to the JIRA** by the same route §3.6 step 7.3 uses: the Atlassian MCP has no attachment tool, the Jira REST API does — `POST /rest/api/3/attachment` with `X-Atlassian-Token: no-check` (multipart), using the `atlassian` credentials from §1 step 5. On failure, do not retry blindly: state `<JIRA>Patch.sql at <path> — attach to the JIRA manually` in the run output and in the §6 comment.
3. **Inline it in the §6 comment.** ≤ 200 lines: the whole script in a fenced ```sql block. Larger: each object's header and signature plus the substantive changed statements, and a pointer to the attachment — never a truncated body that reads like a complete one.

### 5. When §1.7b said `DEPLOYED-STALE`, this section is the whole ticket

§1.7b routes a stale deployed body to "deliver a patch/deploy instruction for that object" and forbids authoring a code fix. §3.10 is that deliverable, with one change of source: the bodies come from **`origin/<TARGET_BRANCH>`**, not from a feature branch, because no fix is being written — the fix already exists and has not reached the customer. There is no CHANGESET, no §4, no §5 and no `<FEATURE_BRANCH>`; the header's `Commit:` line names the commit that introduced the newer body, and its JIRA key. Everything else — P1–P7, step 3, step 4 — applies unchanged. **One precondition, added after AP-24915: when the stale thing is a stored VALUE rather than an object body, §1.7d must first have returned `SINGLE-WRITER-NEVER-APPLIED`.** On `RE-ASSERTED` this section is not the ticket at all — the patch is a stop-gap the next deployment reverts, and it ships only with its expiry written on it (§1.7d step 6).

### 6. When §2.6 held the object, this section is the whole deliverable

The §1.7b `DEPLOYED-STALE` case above has a twin: an object this module may not commit to. The mechanics are the same and the source of the bodies is the same — **`origin/<TARGET_BRANCH>` (or the deployed body), plus the fix, assembled outside the repository** — with one difference: here a fix *is* being written, it simply is not being written into someone else's file. There is no CHANGESET entry for the held object, no §4, no §5 and possibly no `<FEATURE_BRANCH>` at all; the header's `Commit:` line reads `none — held by §2.6 (<OBJECT_OWNER>); delivered as a patch for the owning module's review`. P1–P7, step 3 (execute on a restored copy, prove the symptom gone, restore the pre-fix bodies) and step 4 apply unchanged — **the hold restricts where the fix is written, never how well it is proven.** An unexecuted patch handed to another module is a suggestion, not a fix.

## §3.11 Affected-data sweep — what the defect already broke (R-DATA-SWEEP)

**Purpose:** a code fix stops the defect from happening again. It repairs nothing that already happened. Every run that fixes a program defect which *wrote* something therefore leaves an open question — how many rows are already wrong? — and this runbook has been answering it with silence. Silence reads as "none". This section makes the run answer with a number, on real data, or state plainly that it could not.

**TRIGGER — both conditions, together:**
1. **The defect could have persisted a wrong value — or the EVIDENCE_SET already contains one.** The defective code wrote a stored column, failed to write one it should have, or computed a value that was then stored — including a value stored downstream by a caller on the path §3.4 traced. A defect that only affects what a screen or report *displays* from correct underlying data does not qualify: nothing is wrong at rest. **But the condition is read against the evidence, not against the changeset** (R-GATE-NOT-SELF-EXCUSED): a run that has chosen a UI fix and records `not run — the defect persisted no stored value` while its own analysis names a wrong stored value has excused the gate with its own conclusion. Any unexplained persisted value in the EVIDENCE_SET (§1.6 Step 2c `DATA_CAUSE`) arms this sweep on its own, whatever the issue type and whatever layer the fix landed on.
2. **A database is available** — the §1.7 restore, or a `knownServers` connection to the reported environment.

**A second, OLDER snapshot makes the count trustworthy (R-DB-CANDIDATE-SET).** The sweep counts rows that are wrong *now*, which conflates two populations the remedy treats differently: rows the defect broke, and rows a user already corrected by hand (AP-24877's workaround — *"manually override the tax amount to zero"* — produces exactly the second kind). Compare the sweep against an older copy in the candidate set where one exists: wrong in the newer and right in the older → broken inside that window; right in the newer and wrong in the older → **already hand-corrected, and it must not be counted as needing the data fix**; wrong in both → broken before the older snapshot. Report the count with the snapshot pair it was calibrated against, or state that only one snapshot was available — a single-snapshot count is still deliverable, it just cannot separate those populations.

**When either condition is absent the sweep does not run and NO query is delivered.** An unexecuted sweep query is worse than none: it looks like a finding, it carries no count, and whoever picks it up runs an unvalidated query against production data. The §6 line carries the reason (`not run — no database available`, or `not run — the defect persisted no stored value: <what it affects instead>`) and nothing else. The disclosure is mandatory; the query is not delivered.

### 1. Build it from the mechanism, not from the symptom

The sweep is a **`SELECT` and nothing but a `SELECT`** — any `UPDATE`, `DELETE`, `INSERT`, `MERGE`, `TRUNCATE` or DDL is an immediate FAIL, and this holds on a local restore exactly as it does on a shared server. The sweep's whole value is being safe to run anywhere, including by a BA against a production replica.

Derive it from the mechanism §3.4 proved: **re-compute the correct value the way the fixed code now computes it, and return every row where the stored value disagrees.** Searching for the symptom instead (`WHERE dblAmount = 0`, `WHERE strStatus IS NULL`) finds rows that are wrong for unrelated reasons and misses rows the defect broke into a plausible-looking wrong value. The second class is the expensive one, because nobody will ever go looking for it again.

Return, per row: the business identifiers a human can act on — the module's own document numbers, the ones a user reads off the screen (worked example, AP: `strBillId`, `strPaymentRecordNum`, `strTransactionId`) — never bare surrogate keys — plus the stored value, the re-derived expected value, the delta, and the row's posted/void state. Posted rows are the ones whose repair needs GL treatment (§3.6 Standard 4), so the sweep must distinguish them at discovery time, not later.

Scope it to what the defect can actually reach: the version/build family, the modules on the traced path, and the date range from when §3.8 says the defect was introduced. **State that scope in the §6 line** — an unscoped count invites the reader to take it for a whole-database count when it is not.

### 2. Calibration — the reported transaction must appear (fail-closed)

Run the sweep, then check that the transaction the ticket reports is **in the result set**. It is the one row already known to be broken.

If the sweep returns rows but not that one, **STOP and reconcile before reporting any count.** Exactly one of two things is true and both are serious: the query does not express the mechanism, or the mechanism is not the root cause. Reporting a confident count over a query that misses the known-broken row is how a run manufactures a number nobody can reproduce — and that number will be used to size a data fix.

If the sweep returns **zero** rows, including the reported one, the same STOP applies with more force: the reported row is wrong in the customer's database, so a sweep that cannot see it does not describe the defect. Reconcile before writing anything into §6.

### 3. Report the number, and what it obliges

- **`rows > 0`.** State the count, the identifier list (print up to 50 and state the total), and the scope. Then state the thing that is easiest to leave unsaid: **this code fix does not repair these rows, and a `Data Fix` JIRA is required to correct them.** It belongs in the plain-language summary too — the count is the part a non-technical reader has to act on. Name the identifiers so whoever files that ticket does not have to repeat the sweep.
- **`rows == 0`.** Say so explicitly; it is a real finding, not the absence of one. The defect was caught before it persisted damage, and the reader is entitled to know that was checked rather than assumed.

**When the sweep finds rows, this runbook DELIVERS the data fix — it does not withhold it (operator 2026-08-31, superseding the previous rule).** The earlier rule sent the count to the reader and kept the script back until somebody raised a `Data Fix` JIRA. It cited a §3.6 PRE-REQ that does not exist: §3.6's PRE-REQs are a usable database, a matching build and the policy sources — issue type appears only in its title, and §3.6 is now explicitly reachable on any type. So when rows are found, go to **§3.6** and author the script on the ticket in hand: from the JIRA Datafix Template, tested on the restored database inside the template's transaction, rolled back, with the impact analysis and QC test pointers. Ref AP-24960 — the correction was a five-line `UPDATE` on one voucher; the run reported *“not run”*, and the developer rebuilt the same fix by hand four and a half hours later.

**What is preserved, and is not negotiable.** The script ships with `@ysnCommit = 0`; the datafix-log guard and TRY-CATCH machinery stay intact; the database is left unfixed; the shared-server guard stands (never commit a data fix on a `knownServers` restore — use a local copy or disclose); and **Senior BA sign-off remains the gate**. Delivering the script is not approving it, and this runbook never applies one. The RCA takes the §6 **COMBINED form** when a code fix ships alongside.

**Still out of scope: raising tickets.** This runbook files no JIRA in any project. Whether the data fix is tracked here or on its own key is the operator's call; the sweep and the script hand them everything needed to decide.

The reverse direction already exists and stays consistent: §1.6 Step 2.9.2 requires a data-fix run to name the **program** JIRA whose defect produced the rows. §3.11 is that same link, established from the program side, before anyone has to go looking for it.

### 4. Deliver

1. Save the query to `<liquibaseLogDir>\<JIRA>\<JIRA>-affected-data-sweep.sql` and its output alongside as `sweep-<UTC timestamp>.log`.
2. Include the query **in full** in the §6 comment (a fenced ```sql block) whenever it ran — the count is only as credible as the query behind it, and the BA who files the data fix will re-run it.
3. Emit the §6 **Affected data** line (see §6).

## §4 Create the feature branch and commit

Only reached when §3 passed. **Skipped entirely when `IS_DATAFIX_CASE = true`** (§3.6 step 7 is terminal), and **skipped entirely when §2.6 held every candidate artifact** — there is no branch for a run that changed nothing in the repository (§2.6 step 3.3). When the changeset is mixed and separable, only the `OWNED` files are staged here: a held path must never enter a commit, which is why step 2 below stages explicitly rather than reaching for `git add -A`.

1. Put the validated changes on the feature branch:
   - IF the current branch is **already** `<FEATURE_BRANCH>` (the feature-branch-detection case from Input parameters — you are on `<base>_<JIRA>`): you are already on the correct branch; **do nothing here** (no checkout, no double-suffix). Proceed to step 2.
   - ELSE: `git checkout -B <FEATURE_BRANCH>`.

   Do **not** commit directly to `<TARGET_BRANCH>`.

2. Stage and commit the validated changes:
   - `git add -A` (or stage only the intended files if there are unrelated local edits — never commit validation artifacts or unrelated changes). **When §2.6 held any artifact, `git add -A` is forbidden for this run** — stage the `OWNED` paths by name, and re-check `git diff --cached --name-only` against the held list before committing.
   - Commit message MUST include `<JIRA>` and briefly describe the change intent.

3. After committing, re-inspect the diff before pushing:
   - **Confirm no §2.6-held path is in the commit** (`git show --name-only HEAD`). One that is → the commit is wrong: reset it, re-stage without the held path, and re-verify. A held object reaching `origin` is the exact outcome §2.6 exists to prevent, and the push is the last point at which it is still cheap to undo.
   - Confirm only the JIRA / acceptance-criteria intent is present.
   - Confirm no duplicate properties/columns/routes/methods were introduced.
   - Confirm no unrelated target-only fields, procedures, filters, or endpoints were removed.
   - For Liquibase schema files, confirm no deployed changeset was modified (unless it is a `runOnChange:true` logic object where the standards allow it).
   - For all Liquibase files, confirm every new changeset uses a timestamp ID and does not duplicate an existing `author:id` pair.

## §5 Push the feature branch (single connection)

Not reached when §4 was skipped (data fix, or every candidate artifact held by §2.6). When the changeset was mixed and separable, this pushes the `OWNED` files only — the held object has no commit to push, and no `<FEATURE_BRANCH>` is created for it.

`cd <REPO_PATH>`

`git push origin <FEATURE_BRANCH>`

- Use the Azure DevOps MCP / `az`-authenticated git; do not use a PAT from this prompt.
- After the push succeeds, continue to §6.

STOP if the push fails; report the error. Do not post the Jira comment for a change that was not pushed.

## §6 Comment on JIRA — Root Cause Analysis / Acceptance Verification (MANDATORY on a successful fix)

**The RCA comment means "FIXED".** It is posted ONLY when this run delivered a fix — a validated change pushed on `<FEATURE_BRANCH>` (§5), a data fix authored, tested and rolled back per §3.6, **or a fix held by §2.6 and delivered as an executed §3.10 patch** (the fix exists and is proven; what it lacks is a commit in a repository this module does not own — see the ownership form below). A run that ends any other way posts the matching §1.6 / §6.5 comment instead (see **R-NOFIX-COMMENT** in §1.6) and never an RCA. Never post an RCA describing a fix that was not delivered.

Post ONE comment on the parent `<JIRA>` combining the **Root Cause Analysis** with an **Acceptance Verification** block that answers, for each acceptance criterion the ticket asked for: what the criterion says (verbatim), what this fix does about it, how that was checked, and whether it was satisfied — with the reason stated whenever it was not.

**The block is named for what it is (operator 2026-09-04).** It used to be called *Developer's Testing*, which asserted something untrue: no developer tested this — an automated run did, and a reader who believes a person exercised the fix mis-weighs every verdict under the heading. The block therefore carries its own provenance line ("verified by the automated analysis run, not by manual developer testing — QA sign-off is still required") and that line is not optional. Renaming without the disclosure would trade one misleading heading for a vaguer one.

PRE-REQ:
- §3 validation passed and §5 push succeeded — OR, for `ISSUE_CATEGORY = DATA_FIX`, §3.6 completed with all assertions observed passing and the database left rolled back — OR, when §2.6 held every candidate artifact, §3 validation passed and §3.10 produced the patch (executed where a database was reachable, with its result stated verbatim). In that last case there is no `<FEATURE_BRANCH>` and no push, and the comment says so rather than implying a branch exists.
- Jira integration tool available and cloudId resolved.
- The JIRA issue (§1), `ACCEPTANCE_CRITERIA` (§2), and the CHANGESET diff (§3) are available.

**THE BLOCK REGISTER — the comment's shape is a contract, not a habit (R-RCA-REGISTER, operator 2026-09-09).** `RCA_CONTRACT_VERSION = 1.0.0`. It is bumped whenever a block is added, removed, renamed or reordered, or a required-block rule changes, and it rides in the footer (§6.8) on every comment. **It is deliberately separate from the runbook version:** this document changes weekly for reasons that never touch the comment, so the runbook version cannot answer "did the comment shape differ?" — which is the question a reader comparing two analyses on two tickets is actually asking.

The **id** is what is contractual. The **published label** is display text: when a label is improved, the old one goes in the rename ledger below and the id does not move. Blocks are emitted in register order.

| id | Published label | Forms | Owed when |
|---|---|---|---|
| `PREMISE_ANCHOR` | *Premise not verified.* | all | §2.4 recorded `UNVERIFIED-PROCEEDING` — otherwise absent entirely |
| `SUPERSEDES` | **Supersedes:** | all | §1.6 Step 0.0 gave a material `RERUN_DELTA` — otherwise absent entirely |
| `SUMMARY` | **Summary (non-technical):** | all | always |
| `DELIVERY` | **Delivery:** | CODE_FIX, DATA_FIX, COMBINED | always — on `ANALYSIS_ONLY` it is replaced, never dropped |
| `VERIFICATION` | **Verification status:** | all | always |
| `ISSUE` | **Issue:** | all | always |
| `ROOT_CAUSE` | **Root Cause:** | all | always — takes the `(HYPOTHESIS — not reproduced)` heading unless `REPRO` is a `REPRODUCED-*` verdict |
| `INVESTIGATION` | **Investigation:** | all | always |
| `TECH_EVIDENCE` | **Technical evidence (for dev/QA):** | CODE_FIX, COMBINED, ANALYSIS_ONLY | always on those forms |
| `PROPOSED_SOLUTION` | **Proposed Solution:** | all | always |
| `PATCH` | **Deployable patch:** | CODE_FIX, COMBINED | §3.10 applies — `N/A` line when it did not, never silently absent |
| `OWNERSHIP` | **Object ownership:** | CODE_FIX, COMBINED, ANALYSIS_ONLY | every delivered code fix and every §2.6-held object — stated either way |
| `ORIGIN_TRACE` | **Origin trace:** | CODE_FIX, COMBINED | §3.4 ran |
| `CLIENT_TREE` | **Client file location:** | CODE_FIX, COMBINED | §3.4a ran — `N/A` line when the trigger did not fire |
| `RELATED_DEFECTS` | **Related defects found:** | all | always — `none` when §3.4 Proof 3 was clean |
| `PREMISE` | **Premise:** | all | always (R-PREMISE) |
| `SIBLING_ALIGN` | **Sibling alignment:** | CODE_FIX, COMBINED | §2.5 ran — or its `NOT-RUN` disclosure |
| `PORT_EXCLUSIONS` | **Port exclusions:** | CODE_FIX, COMBINED | `ALIGN_VERDICT = PORT-AVAILABLE`. **Its own block** — never folded into `SIBLING_ALIGN`, or the strip becomes unkeyable |
| `REMEDY_SELECT` | **Remedy selection:** | all | §2.7 ran |
| `PATTERN_COVERAGE` | **Pattern coverage:** | CODE_FIX, COMBINED | §3.4 Proof 4 ran |
| `REGRESSION_IMPACT` | **Regression impact:** | CODE_FIX, COMBINED | §3.7 ran — or its not-run disclosure |
| `RECORDS_AFFECTED` | **Records already affected:** | CODE_FIX, COMBINED, ANALYSIS_ONLY | every delivered code fix, in exactly one of the three forms below |
| `PROPERTY_TEST` | **Property test:** | CODE_FIX, COMBINED | §3.9 ran — or its not-run disclosure |
| `DEFECT_LINEAGE` | **Defect lineage:** | all | §3.8 ran — or its not-determinable disclosure |
| `SCHEMA_VALIDATION` | **Schema validation:** | CODE_FIX, COMBINED | the CHANGESET contains a Liquibase change. **Owed in both directions** — a Liquibase changeset whose comment carries no such line leaves a reader unable to tell that `liquibase update` and rollback were never exercised (ref RM-13209) |
| `ACCEPTANCE` | **Acceptance Verification-** | all | always, with `AC_SOURCE` first, one entry per criterion, `AC_VERDICT` last |
| `PROOF` | **Proof of testing-** | all | screenshots or captured output exist — absent entirely otherwise, never fabricated |
| `PATCH_SCRIPT` | **Patch script-** | CODE_FIX, COMBINED | `PATCH` fired. The patch is described in the block above and printed here; described-but-not-printed is a failure |
| `SWEEP_QUERY` | **Affected-data sweep query-** | CODE_FIX, COMBINED | §3.11 swept and found rows |
| `DF_*` | **Data fix delivered** … **Review** | DATA_FIX, COMBINED | the nine data-fix delivery blocks, all of them, on those two forms |
| `KNOWLEDGE_DRAFT` | `KNOWLEDGE-DRAFT` / `KB-CONSULTED` / `RUN-GATES` | all | always — machine-read, grammar owned by §6.9 |
| `READY_FOR_PR` | `READY-FOR-PR:` | all | a branch was pushed — machine-read, grammar owned by §6.7 |
| `RUN_BASIS` | *Run basis* | all | always (R-RUN-BASIS) |
| `DB_PROVENANCE` | *database provenance* | all | database evidence is cited (R-DB-PROVENANCE) |
| `TELEMETRY` | *stamp + run line* | all | always (§6.8) — or the exact unavailable wording |

**"Never omitted in either direction" is the register's load-bearing column.** A block whose trigger did not fire and which the register gives an `N/A` form is *stated as not applicable*. A silently absent block is indistinguishable from a check nobody ran, and no reader can tell those apart at any distance.

**RENAME LEDGER (R-RCA-RENAME).** A published label may be improved; when it is, the old one is recorded here permanently, because a reader meeting an older comment — and any report keyed on labels — needs both names to resolve to one id. Renaming without a ledger row forks the published record: measured 2026-09-09, three labels were live in two vocabularies across 80 comments, and no label could be relied on as a key.

| id | Old label | Current label | Renamed |
|---|---|---|---|
| `ACCEPTANCE` | Developer's Testing | Acceptance Verification | 2026-09-04 |
| `RECORDS_AFFECTED` | Affected data (§3.11) | Records already affected | 2026-09-04 |
| `CLIENT_TREE` | Client tree (§3.4a) | Client file location | 2026-09-04 |

**FORMAT (mandatory — match this structure).** Build `JIRA_RCA_BODY` from the Jira (symptom / expected behavior / acceptance criteria) + the CHANGESET diff (root cause, evidence, fix), traceable to evidence only — no invented work. The RCA opens with a **Summary (non-technical)** block so non-technical readers (customer, support, consultants, PM) understand the ticket without reading the technical sections. Omit the **Proof of testing** block if no screenshots/output are available; never fabricate proof.

```
# Root Cause Analysis

**Premise not verified.** <PRESENT ONLY when §2.4 recorded `UNVERIFIED-PROCEEDING`; omitted entirely on every other verdict (R-PREMISE-ANCHOR). **The FIRST thing in the comment** — above Supersedes, above the summary, above the mechanism. One short paragraph: "This fix assumes `<the disputed behaviour>` is incorrect. No specification, test or invariant confirms that: `<what the ladder searched and returned>`. If the current behaviour is correct, no fix is needed and this change should be discarded rather than reviewed." Its POSITION is the rule, not its wording: a reviewer handed a complete RCA and a pushed branch grades the fix and does not re-open whether a fix was needed, so an assumption placed after the mechanism has already lost its reader. Never softened into "this could not be fully confirmed", and never merged into the Summary.>

**Supersedes:** <PRESENT ONLY on a re-run that Step 0.0 gave a material delta (`RERUN_DELTA`); omitted entirely on a first run. Four lines, so a reader meeting two analyses on one ticket knows immediately which governs and why the first one is not simply wrong-and-deleted:>
* **Earlier analysis:** <date of this runbook's previous comment> — <its verdict in one line: the root cause it named, or the blocker it stopped on>
* **What changed since:** <the material delta, in the reader's terms: "the acceptance criteria were revised on <date>" · "a copy of the reported database became available" · "the app environment came back up" · "the runbook's <section> configuration was missing on that run">
* **What is different now:** <what that change actually altered — a different root cause, a criterion that could finally be executed, a fix built to a requirement that has since been withdrawn. When the earlier conclusion still holds and only the evidence is stronger, say so plainly rather than implying it was wrong.>
* **Earlier delivery:** <MANDATORY when the earlier run pushed a branch: "commit `<short SHA>` on `<branch>` — <kept and amended | superseded, retraction needed: <why>>". `N/A — the earlier run delivered no code` otherwise.>

**Summary (non-technical):**

<2–4 plain-language sentences for a non-technical reader: what the user experienced in day-to-day terms, why it happened (in business terms, not code), and what the fix changes for them. No file names, no code objects, no SQL/branch/repo jargon. This block restates the technical findings below — it must not introduce any claim that is not covered by them.>

**Delivery:**

<MANDATORY on every delivered code fix — the reader must reach the work in one click (R-RCA-LINKS), never from a bare branch name or SHA. Omit this block entirely for a data fix (§3.6) and for a fix held by §2.6: neither has a branch, and a link would assert one exists. **Two lines are deliberately absent (operator 2026-09-01): no branch-vs-target diff link and no pull-request line of any kind** — not a `pullrequestcreate` URL, not "create the PR", not a link to an existing PR. This runbook creates no PR (§6.7) and the RCA does not invite one: what happens after the RCA is a human decision (verify the analysis, then route or raise the work), and a create-PR link in the comment pre-empts it. Re-adding either line is a §6 defect.>
* **Feature branch:** [`<FEATURE_BRANCH>`](https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>?version=GB<url-encoded FEATURE_BRANCH>) → `<TARGET_BRANCH>`
* **Commit:** [`<short SHA>`](https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>/commit/<full SHA>) — `<n>` file(s)

**Verification status:**

<MANDATORY on every RCA — never omitted, never softened (R-VERDICT-HONESTY). Five lines, built from §1.7b / §1.7d / §1.8. Every value is carried faithfully; the reproduction line is the one that is *rendered* rather than pasted, per R-REPRO-PLAIN, because its token means nothing to the people this comment is written for:>
* **Reproduced:** <the plain-language sentence for the §1.8 `REPRO` verdict from the table below (R-REPRO-PLAIN), then what was actually run on each axis, then the machine verdict in backticks at the end. Never the bare token — e.g. "**Reproduced.** We made the error happen ourselves, on the transaction the ticket reports and on a new one we created. Reported transaction: PI-1671 raised SQL error 544 from `uspAPUpdateIntegrationPayableAvailableQty`. New transaction: the same error on a voucher we created for the test. (`REPRODUCED-BOTH-AXES`)">
* **Database:** <the §1.8 evidence ledger's `DB touched` + `DB provenance` lines verbatim (R-DB-PROVENANCE — a shared server named as `<server> / <dbname>` + build, where `<dbname>` is the **literal value returned by `SELECT name FROM sys.databases` on that server** — copied, never paraphrased or abbreviated, because a name nobody can connect to makes the whole provenance line unreproducible (R-DB-PROVENANCE-LITERAL, operator 2026-08-31; ref AP-24960, which cited `RogersPetroServices_0825` for a server whose database is `RogersPetroServ01_0825`); a local restore identified by its acquisition source and NEVER by its server/db name; which HDTN supplied the copy when the ticket lists more than one, or `not traceable to a listed HDTN`), then what was actually done: objects READ vs objects EXECUTED, errors captured. "No database was available" when that is the case.>
* **Customer's deployed code:** <per object, in words: "matches the version we analysed" / "OUT OF DATE — the customer is running an older body, so the fix may already exist and simply not be deployed". Name each object. "Not checked — no database was available" when that is the case. The internal verdicts SAME / DEPLOYED-STALE stay in the run output; they are not written here.>
* **What writes this value:** <the `DATA_WRITER_VERDICT` line, rendered in words — verdict · writers swept and the scope swept · recurring writers found, each with its owning project · the configured changelog table and what the changeset's row in it said — or "N/A — no stored value in the evidence". Never "not run — no DB reachable": this gate is static.>
* **Earlier work on this defect:** <the JIRA keys found and whether each names the same mechanism or was ruled out and why — each key linked. "None — we checked this object's change history, searched for tickets with the same signature, swept the other release lines, and read the database's own data-fix log" when all four searches ran clean. Say what was searched, not which gate did the searching.>

**Issue:**

<What the user/QA observed — the reported symptom(s). Use a short numbered list when there are multiple distinct failures.>

**Root Cause:** <or, when REPRO is not a `REPRODUCED-*` verdict, this heading MUST read **"Root Cause (HYPOTHESIS — not reproduced)"**>

<The underlying cause. When the failure spans layers (DB / BL / UI / config), break it down per layer. Name the specific defect. When R-ERROR-CLASS left more than one candidate unexcluded, list every surviving candidate as a competing hypothesis — do not present one as the cause.>

**Investigation:**

<How the cause was confirmed — what was validated and in what order; what evidence pinned it down.>

**Technical evidence (for dev/QA):**

<Bulleted, grouped by area. Name the actual files/objects changed and what changed in each, drawn from the CHANGESET diff.>
* **<Area, e.g. Logic / SP fix>**
    * [`<repo/path/to/file.sql>`](https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>?path=/<repo-relative path>&version=GB<url-encoded FEATURE_BRANCH>) — every changed file is linked at the branch it was changed on (R-RCA-LINKS). A §2.6-held or otherwise unpushed path is named in backticks with **no** link, and says why.
    * <what changed and why>

**Proposed Solution:**

<The fix delivered (1–2 lines) + a short prevention/regression checklist for this area.>

**Deployable patch:** <MANDATORY whenever §3.10 applies — never omitted, in either direction. Trigger fired: "`<JIRA>Patch.sql` — `<n>` object(s): `<schema.name>`, … · assembled from `<FEATURE_BRANCH>` @ `<SHA>` · apply only to build `<TARGET_VERSION>`.x · applied to a restored copy of the reported database, all objects compiled, reported transaction re-tested symptom-free, pre-fix bodies restored (database left unfixed)" — or, when no database was reachable, "… · not executed — no database available (bindings unconfirmed: `<list>`)". Say that it is attached to this ticket, or carry the §3.10 step 4.2 manual-attach line when the upload failed. The script itself goes in the **Patch script** appendix below. Trigger did not fire: `N/A — no database object in this changeset`. Omit for a data fix — there the data-fix script IS the artifact.>

**Object ownership:** <MANDATORY on every delivered code fix — never omitted in either direction (§2.6). One line per candidate artifact: "`<object>` — owner `<project>` (`<route>`) · path: `<module-owned|shared: path>` · callers: `<n>` (`<breakdown by prefix>`) · history: `<n>` prior commit(s), keys `<list>`". When every artifact is `OWNED` by this JIRA's own project, the line reads `all changed objects owned by <JIRA_PROJECT> (<the counts>)` and nothing further is said. When any artifact is `FOREIGN-SHARED`, this block states that the object is maintained by `<project>`, that the change **was** authored and pushed here, and that **`<project>`'s reviewer is required before the PR is raised** (§6.7 carries the same marker). When any artifact is `FOREIGN-EXTERNAL` or `UNDETERMINED`, it states instead, in plain language: that **the repository was not modified** and **no fix was authored** (operator 2026-08-31) — the deliverable is the diagnosis, naming the owning project, the exact artifact and lines, and the introducing commit — and the three routing options from §2.6 step 4 — raise it under the owning project's key and link back · keep it here and have the owning module review the patch · route the whole ticket. State explicitly that **this ticket has not been moved, reassigned or re-raised anywhere** — the choice is the reader's to make. Omit for a data fix.>

**Origin trace:** <MANDATORY whenever §3.4 ran (every code/logic change). One line: "value lost at `<w0 — the statement that creates the row>`; fixed there · other callers of that statement: `<list or none>` · changed statements on the reported repro's path: `<n>` of `<m>` (`<off-path ones and why they are included>`)". When the fix is deliberately NOT at `w0`, this line MUST say why the earlier carry gap was left in place. Omit for a data fix.>

**Client file location:** <MANDATORY whenever the CHANGESET contains a client-side asset, and never omitted in either direction. One line: "served tree `<SERVED_TREE>` on `<TARGET_BRANCH>` (`universal` `<n>` commits / `app` `<m>` commits, 24 mo) · `<k>` changed client file(s), all PLACED · `<the counterpart a MISPLACED file was moved to, when there was one>`". Write `N/A — no client-side asset in this changeset` when the trigger did not fire, and `N/A — no app/universal split on <TARGET_BRANCH>` when the repository has no split. A `.js` fix in the unserved tree passes every other check in this runbook, so the verdict is stated, not assumed. Omit for a data fix.>

**Related defects found:** <MANDATORY whenever §3.4 Proof 3 returned a fall-through, or the run found any defect in the touched code that is not this ticket's defect. Name the variable/statement, the concrete input that reaches it, the first misbehaviour, and whether it was fixed here (fail-closed guard) or escalated. Write `none` when Proof 3 was clean. Never drop a finding because it is out of scope — out-of-scope findings are reported, not discarded.>

**Premise:** <MANDATORY on every run (R-PREMISE) — the §2.4 verdict and what earned it, never omitted. One line: "`<PREMISE-CONFIRMED (self-evident: <class>) | PREMISE-CONFIRMED | UNVERIFIED-PROCEEDING>` · authority: `<the rung that answered and its citation — iNet <space>/<page id> v<version> (baselined <branch>, verified <date>) | test <id> | invariant <name> | DEFECT_ORIGIN <KEY> | peers <objects>>`". Where nothing answered, the authority half is **not** left blank and **not** written as "none": it states what was searched — "`no authority found — searched iNet <space> (<n> page(s) matched, <n> baselined on <branch>), tests on <TARGET_BRANCH>, invariants, lineage (<A4 result>), peers (<n>)`". A reader must be able to tell a ladder that ran and found nothing from a ladder that never ran. `REFUTED` and `CONTESTED` never reach this template — they post §6.5 E instead.>

**Sibling alignment:** <MANDATORY whenever §2.5 ran (every code/logic change) — never omitted in either direction. One line per changed logic object: "`<object>` vs `<n>` sibling line(s) (`<branches>`) — `<verdict>`", where the verdict reads `ported from <repo>/<branch>` · `no sibling carries this behaviour — authored here` · `novel fix — <what the sibling body does that this deliberately does not, and why it is unsuitable on this line>` · `N/A — object exists on <TARGET_BRANCH> only` · the `NOT-RUN (<reason>)` disclosure. A port MUST name the branch it was aligned to; a novel fix authored while a sibling held the behaviour MUST carry its justification **here**, in the customer-visible RCA, not in the run output. Omit for a data fix.>

**Port exclusions:** <MANDATORY whenever the fix is a port (`ALIGN_VERDICT = PORT-AVAILABLE`). One line per deliberately stripped portion — "`<portion / referenced JIRA>` — excluded: `<missing prerequisite>` not on `<TARGET_BRANCH>`" — or `none — body taken whole`. Never omitted when a port was taken: a strip nobody recorded reads as an oversight at review time, and an unrecorded non-strip means half a feature shipped under this JIRA's key. Omit this block entirely when the fix is not a port.>

**Remedy selection:** <MANDATORY whenever §2.7 ran (every run that authors, ports or recommends a remedy — data fixes included). Two parts, both required. First the choice: "`<layer>`:`<object/artifact>` — durability `<DURABLE | NOT-DURABLE (<the writer that re-asserts it>)>` · closes `<n>` of `<m>` site(s) · `<c>` caller(s) (`<modules>`) · precedent `<ported from <branch> | module convention <fact> | none — first of its kind here>`". Then what was rejected, one entry each: "`<layer>`:`<object>` — `<axis>` — `<the observation that rejected it>`". A selected remedy with no rejected candidate beside it is only acceptable when the enumeration genuinely held one entry, and then this line MUST carry the reason no other layer can hold the fix. This block is what tells the reader the layer was chosen rather than defaulted to, and it is the half a reviewer would otherwise have to re-derive from scratch.>

**Pattern coverage:** <MANDATORY whenever §3.4 Proof 4 ran (every code/logic change). One line: "`<closed>` of `<total>` site(s) of this mechanism closed — open: `<list or none>`". Every OPEN site is either brought into this changeset or repeated under **Related defects found** with the reason it is out of scope. A fix that closes the reported site and leaves siblings of the same mechanism open is a partial delivery, and saying so here is what stops it being discovered as a follow-up ticket instead. Omit for a data fix.>

**Regression impact:** <MANDATORY whenever §3.7 ran (any CHANGESET with a SQL logic object or a code artifact with callers). One line: "`<d>` dependents analyzed · `<n>` golden rows compared · `<k>` unexpected deltas" plus the excluded volatile columns when tier 2 ran, OR the not-run disclosure "dependents analyzed (`<d>`); golden-set differential NOT run — no database is known/available for this JIRA." When `<k>` > 0, list the affected keys with before/after values — it is a review-blocking finding, not a footnote. Never present a clean differential as proof of no regression; it is sampled evidence. Omit this line entirely for a data fix (§3.6 carries its own Standards 1–4 collateral checks).>

**Records already affected:** <MANDATORY on every delivered code fix, in exactly one of three forms. Sweep ran and found rows: "`<n>` row(s) already carry this defect · identifiers: `<up to 50, then “+ <k> more”>` · scope swept: `<version/build family, modules, date range>` · reported transaction present: yes · **the code fix does not repair these rows; the data fix delivered below does** — pending Senior BA sign-off" (operator 2026-08-31: the sweep no longer stops at asking for a `Data Fix` JIRA — §3.11 goes on to §3.6 and the script ships on this ticket, and the RCA takes the **COMBINED form**). Sweep ran clean: "0 rows — the defect persisted no incorrect data (scope swept: `<…>`)". Not run: the §3.11 reason verbatim — `not run — no database available`, or `not run — the defect persisted no stored value: <what it affects instead>`. The count may never be softened, rounded, or replaced by a qualitative phrase, and a non-zero count MUST also appear in the **Summary (non-technical)** block — it is the part a non-technical reader has to act on. The query goes in the **Affected-data sweep query** appendix below. Omit for a data fix — §3.6 Standard 1's analysis query is the sweep.>

**Property test:** <MANDATORY whenever §3.9 ran. One line with the counts: inputs / evaluations · failures OLD → NEW and whether the new failure set is a SUBSET of the old · fixed · changed and how many of those were unwanted drift · accuracy regressions · each residual class. State plainly that a residual is a pre-existing defect left unfixed (and whether it is reachable on the affected path), never bury it. OR the not-run disclosure naming what the artifact is. Omit for a data fix.>

**Defect lineage:** <MANDATORY whenever §3.8 ran. One line: "introduced by `<KEY>` (`<commit>`, `<date>`) · coverage: `<line>`=`<state>`, … · gaps not fixed here: `<list or none>`", OR the not-determinable disclosure. When `FIX_COVERAGE` is NOT uniform across lines, ALSO include the short vintage → observed-behaviour table required by §3.8 step 4, so a reviewer testing on a different database does not get a false negative. A line marked `PARTIAL` must say what the existing fix does NOT close, backed by the counterexample from §3.8 step 3 — never assert completeness from source text. Omit this block entirely for a data fix.>

**Schema validation:** <ONLY when CHANGESET contains a Liquibase change. DB known: "`liquibase update` + rollback verification are running now on a separate agent — the result will be commented on the PR." DB not known: "`liquibase update` NOT run — no database is known/available for this JIRA." Omit this line entirely for non-SQL changes.>

----------------------------------------------
**Acceptance Verification-**

*Verified by the automated analysis run, not by manual developer testing — QA sign-off is still required.*

**Criteria source:** <MANDATORY first line of this block (R-AC-PROVENANCE). One of: `stated on the ticket (<field or location — Acceptance Criteria field / description section / comment by <author> on <date>>)` · `partially stated — criteria <n>, <m> stated on the ticket, the rest derived from the description and expected behaviour` · `derived — the ticket states no acceptance criteria; the list below was written by this run from the description and expected behaviour and has NOT been confirmed by the reporter` · `derived — the ticket's stated criteria were <ambiguous|untestable>: <what was unclear>; the list below restates them testably`. Never omitted: a reader cannot judge a verdict without knowing whether the criterion came from the business or from this run.>

<One numbered entry per acceptance criterion — every item in ACCEPTANCE_CRITERIA appears here, in the §2 numbering, and each entry carries all four sub-lines below. **`PASS` is reserved for a result that was OBSERVED** — see the verdict vocabulary in the Rules below.>

1. **Criterion (stated):** "<the criterion reproduced VERBATIM as it appears on the ticket — quoted, not paraphrased, not summarized, not re-worded to match what the fix happens to do>"
    * **What the fix does about it:** <the concrete behaviour change that addresses THIS criterion, in one or two sentences a QA analyst can act on — what now happens that did not happen before, and where. Name the changed object/file from the CHANGESET. When one change satisfies several criteria, say so and name them; when this criterion needed no change, say that and why.>
    * **How it was checked:** <the specific test performed — the query run, the screen driven, the `EXEC` issued, the `liquibase update`. "Read the code" is not a check; it is the `UNVERIFIED` verdict below.>
    * **Result:** PASS — <the observed evidence, quoted: the output, the value, the captured screen state>
2. **Criterion (derived — not stated on the ticket):** "<the derived criterion, written as a testable statement>"
    * **What the fix does about it:** <as above>
    * **How it was checked:** <as above>
    * **Result:** UNVERIFIED — static reasoning only (<what was read, and what would settle it>)
3. **Criterion (stated):** "<verbatim>"
    * **What the fix does about it:** <MANDATORY even here — when the changeset deliberately does not implement this criterion, this line says what the fix does instead, and the Result line says why it was left.>
    * **How it was checked:** n/a — not implemented in this changeset
    * **Result:** NOT ADDRESSED — <why this criterion is out of this fix's scope, who or what would close it, and whether a follow-up ticket exists>

**Acceptance verdict:** <MANDATORY closing line of this block, never omitted (R-AC-VERDICT). One line: "`<n>` of `<m>` criteria satisfied and observed · `<a>` unverified · `<b>` not addressed · `<c>` failed". When `<n>` is not `<m>`, the line continues "— this fix does NOT close the acceptance criteria as written: `<the criterion numbers and the one-phrase reason for each>`". A reader must be able to answer "did this fix do what the ticket asked for?" from this single line without reading the entries above it.>

----------------------------------------------
**Proof of testing-**

<Optional — attach/reference test screenshots or output if available; otherwise omit this block entirely.>

----------------------------------------------
**Patch script-**

<Present whenever §3.10 produced a patch. The full `<JIRA>Patch.sql` in a fenced sql block when it is ≤ 200 lines; otherwise each object's header and signature plus the substantive changed statements, and a pointer to the attachment — never a truncated body that reads like a complete one. Omit this block entirely when the §3.10 verdict is `N/A`.>

----------------------------------------------
**Affected-data sweep query-**

<Present whenever the §3.11 sweep ran — the query in full, in a fenced sql block. It is read-only by construction, so it is safe for the reader to re-run, and the BA who files the data fix will. Omit this block entirely when the sweep did not run: an unexecuted sweep query is never delivered.>

----------------------------------------------
*Automated analysis — JIRA-AI runbook <RUNBOOK_VERSION> · <model name>*
*Run basis (R-RUN-BASIS) — ticket: `updated <ISO instant read>` · fixVersion `<v>` · env `<field>` · build `<stamp>` · customer `<c>` · `<n>` attachment(s) · last comment read `<id or date>` · description `<chars>` chars; capability: config `<sections that resolved | none>` · DB `<server>/<dbname> | not reachable>` · app env `<url + build stamp | not reachable>`*
*<the §6.8 telemetry line, verbatim from the script — or `Run telemetry unavailable — transcript not readable.`>*
```

**Worked example — what the Acceptance Verification block should read like.** Illustrative only: the criterion below is a real one taken from a ticket, the object names and evidence are invented to show the shape. Note what each entry does that a bare grade does not — it quotes the requirement in the reporter's own words, states the behaviour that is now different, names where that behaviour lives, and separates *not built* from *not tested*.

```
**Acceptance Verification-**

*Verified by the automated analysis run, not by manual developer testing — QA sign-off is still required.*

**Criteria source:** stated on the ticket (Acceptance section in the description)

1. **Criterion (stated):** "Validation should be added when a user changes any of the header fields for an already loaded currency exposure."
    * **What the fix does about it:** editing a header field on a currency exposure that already has loaded detail now raises a blocking validation message instead of silently saving; the record cannot be saved until the detail is unloaded. The check was added to the header field-change handler and re-asserted on save, so it holds whether the user edits in the grid or through the screen's own save path.
    * **How it was checked:** loaded a currency exposure on the restored copy, changed the header's currency and its as-of date, then saved.
    * **Result:** PASS — both edits raised the validation and the save was rejected; the stored header values were unchanged after the attempt.
2. **Criterion (derived — not stated on the ticket):** An unloaded currency exposure remains freely editable.
    * **What the fix does about it:** the guard is conditioned on the presence of loaded detail, so nothing changes for a header with none.
    * **How it was checked:** created a new exposure with no detail and changed the same two header fields.
    * **Result:** PASS — both edits saved; no validation raised.
3. **Criterion (stated):** "The same validation should apply to the bulk import."
    * **What the fix does about it:** nothing — the import path does not go through the field-change handler this fix touched, and routing it through one is a change to the import contract rather than a validation addition.
    * **How it was checked:** n/a — not implemented in this changeset
    * **Result:** NOT ADDRESSED — out of this fix's scope; the import writes headers directly and needs its own guard. No follow-up ticket exists yet.

**Acceptance verdict:** 2 of 3 criteria satisfied and observed · 0 unverified · 1 not addressed · 0 failed — this fix does NOT close the acceptance criteria as written: criterion 3 (bulk import path untouched).
```

**DATA_FIX form (ISSUE_CATEGORY = DATA_FIX).** Same comment, same Summary/Issue/Root Cause/Investigation opening — the "root cause" here is *why the rows are wrong*, and it names the linked program JIRA where the code defect lives. Replace **Technical evidence** / **Schema validation** with the blocks below, and keep Acceptance Verification. **§3.10 and §3.11 are both N/A on this form** — the data-fix script IS the deployable artifact, and §3.6 Standard 1's analysis query IS the affected-data sweep. Never author a second patch or a second sweep for a data-fix ticket: two artifacts for one ticket are two things that have to stay in step, and they will not.

**COMBINED form (a code fix AND a data fix on one ticket — operator 2026-08-31).** Reached whenever §3.11 found rows on a ticket that is *not* typed `Data Fix`: the code fix stops the defect recurring, the data fix repairs what it already broke, and both belong on the ticket in hand. Neither of the two forms above can express this — the CODE_FIX form has nowhere to put the script, and the DATA_FIX form declares §3.10/§3.11 `N/A`. Build the comment as the **CODE_FIX form in full**, then add, immediately after **Affected data**, the DATA_FIX form's delivery blocks: **Data fix delivered**, **Records affected**, **Validation results** (the dry run, rolled back), **Impact analysis**, **Cross-module approvers required**, **Test pointers for QC**, and **Review: pending Senior BA sign-off**. Two rules specific to this form: the **Affected data** line takes the *fix-delivered* wording above rather than the `Data Fix` JIRA wording; and the *“never a second sweep”* prohibition is lifted here, because §3.11's sweep and §3.6 Standard 1's analysis query **are the same query** serving two blocks — state that once and print it once. Ref AP-24960: two program defects and one bad row, closed as a bare Data Fix with the program defects still live.

```
**Data fix delivered:** `<JIRA>DataFix.sql` — derived from the JIRA Datafix Template (page 434602044), ships with `@ysnCommit = 0`.
**Linked program JIRA:** <key, or "NONE — a program JIRA is required for the code-level root cause">
**Coded against build:** <DB_BUILD_VERSION>   **Target branch:** <TARGET_BRANCH>

**Records affected:** <n> — identifiers: <the printed list>

**Validation results (dry run on a restored copy of the reported database):**
* Standard 1 — rows with issue <n> = rows affected <n> — PASS
* Standard 2 — master/detail rollup integrity (`<MASTER_TABLE>` / `<DETAIL_TABLE>`, rollup per `<the procedure that supplied ROLLUP_RULE>`) — PASS / N/A <reason>
* Standard 3 — application/settlement total integrity (`<applied-total column>` vs its applications) — PASS / N/A <reason>
* Standard 4 — GL debit/credit balance for posted transactions (`strModuleName = <GL_MODULE_NAME>`, resolved from `tblGLDetail` for the affected documents; <n> GL rows matched) — PASS / N/A <reason>
* Additional checks S5–S17 — PASS
* Transaction rolled back; re-run of the analysis query still reports the same <n> rows; no `<DATAFIX_LOG_TABLE>` entry written.
* Data-fix log: `<DATAFIX_LOG_TABLE>` — <existing on this database | created by this script (`IF NOT EXISTS`, columns copied from `<the log table it was modelled on>`)>

**Impact analysis:** <tables/columns changed, row counts, consuming modules (`CONSUMING_MODULES` from the §3.7 tier 1 dependency scan — or the stated coverage limit when tier 1 could not run), and what was verified unaffected — each grounded in a query result>
**Cross-module approvers required:** <team(s), or None>
**Test pointers for QC:** <the areas to test beyond the reported symptom, derived from CONSUMING_MODULES and the Standards that applied — e.g., in AP, the payment's GL entries and the vendor prepayment balance when amounts and GL entries changed>

**Review:** pending Senior BA sign-off per Data Fix Standards (All Modules) — https://irely.atlassian.net/wiki/spaces/AP/pages/705168896 — plus `<the module's addendum, or "no <MODULE> addendum published">`. QC to begin only after that verdict is posted.

<the full script in a fenced ```sql block>
```

Rules specific to the DATA_FIX form: the script is posted **in full** (it is the deliverable); `@ysnCommit` in the posted script is `0`; the comment states that the database used for testing was left unfixed; and **no local/Philippines restore details are named** (R-DB-LEDGER-REUSE) — say "a restored copy of the reported database", not the server or database name.

**ANALYSIS_ONLY form (`ISSUE_CATEGORY` unchanged; the run proved a cause and no program fix is owed — operator 2026-09-09).** Reached when the root cause is proven and **nothing in this codebase needs to change**: the remedy is data, configuration, or an object §2.6 held, and nothing is blocked, missing or disputed. It is not a triage stop — the analysis is complete — and it is not a fix, so the other three forms cannot express it. Without this form a run in that state is handed only forms that assert a delivery and **improvises its own blocks**: measured on GL-17181, four invented (*Corroboration*, *Prevention*, *Not touched*, *Impact*) and nine owed blocks dropped. Rules specific to it:

- **The heading reads `Root Cause Analysis — no program fix required`**, never the bare heading. The bare heading asserts a delivery this form does not have, and the reader who skims it will believe a fix shipped.
- **`DELIVERY` is replaced, not dropped:** one line reading *no code change was authored; nothing was pushed*, followed by what the remedy actually is and who owns it.
- **`ACCEPTANCE` is still owed**, and its verdict line states plainly that no criterion was closed by a change, with what would close each one.
- `PATCH`, `PATCH_SCRIPT`, `SCHEMA_VALIDATION`, `SIBLING_ALIGN`, `PORT_EXCLUSIONS` and `PROPERTY_TEST` are absent entirely. `OWNERSHIP` and `RECORDS_AFFECTED` are **still owed** — "who owns this" and "what is already broken" are the two questions this form exists to answer.
- It never claims, implies or is labelled as a fix. **Label: `JIRA-AI-Triaged`** (§6.6), because it is terminal for this runbook and that label already gates the §6.5 selector. A label of its own would read better and would require adding it to the §6.5 queue-exclusion list in the same change — otherwise every such ticket re-enters the queue forever. That is an operator call, not this form's to make.

**Before the call, run §6.4 (R-RCA-VALIDATE) and require `PASS`.** The body is assembled, then checked against the register above, then posted — never assembled and posted in one move. A failing check is fixed and re-validated; it is never posted with a note about itself.

Call `addCommentToJiraIssue`:
- issueKey: `<JIRA>`
- cloudId: resolved
- commentBody: `JIRA_RCA_BODY`
- contentFormat: markdown

Rules:
- **ONE** `addCommentToJiraIssue` call.
- **Mention the people who need to see it (R-COMMENT-MENTIONS, operator 2026-08-08).** Every comment this runbook posts @-mentions the issue's **current assignee**. In addition, the comment that **first establishes a §3.8 lineage** mentions the **assignee and commit author of each related JIRA** it names — they know the object and the comment discusses their earlier work, and naming a ticket without notifying its developer buries the finding. On **subsequent** comments in the same run, mention only the people the *new* information actually concerns: re-mentioning the same group on consecutive comments is noise, and an automation that spams gets muted, which costs more than the notification gains. Use `contentFormat: adf` with real `mention` nodes (`{"type":"mention","attrs":{"id":"<accountId>","text":"@Name"}}`) — markdown renders `@Name` as inert text and notifies nobody. Resolve account ids with `lookupJiraAccountId`; when one cannot be resolved, name the person in plain text and say the mention could not be resolved. Never mention someone merely to escalate, and never mention a customer-facing account.
- Every **Root Cause** / **Technical evidence** / **Acceptance Verification** claim must be traceable to the CHANGESET diff, the acceptance criteria, or the Jira description; do not invent symptoms, layers, fixes, or test results.
- The **Summary (non-technical)** block is mandatory and jargon-free: it translates the Issue/Root Cause/Proposed Solution into plain language a non-developer can act on, and may not add facts beyond the technical sections it summarizes.
- Every `ACCEPTANCE_CRITERIA` item MUST appear in the **Acceptance Verification** block. An empty or partial Acceptance Verification block -> STOP and re-derive from §2/§3.
- **R-AC-VERBATIM — the criterion is quoted, not summarized (operator 2026-09-04).** Each entry opens with the criterion **word for word as the ticket states it**, in quotes. Paraphrasing is forbidden in both directions, and the dangerous direction is the quiet one: a criterion re-worded to describe what the fix happens to do turns the verification into a tautology — the reader compares the fix against a restatement of the fix and finds them in agreement. The business wrote those words and the business is the reader who has to recognise them. A derived criterion is written testably (there is no verbatim to quote) and is **labelled `derived`** on its own line, so nobody mistakes this run's reading of the description for the reporter's requirement.
- **R-AC-WHATCHANGED — every criterion says what the fix does about it (operator 2026-09-04).** The **What the fix does about it** sub-line is mandatory on every entry, including one graded `NOT ADDRESSED`, and it names the changed object or file from the CHANGESET. A verdict with no statement of the behaviour behind it cannot be reviewed: `PASS` alone says a check passed, not that the right thing was built, and the reader's actual question — *what did you change, and does it do what we asked?* — goes unanswered by a table of grades. When a single change satisfies several criteria, say so and name them rather than repeating the change; when a criterion needed no change at all, that is the sub-line's content and it must say why.
- **R-AC-PROVENANCE — the block says where the criteria came from (operator 2026-09-04).** The **Criteria source** line is the block's first line and is never omitted. §2 already distinguishes criteria *stated on the ticket* from criteria this run *derived* when the ticket had none or stated them untestably — but that distinction lived only in the run output, so the posted comment presented both kinds identically. A reader grading a derived criterion `PASS` is being told the fix satisfies a requirement **this runbook wrote for itself**, and only the provenance line makes that visible. When any criterion is derived, the line also states that the derived list has not been confirmed by the reporter.
- **R-AC-VERDICT — one line answers "did it do what the ticket asked" (operator 2026-09-04).** The block closes with the **Acceptance verdict** count line, and when the satisfied count is short of the total it names the criteria that are open and why in the same line. Reviewers, QA and the reporter read the verdict before the entries, and a block that forces them to tally per-criterion grades to discover the fix closes three of five requirements is a block that gets read as "done".
- **R-RUN-BASIS — every terminal comment records what the run had (operator 2026-09-04).** The `Run basis` footer line is written on **all four** terminal comments, not just the RCA, because the run that most needs comparing later is usually the one that stopped. It carries two halves. **Ticket state:** the issue's `updated` instant at read time, Fix Version, environment field, reported build, customer, attachment count, the last comment read, and the description's character count. **Capability:** which config sections resolved, whether a database was reachable and its literal `<server>/<dbname>`, and whether an app environment was reachable with its build stamp. The capability half is the half nobody thinks to record and the half that matters most: three of the four reasons a developer re-runs this runbook are a capability that was missing the first time, and a comment that reports only its conclusion leaves the next run unable to tell a genuine re-analysis from a duplicate. The description is recorded as a **character count**, which is a tripwire and not a diff — it catches an edit, it does not describe one, and Step 0.0 reads the ticket's field history for that.
- **R-RERUN-DELTA — a re-run must name what changed, or it does not run (§1.6 Step 0.0, operator 2026-09-04).** Before anything else, §1.6 finds this runbook's own prior comments, reads their basis, and classifies the delta as `SETUP` / `DATABASE` / `APP-ENV` / `TICKET` / `EVIDENCE` / `NONE`. **The delta must intersect what actually limited the prior run** — a config section that resolved but feeds nothing this ticket needs is named and dismissed, not treated as a reason to re-analyze. No material delta is a STOP that posts nothing and leaves the labels alone. A material delta continues, and the resulting comment opens with the **Supersedes** block, so a ticket never ends up carrying two analyses with nothing saying which governs. Two consequences elsewhere: Step 0 may not read this runbook's own RCA and commit as evidence that someone resolved the ticket, and a `TICKET` delta is split **CORRECTION** (a requirement changed or was withdrawn — the pushed commit may implement a specification that no longer exists) from **EXTENSION** (the requirements grew — the earlier fix is right but partial, and the added criteria are graded as new items).
- **R-NO-INTERNAL-REFS — nothing this runbook calls itself appears in a comment (operator 2026-09-04).** The people who read a Jira comment are the reporter, a consultant, a customer and a QA analyst. **None of them has this document.** A label like `Deployed-object check (§1.7b)` or `Affected data (§3.11)` therefore reads as a reference to something that, for them, does not exist — it looks like a citation and resolves nowhere, which is worse than no label at all. Every published block label, and every sentence inside one, names the thing in plain words. Three specific bans, because these are the forms that keep creeping back:

  - **Section numbers** (`§1.7b`, `§3.11`, `§2.6 step 4`, `Step 0.0`) anywhere in text that reaches the ticket. They belong in the run output, in this file, and in the `< >` instructions that tell a run what to write — never in the written result.
  - **Rule codes** (`R-DB-PROVENANCE`, `R-ALIGN-TO-SIBLING`, `R-RUN-BASIS`). The single exception is the `Run basis` footer, which is machine-read state for the *next run* rather than prose for a human, and is labelled as such.
  - **Internal verdict tokens** as the reader's first encounter with a fact — `DEPLOYED-STALE`, `REPRODUCED-BOTH-AXES`, `SUBSTITUTE-DB-COLD`, `PORT-AVAILABLE`. Say what happened; append the token in backticks afterwards where a reviewer benefits (R-REPRO-PLAIN is the worked pattern), and never lead with it.

  The test before posting: **read the comment as somebody who has never seen this runbook.** Every symbol they cannot resolve is a symbol that should have been a sentence. This is the same rule the runbook applies to itself in reverse — inside *this file* the section numbers are the addressing system and must stay, because renumbering them to prose would break every cross-reference. The distinction is the audience, not the notation.
- **R-REPRO-PLAIN — the reproduction verdict is written in words, with the token kept as a tag (operator 2026-09-04).** The `REPRO` token is *derived* by R-REPRO-DERIVED and checked against the evidence ledger, so it stays exactly as it is in the run output and in every gate — it is a machine value and renaming it would break the derivation and the fail-closed check that reads it. What changes is how §6 **renders** it. `REPRODUCED-BOTH-AXES · reported-txn: … · new-txn: …` is unreadable to the people the comment is written for: the reporter, the consultant, the customer, and the QA analyst deciding whether to trust the analysis. It also hides the single most important thing the comment says, which is whether anyone ever actually made the error happen. So the line **leads with the sentence, explains each axis in words, and carries the token in backticks at the end** for the reviewer who wants the machine value. Fixed wording per verdict, so the meaning does not drift run to run:

  | `REPRO` verdict | The sentence the comment opens with |
  |---|---|
  | `REPRODUCED-BOTH-AXES` | **Reproduced.** We made the error happen ourselves, on the transaction the ticket reports and on a new one we created |
  | `REPRODUCED-DB` | **Reproduced on the customer's data.** We ran the failing operation against a copy of the reported database and it failed the same way |
  | `REPRODUCED-RUNTIME` | **Reproduced in the application.** We drove the screen ourselves and saw the reported behaviour |
  | `REPRODUCED-REPO` | **Reproduced, but not on the customer's environment.** We raised the error on a database built from our own source code, so it is still unconfirmed that the customer is running this same version |
  | `REPRO-ATTEMPTED-DISPROVEN` | **Not reproduced, and that is itself the finding.** We ran the failing operation and it behaved correctly, so the cause described here is not confirmed |
  | `NOT-REPRODUCED-TXN-ABSENT` | **Not reproduced.** We ran the failing operation, but the transaction the ticket names is not present in the database copy we had, so there was nothing to test against |
  | `NOT-REPRODUCED-NO-ENV` | **Not reproduced.** No copy of the database and no working environment were available, and this kind of failure cannot be made to happen from the source code alone |
  | `NOT-ATTEMPTED` | Never appears in an RCA — this verdict bars the RCA outright (§6.5 D triage instead). Any comment carrying it is a §6 defect |

  Two things this rule does **not** license. It is not permission to soften: the sentence for a non-reproduction says *not reproduced* in its first two words, and the heading rule for an unreproduced root cause (below) still applies unchanged. And it is not permission to paraphrase per run — the wording above is fixed, because a verdict re-worded by each run is a verdict readers cannot compare across tickets.
- **R-VERDICT-HONESTY — `PASS` means observed (operator 2026-08-17; ref AP-24899).** The Acceptance Verification verdict vocabulary is closed, and the distinction is *how the result was obtained*, never how confident the analysis feels:

  | Verdict | Permitted only when |
  |---|---|
  | `PASS` | The stated result was **observed** — a query/`EXEC` was run and its output is quoted, a screen was driven and captured, `liquibase update` returned. Quote the evidence |
  | `FAIL` | Same, and the observation contradicted the criterion |
  | `UNVERIFIED — static reasoning only` | The criterion was reasoned from source code and **not executed**. Must name what would settle it |
  | `NOT TESTED — <reason>` | No attempt was possible (no DB, no `APP_ENV`, shared server / no writes). Name the blocker |
  | `NOT ADDRESSED — <reason>` | The changeset **deliberately does not implement** this criterion. A scope decision, never an environment limitation. Name why it was left, what would close it, and any follow-up ticket |

  **`NOT TESTED` and `NOT ADDRESSED` are different claims and are not interchangeable (operator 2026-09-04).** The first says *we could not check it*; the second says *we did not build it*. Grading an unimplemented criterion `NOT TESTED` reads as a missing database and hides a scope gap behind an environment excuse — the reviewer waits for a test that would never have passed. Before writing `NOT TESTED`, ask whether the criterion would pass if the environment appeared; if the answer is no, the verdict is `NOT ADDRESSED`.

  **Forbidden**: `PASS (static)`, `PASS (static + DB corroboration)`, `PASS (code)`, or any other construction that attaches `PASS` to something nobody ran. AP-24899 graded all four of its criteria `PASS` on that basis while the actual defect sat unexecuted in a stored procedure — the grade is what made a wrong RCA read as a tested one, and it is what a reviewer, QA, and the customer all relied on. Reading a table, matching values, and finding a plausible mechanism are *investigation*; they are not test results. A criterion whose evidence is `ANALOGY` (§1.8 Axis A) or `SUBSTITUTE-DB` can never be `PASS`.
- **R-PATCH — the patch verdict is never absent (§3.10).** A CHANGESET containing a database object MUST carry a **Deployable patch** line naming the attached `<JIRA>Patch.sql`, its objects, its build constraint and its execution result; one that contains none MUST carry `N/A — no database object in this changeset`. Both an unexplained omission and a patch described as executed when nothing was run are §6 STOPs. The `PASS`-means-observed rule above governs this line too: "applies cleanly" is a claim about an execution, and it may only be written when the execution happened.
- **R-OBJECT-OWNERSHIP — the ownership verdict is never absent, and a held object is never described as pushed (§2.6).** Every delivered code fix carries the **Object ownership** line, in both directions: all-owned reads as such with its counts; a held artifact says the repository was not modified, names the owner and the evidence behind it, points at the patch, and gives the three routing options. Two constructions are §6 STOPs: an ownership line missing from a code-fix RCA, and any wording that implies a branch or commit exists for a held object (`READY-FOR-PR`, "pushed on", "merged to"). **The comment also states that the ticket has not been moved** — this runbook re-homes nothing (R-NO-REHOME).
- **R-DATA-SWEEP — the affected-row count may not be softened (§3.11).** When the sweep found rows, the **Affected data** line carries the integer, the identifiers and the swept scope, and states that this code fix does not repair them and a `Data Fix` JIRA is required. Never replace the count with a qualitative phrase ("some records may be affected", "a small number of vouchers"): the number is what sizes the data fix, and a phrase in its place reads as reassurance nobody measured. A non-zero count also appears in the plain-language summary — and this runbook neither files that Data Fix JIRA nor authors the fix under this key.
- **The Summary (non-technical) block inherits the reproduction status.** When `REPRO` is not a `REPRODUCED-*` verdict, the summary says so in plain language ("we have identified a likely cause but have not yet been able to make the error happen ourselves") — a confident plain-language summary over an unreproduced hypothesis is the single most misleading artifact this runbook can emit, because it is the block non-technical readers act on.
- **R-RUN-TELEMETRY — the comment closes with what the run cost (§6.8).** Measure from `RUN_START_UTC` and append the two-line telemetry footer inside this same comment body — never as a second comment. Unmeasurable → the explicit `Run telemetry unavailable` line; never an estimate, never a silent omission.
- **R-RCA-LINKS — every address the RCA names is reachable in one click (operator 2026-08-29).** A branch name, a commit SHA, a file path, a PR number, a related JIRA key and a guideline page id are all *addresses*. Written as bare text they hand the reader a search task, and the reader is a reviewer, a QA analyst or a customer-facing consultant who will not perform it. Link them:

  | Thing named | Link form |
  |---|---|
  | Feature branch | `https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>?version=GB<url-encoded branch>` |
  | Commit | `https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>/commit/<full SHA>` |
  | Changed file | `…/_git/<ADO_REPO>?path=/<repo-relative path>&version=GB<url-encoded branch>` |
  | Related JIRA key (§3.8 lineage, §1.6 prior art, a linked program JIRA) | `<the Jira site host taken from THIS issue's own browse/self URL>/browse/<KEY>` |
  | Guideline / template page cited | that page's Confluence URL — never the bare page id |

  What makes the links true rather than decorative: **URL-encode the branch** (`/` → `%2F`); build every URL from what §5 **actually pushed** and from `ADO_REPO` resolved off the origin remote, never from a remembered org/project; **never link a branch diff or a pull request** — neither belongs in the comment (operator 2026-09-01); and **never link a §2.6-held or unpushed path** — a link asserts the thing is there, so those are named in backticks with the note that the repository was not modified. **When the comment is posted as `adf` to satisfy R-COMMENT-MENTIONS, markdown `[text](url)` is inert text** — carry each link as a `link` mark on its text node (`{"type":"text","text":"<FEATURE_BRANCH>","marks":[{"type":"link","attrs":{"href":"<url>"}}]}`); a mention-bearing comment full of raw `[text](url)` is the same failure as a markdown `@Name` that notifies nobody. A link that 404s is worse than no link: emit one only when every component came from a resolved value, and write `<not linkable — <reason>>` otherwise.
- Do NOT use the Jira REST API directly.
- FAIL (STOP) if the tool is unavailable.

## §6.4 Pre-post validation — the comment is checked before it is posted (R-RCA-VALIDATE, operator 2026-09-09)

**Assemble, then check, then post — in that order, on every comment this runbook emits.** This gate is the only rule in §6 that does not depend on the run having read a current copy of anything, which is why it is the part that actually holds. Everything above it describes the shape; this decides whether what was assembled *is* that shape.

**Scope.** Checks 1, 2, 3 and 7 are the RCA's — they are about the register and the acceptance block. Checks **4, 5, 6, 8, 9 and 10** apply to **every** comment this runbook posts: the §6 RCA, the §6.5 CANNOT-FIX / TRIAGE / specified-behaviour protocols, the §1.6 information request and the §1.8b environment request. A blocked run's comment is read by the same reporter, and a placeholder or a leaked rule code costs exactly as much there.

Run these ten checks against the assembled body immediately before the `addCommentToJiraIssue` call:

1. **Form resolved** — exactly one of `CODE_FIX` / `DATA_FIX` / `COMBINED` / `ANALYSIS_ONLY`, named in the run output. Two forms, or none, is a stop.
2. **Every owed block present**, in register order, judged against what the run's gates actually did — never against what the assembler happened to produce.
3. **Every block the register gives an `N/A` form carries it.** For those blocks absence is a failure in both directions: `PATCH`, `CLIENT_TREE`, `OWNERSHIP`, `SCHEMA_VALIDATION`, `RECORDS_AFFECTED`, `SIBLING_ALIGN`, `REGRESSION_IMPACT`, `PROPERTY_TEST`, `DEFECT_LINEAGE`.
4. **No template remnant** — no unfilled `<…>` instruction text, no placeholder token, nothing that reads as an authoring note to the ticket's reader.
5. **No internal reference (R-NO-INTERNAL-REFS)** — no `§`-number, no `R-*` code, no gate or file name from this chain, no verdict token used as the reader's first encounter with a fact. The one sanctioned exception is the `Run basis` footer label.
6. **Footer complete (§6.8)** — run basis, runbook version, `rca-contract` version, model, and the run line or its exact unavailable wording. A footer missing the contract slot makes the comment unattributable to a shape.
7. **Acceptance block well-formed** — `AC_SOURCE` first, one entry per criterion, `AC_VERDICT` last, and the verdict's four counts summing to the criterion count. A block whose entries are marked *stated* while its source line says the ticket carries no criteria fails this check: both cannot be true (ref RM-13209).
8. **Verdict vocabulary closed (R-VERDICT-HONESTY)** — `PASS` and *observed* appear only where a result was seen. An inferred pass fails the check; it is not a wording preference.
9. **Mentions and links are real** — posted as `adf`, mentions are `mention` nodes and links are `link` marks (R-COMMENT-MENTIONS, R-RCA-LINKS). A rendered `@Name` notifies nobody and a bare `[text](url)` navigates nowhere. The current assignee is mentioned on every comment.
10. **Numbers are not softened** — affected-row counts, criterion counts, coverage counts and dependent counts are integers. "Several", "a few", "minimal" and "none to speak of" all fail.

**Fail-closed.** Any failing check stops the post. Fix the body and re-validate. Where a value genuinely cannot be produced, emit that block's not-run disclosure — **never drop a block to get past this gate**, which would be the defect the gate exists to catch, committed by the gate itself. Record one line in the run output so a batch pass is auditable without re-reading Jira:

```
RCA_VALIDATION: PASS (form=CODE_FIX · contract 1.0.0 · 26 owed / 26 present · 2 N/A stated · 0 internal refs · footer complete)
```

**Why a gate and not another rule.** Two rules already in this document did not hold, because nothing checked the body before it went out. The runbook-version stamp has been mandatory since 2026-09-02, yet **28 of the 65** comments posted on or after that date carry no version. Internal references have been banned since 2026-09-04, yet **21 of the 47** comments posted on or after that date publish **102** of them. Both were written as requirements and both were followed at the attention level of whoever ran the runbook that day. A rule that is only read is a rule that holds sometimes; a check that runs before the post either passes or stops the run.

## §6.5 Additional comment protocols (operator 2026-08-06)

**A. CANNOT-FIX comment (FEASIBILITY = CANNOT-FIX, §1.6).** When the run concludes the issue cannot be fixed by this runbook (module ownership elsewhere, won't-fix/by-design candidate, cross-team dependency), post ONE comment — never skip silently:

```
# Automated analysis (JIRA-AI) — cannot deliver a fix on this ticket

**What was analyzed:** <code paths read, evidence used — the full detail, so nobody repeats the work.>
**Database:** <MANDATORY whenever any database evidence is cited (R-DB-PROVENANCE): the §1.8 ledger's `DB touched` + `DB provenance` — a shared server as `<server> / <dbname>` + build, a local restore by its acquisition source only, and which HDTN supplied the copy when the ticket lists more than one. "No database was used" when that is the case.>
**Why not fixable here:** <owning module + the exact artifact / the dependency / the by-design behavior, with evidence.>
**Suggestion / recommendation:** <the concrete next step: which team/module should own it, the specific object to change, or the dependency to resolve first.>

----------------------------------------------
*Automated analysis — JIRA-AI runbook <RUNBOOK_VERSION> · <model name>*
*Run basis (R-RUN-BASIS) — ticket: `updated <ISO instant read>` · fixVersion `<v>` · env `<field>` · build `<stamp>` · customer `<c>` · `<n>` attachment(s) · last comment read `<id or date>` · description `<chars>` chars; capability: config `<sections that resolved | none>` · DB `<server>/<dbname> | not reachable>` · app env `<url + build stamp | not reachable>`*
*<the §6.8 telemetry line, verbatim from the script — or `Run telemetry unavailable — transcript not readable.`>*
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

**Rules 2 and 4 are BARRED when the ticket carries a screen recording this run decoded** (§1 step 5, **R-VIDEO-EVIDENCE**): the steps and the error text were supplied, and asking for them again is the R-EVIDENCE-UNREADABLE failure in a different costume — it tells a reporter who did more work than most that they did none. Where `ffmpeg` **ran** and the file itself would not decode — a truncated or corrupt upload — ask for the one thing that leaves open, and name the failure as ours: *"the recording could not be decoded here (<ffmpeg’s error>) — a screenshot of the error dialog, or the error text pasted as text, would unblock this"*. Never for the recording again, and never for the steps it already shows. **A missing decoder never reaches this comment at all**: that case STOPs the run with nothing posted (§1 step 5 sub-item 5), because the reporter must not be asked to cover for a tool we did not install.

**C. RESOLVED-BUT-UNDOCUMENTED note.** When the issue is (or becomes) resolved but the ticket's description lacks the information an automated analysis needed (build/family, repro documents, DB location, exact error), post a SHORT note listing exactly which of the six items above were missing — so the next ticket from the same reporter arrives analyzable. One comment, no label.

**D. TRIAGE comment (R-NOFIX-COMMENT fallback).** When a run analyzed the issue but ended WITHOUT delivering a fix and without falling into an information-request / cannot-fix / fix-delivery case — a §3 validation FAIL, a failed DB restore, a `DB-VERSION-MISMATCH`, an unresolvable branch, an implementation the run could not complete safely — post ONE comment so the ticket carries what the run learned. Label `JIRA-AI-Triaged`. Never leave a ticket with nothing after an analysis.

```
# Automated triage (JIRA-AI) — analyzed, not fixed

**Verdict:** <the classification and why the run stopped, in one line>
**Target branch:** `<TARGET_BRANCH>` (derived from <evidence>)  ·  **Module/repo:** <PRODUCT / repo>
**Requirements found:** <n — list each distinct reported defect when there is more than one>

**What was analyzed:** <the code paths read, the objects checked, what was ruled out — enough detail that the next person does not repeat it.>
**Findings so far:** <the suspected mechanism, named concretely, or "root cause not yet established".>
**Why no fix was delivered:** <the specific blocker: which validation failed, which check could not be run, what the mismatch was.>
**What would unblock it:** <the concrete next step.>

----------------------------------------------
*Automated analysis — JIRA-AI runbook <RUNBOOK_VERSION> · <model name>*
*Run basis (R-RUN-BASIS) — ticket: `updated <ISO instant read>` · fixVersion `<v>` · env `<field>` · build `<stamp>` · customer `<c>` · `<n>` attachment(s) · last comment read `<id or date>` · description `<chars>` chars; capability: config `<sections that resolved | none>` · DB `<server>/<dbname> | not reachable>` · app env `<url + build stamp | not reachable>`*
*<the §6.8 telemetry line, verbatim from the script — or `Run telemetry unavailable — transcript not readable.`>*
```

Rules: dedupe against an unanswered prior JIRA-AI triage comment for the same blocker (report "triage unchanged since `<date>`" and post nothing); never name a local restore's server/database (R-DB-LEDGER-REUSE), but always identify the database the evidence came from per **R-DB-PROVENANCE** — a shared server named as `<server> / <dbname>` + build, a local restore by its acquisition source, and which HDTN supplied it when the ticket lists more than one; never state a root cause that was neither statically proven nor reproduced on a database; append the §6.5 B Reporter Rules note where a rule applies.

**E. PREMISE CHALLENGE comment (`PREMISE-REFUTED` / `PREMISE-CONTESTED`, §2.4).** When the premise gate found that the reported behaviour is specified, asserted, invariant-bound, or was somebody's deliberate decision, the run posts this **instead of** an RCA and **instead of** the D triage — no branch, no commit, no code. It is not a refusal and must not read as one: the run is not saying the reporter is wrong, it is saying the ticket asks to change behaviour that something already settled, and **naming who can settle it now**.

```
# Automated analysis (JIRA-AI) — the reported behaviour appears to be specified

**Verdict:** <`PREMISE-REFUTED` — an authority contradicts the report | `PREMISE-CONTESTED` — the behaviour was a deliberate decision and no specification settles it>
**Target branch:** `<TARGET_BRANCH>` (derived from <evidence>)  ·  **Module/repo:** <PRODUCT / repo>

**What the ticket asks for:** <the disputed behaviour and the expectation, in the reporter's own terms — quoted, never paraphrased into the run's framing.>
**What the current behaviour is, and why:** <the mechanism that produces it, named concretely — the object, the construct, the computation.>
**What says it is correct:** <the rung that answered, as something the reader can OPEN and check:
  - a specification page: title + link, pinned `v<version>`, "baselined on `<branch>`, verified `<date>`" — and, when the page is baselined on a DIFFERENT branch, say so plainly instead of implying it binds here;
  - a test: id, what it asserts, that it is present on `<TARGET_BRANCH>`;
  - an invariant: the identity, computed BOTH ways, with the arithmetic on its own line;
  - a deliberate origin: `<KEY>` (`<commit>`, `<date>`, `<author>`) and the sentence of ITS acceptance criteria that asked for this behaviour — quoted;
  - peers: the objects that compute the same quantity the same way, with counts.>
**What this run did NOT do:** no code was written and no branch was pushed, because a fix here would reverse <the specification | the decision in `<KEY>`> rather than correct a defect.

**What is needed to proceed:** <exactly one decision, addressed to named people — "confirm whether the behaviour on `<screen/object>` should change from `<current>` to `<requested>`; if it should, this becomes a change request against `<KEY>`'s decision and needs <BA> and <module owner> to agree the specification moves.">

cc <the BA on the ticket, and the module owner §2.6 resolved>

----------------------------------------------
*Automated analysis — JIRA-AI runbook <RUNBOOK_VERSION> · <model name>*
*Run basis (R-RUN-BASIS) — ticket: `updated <ISO instant read>` · fixVersion `<v>` · env `<field>` · build `<stamp>` · customer `<c>` · `<n>` attachment(s) · last comment `<date>`*
*<the §6.8 telemetry line, verbatim from the script — or `Run telemetry unavailable — transcript not readable.`>*
```

Rules:

1. **Never posted on `UNVERIFIED`.** A ladder that found nothing is not an authority. `UNVERIFIED-PROCEEDING` posts the ordinary RCA carrying the R-PREMISE-ANCHOR banner; a wide-blast-radius `UNVERIFIED` posts this comment **as `CONTESTED`**, and its "what says it is correct" section then states the blast radius as the reason for asking rather than dressing an absence up as evidence.
2. **The citation must be openable.** A page title without an id and version, a test without an id, an invariant without its arithmetic, or an origin without the quoted criterion is not a citation — it is an assertion, and this comment exists precisely to stop one of those from ending a customer's ticket.
3. **Dedupe** against an unanswered prior premise challenge for the same disputed behaviour: report `premise challenge unchanged since <date>` and post nothing.
4. **The ticket does not move and is not closed.** Status untouched (R-NO-REHOME applies here too), label `JIRA-AI-PremiseChallenged`, AI-Assisted stamped as on every run (R-AI-ASSISTED). Deciding that a report is not a defect is a human's call, and this runbook does not make it — it assembles the evidence and asks.

## §6.6 Status handoff (R-STATUS-HANDOFF)

Runs after the §6 / §6.5 comment. Purpose: make the ticket's state reflect what the run did, so the next batch pass does not re-pick its own in-flight work and humans can see at a glance which tickets are waiting on them.

**Config gate:** enabled by default; the operator can disable it for a run (`statusHandoff = off`), in which case the intended transition is reported in the run output but not applied.

1. **Resolve the transition by name, never by id:** `getTransitionsForJiraIssue` on `<JIRA>`, then match the target status name case-insensitively against the available transitions. **No matching transition available → do not force anything:** report `status handoff skipped — no transition to <target> from <current>` and continue. A workflow that does not permit the move is the workflow's decision, not an error. **Target the status by meaning** — projects name this state differently, and the reference-scheme name may not exist here.

   **A transition that exists but is REJECTED for missing required fields is skipped the same way.**
   Projects put required fields on transition screens (worked example, AP: the `Coding` transition returns
   HTTP 400 when `Components` or `Business Analyst` is empty). Do **not** populate someone else's required
   field to force the move: report `status handoff skipped — <target> requires <field(s)>` and continue.
   The §6.6 **label** is the durable state the queue selector reads (R-QUEUE-LABEL-STATE), so a skipped
   transition costs the next pass nothing — whereas a guessed Business Analyst puts a real person's name
   on work they never triaged.
2. **Target status by outcome:**

| Run outcome | Transition | Label |
|---|---|---|
| Fix delivered — branch pushed (§5) | → the project's **"code written, not yet in review or test"** status (reference scheme: `Coding`) — the fix exists but no PR has been raised; the PR runbook or a human owns the next move | `JIRA-AI-Fixed` |
| Data fix delivered (§3.6) | → the same status — and the comment states that Senior BA review is pending | `JIRA-AI-DataFix` |
| Artifact held by §2.6 — diagnosis delivered, nothing authored and nothing committed (`OWNERSHIP_ROUTE` = `FOREIGN-EXTERNAL` / `UNDETERMINED`) | **no transition** — there is no branch and, since operator 2026-08-31, no authored fix either; the routing question belongs to a human. **Never re-home:** no project change, no reassignment, no ticket raised elsewhere (R-NO-REHOME) | `JIRA-AI-OwnerReview` |
| Information requested (§1.6) | **no transition** — the issue stays `Open`/`Reopened` because the reporter still owns it | `JIRA-AI-NeedInfo` (existing) |
| Database requested | **no transition** | `JIRA-AI-NeedInfo` (existing) |
| `CANNOT-FIX` | **no transition** — routing/ownership is an operator decision, not an automated status change | `JIRA-AI-CannotFix` |
| Triage only (§6.5 D) | **no transition** | `JIRA-AI-Triaged` |
| Premise challenged (§2.4 `REFUTED` / `CONTESTED`, §6.5 E) | **no transition** — the ticket is not blocked and is certainly not closed; whether the reported behaviour is a defect at all is a human decision this runbook does not make | `JIRA-AI-PremiseChallenged` |
| `ALREADY-RESOLVED` | **no transition** — the run happened and found the fix already present | no label; the step 5 stamp still applies |
| Out-of-status / out-of-type — declined at the gate, never a run | **no transition** | no label, and **no stamp**: nothing at all is written to the issue |

3. **Assignment:** when the issue is **unassigned**, assign it to the run operator. **Never reassign an issue that already has an assignee** — that person owns it, and silently taking it is exactly the collision the status gate exists to prevent.
4. **Labels are additive, always** — re-send the issue's existing labels alongside the new one; never overwrite the label set (same rule as `JIRA-AI-NeedInfo`).
5. **Stamp the AI-Assisted field — `Manual AI` (R-AI-ASSISTED, operator 2026-09-02).** **Every outcome of a run takes the stamp**, whatever it was: fix delivered, data fix, owner review, information requested, database requested, `CANNOT-FIX`, triage and `ALREADY-RESOLVED` alike. The field records that automated analysis was **applied to this ticket**; the §6.6 label records what that analysis **concluded**. Those are different questions, so the stamp does not vary with the outcome and nothing in the table above is exempt from it — an outcome that earns no label still earns the stamp. What it buys: the work is visible on the issue itself and countable in JQL, and the labels live in the automation's own namespace while this field is the one the business reports on.

   - **The two gate declines are not run outcomes.** A ticket refused by the **Issue type gate** or the **Issue status gate** is turned away *before* any analysis, and those STOPs are defined as writing to Jira in no way at all — no comment, no label, no field. That is unchanged: there was no run to record, and stamping one would put `Manual AI` on a `Feature` nobody analysed.
   - **Write it by id, never by name: `customfield_14679`.** The field is spelled **`AI-Assissted`** in Jira — a typo in the field's own definition, carried site-wide. A name match will miss it, and the resulting "field not found" reads exactly like "field not configured for this project", which it is not.
   - **Payload:** `editJiraIssue` on `<JIRA>` with `{ "customfield_14679": { "value": "Manual AI" } }`. It is a single-select whose full option set is `No` (id `16153`) / `Full AI` (`16154`) / `Manual AI` (`16155`) — address it by `id` only if a deployment ever needs to. `Manual AI` is this runbook's value because the run stops at a pushed branch: a human still reviews, tests and merges it. `Full AI` belongs to a flow that carries the work further than this one does.
   - **Never downgrade a value that is already there.** Write only when the field is empty or reads `No`. **Both of those starting states are real, and neither is a human's answer** (measured 2026-09-02): the field is empty on essentially the entire backlog — 415,905 issues — while tickets raised from 2026-09-02 onward carry `No` as a **create-time default**. That default is not universal: on the same day, `Bug-QC` and `Bug-Ongoing UAP` tickets were still being created empty, and both are in-scope issue types here. So never implement this as *write only when empty* — that silently turns the stamp into a no-op on most tickets raised from now on — and never read `No` as "a person decided AI was not involved". A ticket already marked `Full AI` was stamped by that further-reaching flow, and overwriting it destroys the only record of it. A ticket already reading `Manual AI` is a no-op on re-entry, not a rewrite.
   - **Rejection is non-blocking, exactly like the transition.** The field absent from the project's edit screen, or `editJiraIssue` refusing it, is reported as `AI-Assisted stamp skipped — <reason>` and the run continues. The §6.6 **label**, not this field, is the durable state the queue selector reads (R-QUEUE-LABEL-STATE) — a missed stamp costs the next pass nothing.
6. **Never** transition an issue into a status meaning *ready for test*, *in test*, *done*, or *closed* (reference scheme: `Testing`, `Ready to Test`, `Closed`, `Done` — match by meaning, since the names differ by project). This runbook does not certify delivery: a fix that is merely pushed is not testable, and closing is a human judgement.
7. Record the applied (or skipped) transition, assignment, labels, and AI-Assisted stamp in the run output.

## §6.7 PR handoff (R-PR-HANDOFF)

This runbook creates no PR. It ends by stating, in a machine-readable form, that a branch is ready — so `JIRA-PR-Automation.md`, the propagation runbook, or a scheduled job can pick the work up without re-deriving any of it.

**On a delivered code fix**, emit this line BOTH as the last line of the run output AND as the closing line of the §6 RCA comment:

```
READY-FOR-PR: <PRODUCT> | <ADO_REPO> | <FEATURE_BRANCH> → <TARGET_BRANCH> | <JIRA> | <n> file(s)
```

- The values come from what was actually pushed in §5 — never from intent. If the push did not succeed, no handoff line is emitted (and no RCA comment exists to carry it).
- When §3.5 launched the async schema-change confirmation, append `| schema-confirmation: pending (result will be commented on the PR)` so the reviewer knows a ✅/❌ is still inbound.
- When §3.7 returned `UNEXPECTED-DELTAS`, append `| regression-flag: <k> unexpected delta(s) — DO NOT auto-complete` so the PR flow cannot merge it unreviewed. When §3.7 tier 2 was skipped, append `| regression: tier-2 not run (no DB)`.
- When §3.10 produced a patch, append `| patch: <JIRA>Patch.sql (<n> object(s), <executed|not executed>)` so the PR owner knows a deployable artifact exists and whether it was proven on a database.
- When the §3.11 sweep found rows, append `| datafix-required: <n> row(s) already affected` — the PR closes the code defect and leaves those rows broken, and whoever completes it needs to see that before it disappears into a merged PR. This is a marker only: no ticket is filed here.
- When §2.5 returned `PORT-AVAILABLE`, append `| port: from <repo>/<branch> (<n> exclusion(s))` so the PR reviewer knows the body was aligned to a sibling line rather than authored here, and how many portions were deliberately stripped — the two things a reviewer would otherwise have to reconstruct from the diff. When §2.5 returned `NOVEL-JUSTIFIED`, append `| novel-fix: sibling <branch> holds the behaviour — see RCA` so the choice is reviewed, not assumed.
- When §3.8 found `COVERAGE_GAPS`, append `| coverage-gap: <line>=<state>, …` so the PR/propagation owner sees which other lines still carry the defect. This is a marker only — this runbook never propagates and never files a ticket in another team's project.
- **When §2.6 returned `FOREIGN-SHARED` (Tier 1), append `| owner: <project> (FOREIGN-SHARED) — <project> review REQUIRED before this PR is raised`** (R-HANDOFF-OWNERSHIP, operator 2026-08-31). A Tier-1 fix is pushed on our branch but changes an object another project maintains, and without this marker the PR runbook opens a PR on a foreign-owned change with no way of knowing it should not. This is the one marker that is a **precondition, not an annotation**: the downstream flow must add the owning project's reviewer as a required reviewer, and must not auto-complete. Ref AP-24914.
- **When §2.6 step 3a returned `DIRECTION-UNDECIDED`, append `| decision-required: root cause written by <object> (owner <project>) — fix direction not settled, DO NOT raise the PR`** (R-HANDOFF-DECISION, dev review 2026-08-31; ref AP-24889). Like the ownership marker above, this is a **precondition, not an annotation**: the branch is pushed and correct as far as it goes, but it implements one of two remedies to a question the owning module has not answered, and a PR raised on it commits the product to that answer silently.
- When the run touched more than one repository, emit one line per repository.

**On an artifact held by §2.6** (`FOREIGN-EXTERNAL` or `UNDETERMINED`) there is no branch, no PR and — since operator 2026-08-31 — no authored fix either: the **diagnosis** is the deliverable and the next decision is a human's. Emit instead (one line per held object):

```
ROUTING-REQUIRED: <JIRA> | <object> | owner: <OBJECT_OWNER> (<route>) | evidence: callers <n> (<breakdown>), history <n> commit(s) <keys> | patch: <JIRA>Patch.sql (<n> object(s), <executed|not executed>) | repository NOT modified | ticket NOT moved
```

Never emit `READY-FOR-PR` for a held object: there is no branch to raise a PR from, and a handoff line naming one sends the PR runbook looking for a branch that does not exist. When the changeset was mixed and separable, both lines are emitted — `READY-FOR-PR` for the `OWNED` files that were pushed, `ROUTING-REQUIRED` for the held ones — and the RCA says which part is which.

**On a delivered data fix** there is no branch and no PR. Emit instead:

```
READY-FOR-REVIEW (data fix): <JIRA> | <JIRA>DataFix.sql | records affected: <n> | Senior BA sign-off required
```

Nothing in this section creates, approves, or completes a pull request — that boundary is unchanged.

**The RCA carries the same handoff as clickable links (R-RCA-LINKS).** The `READY-FOR-PR` line above stays machine-readable and unlinked — it is parsed, not clicked. Its human counterpart is the **Delivery** block at the top of the §6 RCA, which links the feature branch and the commit — and, since operator 2026-09-01, **nothing else**: no branch-vs-target diff link and no pull-request link. Emitting one without the other is a §6 defect: a reviewer left to hand-assemble an Azure DevOps URL out of a pipe-delimited line is exactly the friction this handoff exists to remove.

## §6.9 Knowledge draft — state the run's claims so they can be graded (R-KNOWLEDGE-DRAFT)

This runbook never writes to the knowledge base (§1.6e step 8). It states what it believes, in a form `JIRA-AI-Reconcile.md` can grade against what actually merged and what the developer said — and a claim that is never stated is never graded, so the base learns nothing from the run.

**Emit these three blocks as the closing lines of the §6 RCA comment, immediately before the `READY-FOR-PR` line** (or last, when there is none — a triage, a cannot-fix and a data fix all still made claims). They are one contract, read together by the dev review and by the reconciler:

```
KNOWLEDGE-DRAFT: <JIRA>
C1 mechanism   | <what the system actually does that produces the symptom>
C2 cause       | <why it does that — the statement, binding or row that decides it>
C3 fix-pattern | <what shape of change corrects it, stated so it survives this object>
C4 verified-by | <REPRO / property test / regression verdicts / static reasoning only>
KB-CONSULTED: <record path> = <used | confirmed-not-used | unconfirmed>; … | none (<no base | no key matched>)
RUN-GATES: <JIRA> | symptom=<QUOTED|CLASS-ONLY> | repro=<REPRO token> | premise=<PREMISE token>:<rung that answered: A1|A2|A3|A4|A5|self-evident|none> | origin=<w0 object.statement | WRITER-UNIDENTIFIED | N-A> | align=<ALIGN_VERDICT> | remedy=<selected layer:object> | rejected=<n> | coverage=<closed>/<total> | ownership=<OWNERSHIP_ROUTE> | datacause=<none|present|undetermined>
```

- **Four claims, one line each.** If a claim needs a paragraph it belongs in the RCA above; this block is what gets graded, not what gets read.
- **Keyed on the claim NAME, not the C-number.** The number is a label.
- **C4 states how far the claim was actually taken**, in the vocabulary §1.8 and §3.7 already use. `static reasoning only` is a legitimate answer and a far better one than a verification that did not happen.
- **Plain text, never linked**, on its own lines at the end of the comment — the same convention `READY-FOR-PR` uses, and for the same reason: a machine reads it.
- **Claim what this run established, not what it assumes.** A claim graded `CONTRADICTED` by the merged diff lowers the confidence of every fact drawn from it, so an overstated claim costs more than an absent one.
- **A knowledge-base hit that this run confirmed (§1.6e step 3) may be restated here; one that it did not confirm may not.** Repeating an unconfirmed pointer as a claim launders a candidate into a finding.
- **The four claims are graded individually.** `C1 mechanism` true and `C3 fix-pattern` wrong is the single most common outcome in the graded corpus — it is what "correct RCA, rejected fix" means — so a ticket-level verdict cannot express it and a run must not write the block as one argument. State each claim so it can stand or fall alone.

**`KB-CONSULTED` — what the base was asked, and whether it was believed.** Without it, nobody downstream can tell a run that read a record and ignored it from a run that never looked, and the dev review's `kb=` field is unanswerable from a fresh session. One entry per record actually read (§1.6e steps 1–5), each in exactly one state:

| State | Means |
|---|---|
| `used` | it entered the analysis, the remedy selection, or the RCA |
| `confirmed-not-used` | read and confirmed on this branch, and it turned out not to bear on this ticket |
| `unconfirmed` | a derived pointer that could not be confirmed on `TARGET_BRANCH` (R-KB-CONFIRM), so it never entered — **the run says so rather than dropping it silently** |

**A module consulted at §1.6e step 5 that held no fact still gets a line** — `modules/<CODE>/ = none (no <kind> fact for <objects>)`. Where the run widened past the ticket's own module (R-KB-WIDEN), that line is the only evidence it did: a widen that found nothing and a widen that never happened produce identical analyses, and only one of them is a gap. Name each module separately, the ticket's own included.

`none` is a legitimate and common value, and it carries its reason: no base on this machine, no key in the ticket matched, or no fact for the objects a remedy touches. It is never a failure — the base indexes one branch of one repository and a handful of tickets, and R-KB-ABSENCE governs.

**`PREMISE-CONSULTED` — the specification pages the §2.4 ladder read, recorded exactly like `KB-CONSULTED` (R-PREMISE).** One line per page actually opened: `iNet <space>/<page id> v<version> "<title>" = <used | confirmed-not-used | unconfirmed>`, where `unconfirmed` is the page that carried no baseline table for `TARGET_BRANCH` and therefore could not become authority. `none` carries its reason — no space for this module, no page matched the objects, or none of the matches was baselined. **A run that found a page and could not use it is the most valuable line in this block**, because it names a page one baselining away from being able to stop a bad ticket, and that is the shortest path from *"we have no source of truth"* to having one. State it as a claim in the four-claim draft when it bears on the outcome; this runbook writes no page itself (R-PREMISE-READ-ONLY).

**`RUN-GATES` — the gates' own verdicts, collected in one line.** Every token in it is a value the run has **already recorded** elsewhere in this runbook; this block copies them, it does not compute anything new. Its purpose is the failure mode no additional rule can fix: a gate that fired and was not honoured. SC-9232 posted a `REPRO` verdict its own evidence ledger contradicted, and AP-24960 recorded an origin trace as not-applicable on a ticket whose proximate cause was a stale stored value the same RCA reported twice. Both are visible in one line, to a reader who never opens the run's transcript, the moment the tokens sit side by side.

- **Copy the tokens verbatim from where they were recorded.** A value that disagrees with the prose above it in the same comment is a **§3 FAIL** (R-REPRO-DERIVED already says this for the reproduction verdict; it holds for all of them). This is arithmetic over the run's own writing and needs no evidence, no environment and no execution.
- **Write `N-A`, never `N/A`, inside this block** — `coverage=` carries a slash, and one unambiguous spelling keeps the line machine-readable.
- A gate that did not run because its trigger did not fire is `N-A`, and a gate whose verdict is genuinely unknown is `UNKNOWN`. Neither is omitted: a missing token and a token that says nothing ran are different facts, and only one of them is honest.

## §6.8 Run telemetry — what the run cost in time and tokens (R-RUN-TELEMETRY)

Every comment this runbook posts carries a footer stating how long the run took and how many tokens it consumed. Purpose: the ticket becomes the durable record of the run's cost. The run output dies with the session, so without this line nobody can answer "what did automated analysis cost on this ticket" a week later — and effort per ticket is exactly what sizes the automation's value against a developer's time.

**Where the numbers come from.** The harness writes one JSON-lines transcript per session under `%USERPROFILE%\.claude\projects\<project-slug>\<session-id>.jsonl`. Each assistant record carries its own `timestamp` and a `usage` object (`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`). Measuring from `RUN_START_UTC` (§1 PRE-REQ) over that file is the whole mechanism — no external service, no API call, no counter this runbook has to maintain.

**Run this immediately before composing the comment** (Windows PowerShell 5.1+, no modules, nothing written to disk — substitute `RUN_START_UTC`):

```powershell
# Run telemetry (S6.8): elapsed time + tokens for THIS run, measured from the run's own transcript.
# Separators are built by code point: PowerShell 5.1 reads a UTF-8 script as ANSI, so a literal
# middle dot in the source reaches Jira as mojibake. Keep this file's executable text ASCII-only.
$DOT   = [char]0x00B7
$DASH  = [char]0x2014
$FAIL  = '*Run telemetry unavailable ' + $DASH + ' transcript not readable.*'
$sid   = $env:CLAUDE_CODE_SESSION_ID                       # = RUN_SESSION_ID
$since = [datetime]::Parse('<RUN_START_UTC>').ToUniversalTime()
$self  = Get-ChildItem (Join-Path $env:USERPROFILE '.claude\projects') -Recurse -File -Filter "$sid.jsonl" -ErrorAction SilentlyContinue |
         Select-Object -First 1
if (-not $sid -or -not $self) { $FAIL; return }

function Read-Seg($path, $since) {
  $o = [pscustomobject]@{ First=$null; Last=$null; Stamps=(New-Object Collections.Generic.List[datetime]);
                          In=[int64]0; Out=[int64]0; Cw=[int64]0; Cr=[int64]0; Turns=0 }
  foreach ($l in [IO.File]::ReadLines($path)) {
    $m = [regex]::Matches($l, '"timestamp":"(20\d\d-\d\d-\d\dT[^"]+)"')
    if ($m.Count -eq 0) { continue }
    foreach ($mm in $m) {                                  # file bounds span EVERY record type - see rule 4
      $b = [datetime]::Parse($mm.Groups[1].Value).ToUniversalTime()
      if (-not $o.First -or $b -lt $o.First) { $o.First = $b }
      if (-not $o.Last  -or $b -gt $o.Last)  { $o.Last  = $b }
    }
    if (-not (($l -like '*"type":"assistant"*') -or ($l -like '*"type":"user"*'))) { continue }
    $t = [datetime]::Parse($m[$m.Count-1].Groups[1].Value).ToUniversalTime()
    if ($t -lt $since) { continue }
    $o.Stamps.Add($t)
    if ($l -notlike '*"type":"assistant"*') { continue }
    $i = $l.LastIndexOf('"usage":{')                       # the REAL usage follows the content array - see rule 5
    if ($i -lt 0) { continue }
    $s = $l.Substring($i, [Math]::Min(600, $l.Length - $i))
    if ($s -match '"input_tokens":(\d+)')                { $o.In  += [int64]$Matches[1] }
    if ($s -match '"cache_creation_input_tokens":(\d+)') { $o.Cw  += [int64]$Matches[1] }
    if ($s -match '"cache_read_input_tokens":(\d+)')     { $o.Cr  += [int64]$Matches[1] }
    if ($s -match '"output_tokens":(\d+)')               { $o.Out += [int64]$Matches[1] }
    $o.Turns++
  }
  $o
}

$segs = @(Read-Seg $self.FullName $since)                  # then walk back through compaction predecessors
$pool = Get-ChildItem $self.Directory -File -Filter '*.jsonl' | Where-Object { $_.FullName -ne $self.FullName }
$head = $segs[0].First
for ($g = 0; $g -lt 10; $g++) {
  if (-not $head -or $head -le $since) { break }
  $prev = $null
  foreach ($c in $pool) {
    if ($c.LastWriteTime.ToUniversalTime() -lt $head.AddMinutes(-15)) { continue }
    $s = Read-Seg $c.FullName $since
    if ($s.Last -and [Math]::Abs(($s.Last - $head).TotalSeconds) -lt 2) { $prev = $s; break }
  }
  if (-not $prev) { break }
  $segs += $prev; $head = $prev.First
}

$stamps = New-Object Collections.Generic.List[datetime]
foreach ($s in $segs) { $stamps.AddRange($s.Stamps) }
if ($stamps.Count -lt 2) { $FAIL; return }
$srt = $stamps | Sort-Object
$act = 0.0
for ($k = 1; $k -lt $srt.Count; $k++) { $d = ($srt[$k]-$srt[$k-1]).TotalSeconds; if ($d -gt 600) { $d = 600 }; $act += $d }
$in    = ($segs|Measure-Object In -Sum).Sum + ($segs|Measure-Object Cw -Sum).Sum + ($segs|Measure-Object Cr -Sum).Sum
$fmtN  = { param($n) if ($n -ge 1e6) { '{0:N1}M' -f ($n/1e6) } elseif ($n -ge 1e3) { '{0:N0}K' -f ($n/1e3) } else { "$n" } }
$seg   = if ($segs.Count -gt 1) { ' ' + $DOT + ' ' + $segs.Count + ' session segments' } else { '' }
'*Run: ' + [math]::Round($act/60) + ' min active (' + [math]::Round(($srt[-1]-$srt[0]).TotalMinutes) + ' min wall) ' + $DOT + ' ' +
  (& $fmtN $in) + ' input / ' + (& $fmtN ($segs|Measure-Object Out -Sum).Sum) + ' output tokens ' + $DOT + ' ' +
  ($segs|Measure-Object Turns -Sum).Sum + ' API turns' + $seg + ' ' + $DOT + ' measured to comment time.*'
```

**FOOTER (append to EVERY comment this runbook posts).** Two lines, last thing in the comment body, separated by the same `----` divider the other appendices use:

```
----------------------------------------------
*Automated analysis — JIRA-AI runbook 1.3.0 (source copy) · STALE — 1.4.0 is current · rca-contract 1.0.0 · <model name, e.g. Opus 5>*
*Run: 46 min active (52 min wall) · 31.2M input / 216K output tokens · 144 API turns · measured to comment time.*
```

Rules:
1. **It rides inside the comment that is already being posted — never its own comment and never its own tool call.** §6's "ONE `addCommentToJiraIssue` call" is unchanged; when the comment uses `contentFormat: adf` (R-COMMENT-MENTIONS), the footer is two italic paragraph nodes.
2. **All four comment types carry it:** the §6 RCA, the §6.5 A CANNOT-FIX, the §6.5 D TRIAGE, and the §1.6 INFORMATION REQUEST. A blocked or unfixable run is exactly the case worth measuring — restricting the footer to successful fixes would make the record read as though automated analysis only ever costs anything when it works.
3. **`measured to comment time` is mandatory wording, and the numbers are never adjusted upward to "account for" what follows.** The comment itself, the §6.6 label/transition and the §6.7 handoff all happen after the measurement. An estimate dressed as a measurement is the same defect R-VERDICT-HONESTY forbids in the Acceptance Verification block.
4. **Both clocks, always — active AND wall.** Active time sums the gaps between records with each gap capped at 10 minutes; wall is simply last minus first. A run left open over a break otherwise reports hours of "work" that nobody did (measured: one session at 1,131 wall minutes against 46.7 active). When the run spans a compaction, the script walks back through predecessor transcripts — a successor's first record lands within ~0.3s of its predecessor's last, and those bounds must be read from **every** record type, because the last thing written before a compaction is not a message (measured: assistant/user-only bounds miss the boundary by 539s and 63,543s). Counting only the final segment undercounts a long run several-fold.
5. **Never fabricated, never silently dropped.** No transcript, no `CLAUDE_CODE_SESSION_ID` (another harness, a plain-chat run), fewer than two records, or any error → the footer's second line reads exactly `*Run telemetry unavailable — transcript not readable.*` and the first line still names the runbook. Same fail-closed discipline as the §3.5 / §3.11 not-run disclosures. Note that `LastIndexOf('"usage":{')` is deliberate: an assistant message whose *text* discusses a usage object would otherwise be summed as if it were real accounting.
6. **No cost figure.** Tokens and minutes only — no USD, no rate, no extrapolation. Token prices depend on a commercial arrangement this ticket's readers are not party to, and a dollar amount on a customer-visible ticket invites a conversation about billing that the number cannot actually support.
7. **Headless `claude -p` child processes are NOT counted, and the footer never implies otherwise.** They write their own transcripts and the format records no parent-session link, so attributing them would be a guess. Where a run leaned on them heavily, say so in the run output — not in the footer.
8. Record the same figures in the run output alongside `RUN_START_UTC` and `RUN_SESSION_ID`, so a batch pass can total them without re-reading Jira.
9. **The runbook's OWN version rides on the first line (R-RUNBOOK-STAMP, operator 2026-09-02, amended 2026-09-03, ref SC-9232).** Resolve `RUNBOOK_VERSION` through this precedence chain and print `JIRA-AI runbook <version>`:

   1. **The `> **Version.**` blockquote directly under this file's title** — the authority. It is written by the packager into the shipped copy and it **travels with the content that actually governed the run**, so it survives every transport a sibling file does not: a runbook dropped in by hand, a pasted copy, a file read straight out of the maintainer repository, or an install predating the manifest. Three shapes, all printed as-is and never editorialised:
      - a **version** (`1.3.0`) — print `JIRA-AI runbook 1.3.0`.
      - a version marked **source copy** — the file was handed over directly rather than unpacked from a release zip. Print the version and append `(source copy)`, because `Install.ps1 -Verify` will report this file as `changed` against any manifest already on the machine: that is the expected consequence of a hand-distributed runbook, not evidence of corruption, and the reader needs to be able to tell the two apart.
      - **`working-copy`** — print `JIRA-AI runbook (working copy — unreleased)`. Truer and more useful than a number: it tells the reader the conclusion came from a runbook nobody has released.
   2. **`MANIFEST.json` at the root of the installed skill folder** (one level above the `runbook/` directory holding this file) — its `version`, with `builtAt` where a reader would benefit. Used only when the header is absent.
   3. `JIRA-AI runbook (version unknown)` — **never omit the slot, and never guess a number.** A version taken from anything else (a changelog, a memory, a zip filename lying around) is a guess, and a guess is recorded as `unknown`.

   **On disagreement the header wins, and the disagreement is itself reported.** The manifest describes the version whose files were *installed*; the header describes the bytes being *read*. When they differ, someone replaced this file by hand — record `RUNBOOK_VERSION = <header> (manifest says <manifest version> — file replaced out of band)` and carry it into the comment. Neither mechanism is sufficient alone and they fail differently: a header is an author's claim and lies if the content changed without a rebuild, while the manifest is a measurement (`Install.ps1 -Verify` hashes every file against it) and catches exactly that case. Together they cover both.

   **Why this line exists.** A runbook is a document that changes weekly, so a root cause is only interpretable against the generation that produced it. Without the stamp, *"was this conclusion reached by a runbook that carried the fetch ladder?"* is answerable only by archaeology across three separate copies, and a reader has no way to tell a conclusion reached under today's gates from one reached under gates that did not yet exist. With it, the whole fleet is auditable from Jira alone: one JQL search over comment text partitions every published conclusion by the rules in force when it was reached, and a rule added after a bad RCA can be checked for effect instead of assumed to have had one.

   Measured on SC-9232 (2026-09-02): the installed skill tree was missing **32 of the source runbook's 76 `R-*` rules** — including R-EVIDENCE-UNREADABLE, R-REPRO-STEPS and R-GATE-NOT-SELF-EXCUSED, each of which would have stopped the run that published the wrong cause — while the package's own preflight reported every file current, because it validates a package against itself and knows nothing of the authoring source. Three RCAs were posted across six days and not one of them said which generation had produced it. **Integrity is not currency:** a copy can be provably intact and still be months behind, and only a version on the ticket makes the difference visible to the person reading the conclusion.

10. **Is the runbook being executed the newest one? Ask GitHub, never a local file (R-RUNBOOK-CURRENCY, operator 2026-09-03, ref SC-9232).** The stamp above says *which* generation ran; this says whether that generation is *current*. It compares **the runbook this run is executing** against the authoritative copy, because those are the only two things whose disagreement matters — a manifest describes what an installer once placed on the machine, which is a different question and answers it for a file that may since have been replaced.

    **A missing `MANIFEST.json` is not an error and never blocks anything.** Most installed copies have none, a hand-distributed runbook has none by construction, and the version resolves from the header regardless (rule 9). Nothing in this runbook requires a manifest to run.

    **The comparison.** Resolve `RUNBOOK_CURRENCY` at run start, alongside `RUN_START_UTC`, and carry it to the footer:

    1. `LOCAL` = the version in this file's own `> **Version.**` header.
    2. `REMOTE` = the same header, read from the maintainer repository's default branch:
       `gh api -H "Accept: application/vnd.github.raw" "repos/<owner>/<repo>/contents/JIRA-AI-Fix.md?ref=<default branch>"` — take the header line and parse the version out of it.
    3. Record exactly one: `CURRENT` · `STALE <LOCAL> -> <REMOTE>` · `AHEAD <LOCAL> > <REMOTE>` (a copy newer than the branch — the maintainer has not pushed) · `N/A (working copy)` (an unreleased authoring source is not meaningfully comparable) · `N/A (local build)` · `UNRESOLVED (<reason>)`.

    **Not every version string is a version.** A copy built from a working tree carries a deliberately unmistakable stamp — `2026.09.03.0930-local` from `install-jira-ai-fix-from-clone.ps1`, or a bare `yyyy.MM.dd` from a packager run that named none. Comparing either against a semantic version on the branch produces noise dressed as a finding (`STALE 2026.09.03.0930-local -> 1.3.0` says nothing true). A `LOCAL` carrying a `-local` suffix, or shaped as a date rather than a version, resolves to `N/A (local build)`: the developer built from a tree whose currency only they can speak to. Report it, compare nothing, and never call it stale.

    **Never a STOP, in any outcome** (same discipline as R-BUILD-RESOLVE). No `gh`, no access to a private repository, no network, a rate limit, a parse failure — all resolve to `UNRESOLVED (<reason>)`, which is recorded and the run continues normally. A developer without repository access simply never gets the check, and that is a disclosed gap rather than a broken run. A stale runbook still runs: staleness is reported, not enforced. Only a release the operator has explicitly marked mandatory may harden this, and that is a deliberate act, never this rule's default.

    **Where it surfaces — silent when current, loud when not.** `CURRENT` and `N/A` add nothing to the footer. Every other outcome appends to the first line, after the version: `· STALE — <REMOTE> is current` or `· currency UNRESOLVED (<reason>)`. The signal belongs in the Jira comment and not only in a console nobody re-reads, because the reader who needs it is the person deciding whether to trust the conclusion — and on SC-9232 that reader had no way to learn that three RCAs came from a runbook missing 32 of the rules that governed the ticket.

11. **The comment's own contract version rides on the same line (R-RCA-CONTRACT-STAMP, operator 2026-09-09).** Print `rca-contract <RCA_CONTRACT_VERSION>` between the runbook stamp and the model name, taking the value from the §6 block register. It is never omitted and never merged into the runbook version: those two answer different questions, and only this one tells a reader whether two comments were built to the same shape. Measured 2026-09-09 across 80 published RCAs: **42 carried no version of any kind**, so partitioning the published record by comment shape was impossible without matching on block labels — which had themselves been renamed. A run whose register differs from this file's (a hand-edited copy) prints the version it actually read, honestly, exactly as rule 9 requires of the runbook stamp.

12. **One separator, and it is built by code point (R-FOOTER-GRAMMAR, operator 2026-09-09).** The footer uses `·` (U+00B7) and nothing else — not a hyphen, not a full stop, not a pipe. Measured across the same 80 comments: **36 distinct footer strings**, four different separators, two mojibake renderings (`Â·`, `â€"`) and one `unknown — no manifest installed`. The mojibake is the same failure the telemetry script's own header warns about — Windows PowerShell 5.1 reads a UTF-8 source as ANSI — so any executable text that composes this footer stays ASCII-only and assembles the separator from its code point, exactly as `$DOT` already does. A footer that varies per run is not a footer; it is prose that happens to appear at the end.

- **R-NO-MODULE-CONFIG — this runbook is module-agnostic and holds no per-module configuration.** No table, column, procedure, GL module string, document type, or repository name for any module is hardcoded anywhere in it. `JIRA_PROJECT`, `MODULE`, `OBJECT_PREFIX`, `DOC_TYPES`, `MASTER_TABLE`/`DETAIL_TABLE`, `ROLLUP_RULE`, `GL_MODULE_NAME`, `DATAFIX_LOG_TABLE` and `CONSUMING_MODULES` are **derived on every run** from the ticket, the repository and the connected database per **Module resolution**, and each derivation is recorded in the run output. A derivation that cannot be completed is **skipped and disclosed** (or a STOP where the rule says so) — never quietly assumed. Every concrete Accounts Payable object, table, and `AP-#####` citation in this file is a labelled **worked example**: it records how a gate behaved on real evidence, and reading one as a default for another module is the specific error this rule exists to prevent.
- **R-DATAFIX-LOG — the data-fix audit trail is per module: `tbl<MODULE_PREFIX>DataFixLog` (§3.6 step 1a).** `MODULE_PREFIX` comes from the **affected tables**, not from the Jira project key — the project says where the symptom was reported, the tables say whose data is being changed. Discover what exists (`sys.tables LIKE 'tbl%DataFixLog'`) before deciding: an existing table for the module is used **exactly as it is** (never renamed, never duplicated — a parallel table splits the audit trail and blinds each half's idempotency guard); a module with none gets one created by the script, `IF NOT EXISTS`-guarded, outside the transaction, with columns copied from an existing module's log table on the same database. Nothing to copy from anywhere → STOP, because authoring the product's first data-fix log schema is an operator and Senior BA decision. Every reference in the script — create, guard, `@fileName` lookup, `INSERT` — names the resolved table (S16); one left pointing at the template's shipped name lets the fix apply twice in silence.
- **R-PROJECT-SCHEME — issue types, statuses and transitions are matched by MEANING against the project's own scheme, never by string.** i21 projects do not share one set of names. The type gate resolves a **category** (BUG / TECHNICAL_DEBT / DATA_FIX / out-of-scope) from the project's real types via `getJiraProjectIssueTypesMetadata`, preferring type **ids** over display names, and STOPs silently on a genuinely ambiguous category rather than guessing a `Feature`-shaped type into BUG. The status gate matches the meaning of `Open`/`Reopened`. §6.6 targets the project's "code written, not yet in review or test" status and **skips — keeping the label — when the workflow forbids the move or its transition screen demands fields this run must not invent** (worked example, AP: `Coding` 400s on empty `Components`/`Business Analyst`). Every reference-scheme name in this file (`Bug-QC`, `Coding`, `Ready to Test`, …) is the AP project's, quoted as illustration.
- **R-DATAFIX-DERIVED — §3.6 Standards 2–4 are invariants, not table names.** Standard 2 checks master/detail rollup integrity, Standard 3 application/settlement totals, Standard 4 GL balance for posted documents — each against the pair, formula and `strModuleName` **resolved from this run's own schema and data**, never mapped onto a table by name resemblance or carried over from another module. `N/A` is legitimate only where the module genuinely lacks the structure, stated with its reason; it is never shorthand for "did not check", and an unresolved `ROLLUP_RULE` on a table the fix writes to is a STOP. A Standard 4 check that matched **zero** `tblGLDetail` rows is a FAIL — a guessed `GL_MODULE_NAME` makes the balance assertion pass on an empty set (S15 requires every 2–4 verdict to show its derivation).

- **R-DATAFIX-STANDARDS — the published standards page is the source of record; §3.6 is its executable restatement.** The org-wide baseline lives on **Data Fix Standards (All Modules)** (page 705168896): Standards 1–4, fail-checks `S5`–`S17`, the dry-run-and-roll-back proof, the impact-analysis and QC-briefing contents, and the Senior BA gate. §3.6 states the same rules as gates a run can fail, under the **same numbering** — so a verdict this runbook posts (`Standard 3 — N/A`, `S16 FAIL`) resolves to the same rule for the Senior BA reading the iNet page. Two consequences: **(a)** where a module publishes a `<Module> Data Fix Addendum` under that page, its bindings and its own numbered standards (`AP-1`, `IC-1`, …) are read and applied **for the module `MODULE_PREFIX` names** — the tables the fix writes to, not the Jira project key — and an addendum may tighten the baseline but never weaken it; **(b)** where §3.6 and the page diverge, the page wins and §3.6 is the defect — report the divergence in the run output rather than resolving it silently in either direction. An addendum is a review aid, never the authority: every table, formula and module string is still derived per **Module resolution** against the connected database.
- JIRA_KEY is a required input parameter, validated against `[A-Z][A-Z0-9]+-\d+$`. It is used for the feature-branch name, the commit message, and the Jira comment only.
- **REPO_ROOT is the main folder where all i21 repositories reside (default `C:\i21Source`); REPO_PATH = `<REPO_ROOT>\<repo folder>` must be resolved and the repository loaded/cloned before any code analysis.** If the target repository (REPO) is not provided, AUTO-RESOLVE it from the Jira/module evidence + cross-repo code search under `<REPO_ROOT>`; ask the user only when that resolution stays ambiguous (never assume the opened workspace). If the repo is not present locally, clone it from Azure DevOps; if it is present, fetch (and checkout/pull TARGET_BRANCH when provided) so the code analysis in §1/§3 runs against real, current code. STOP if the repo cannot be cloned/loaded; a tree dirty with unrelated edits is **auto-stashed** (`git stash push -u -m "JIRA-AI auto-stash …"`, stash ref recorded in the run output, never popped/dropped automatically) and the run continues — only a failed stash is a STOP.
- **An auto-detected TARGET_BRANCH is provisional and is auto-aligned by §1.5 — Dev-first (operator 2026-08-06).** `EXPECTED_BRANCH` = the customer's dedicated Dev branch for the fix version when one exists (CUSTOMER_BRANCH_ALIASES, e.g. `22.1DevWaMa`, `24.2DevDnD`, `26.3DevCTRMFeatures_Sucden`), else mainline `<fixVersion>Dev`; the ONLY Prod branch we work is `24.2ProdSunshineGas`. Fallbacks: the Reported Build family as a branch, then build-stamp→branch resolution (token scoring against the `ls-remote "<version>*"` scan, cross-checked via ADO pipeline definition names — app build stamps are NOT ADO build numbers). JIRA_BUILD is harvested from all fields + description/comments/environment/screenshots, never the build field alone. Case-exact matching with the case-twin guard (`22.1ProdWaMa` ≠ `22.1ProdWama`); artifact-presence corroborates between surviving candidates. **The alias entry is per REPO, not just per casing** — the same customer's branch can carry a different name in each repo (Walter Matter: `22.1DevWaMa` in the AP repo, `22.1ProdDevWaMa` in i21_sqlscripts, which has no `22.1DevWaMa` at all), and a `<ver>ProdDev<Customer>` branch is a development branch that rule 3 does not restrict. Before escalating an "artifact only on a forbidden Prod branch" conflict, scan EVERY branch in the fresh ls-remote list, not only those whose name contains `Dev` (corrected 2026-08-12 — the former `uspAPClearingDetailsWAMA.sql` example was a false conflict). Only an underivable base is a STOP. Never adopt a leftover checked-out branch as the base without §1.5 clearance, and never create the target branch.
- **§1.6 feasibility gate runs before any implementation.** ALREADY-RESOLVED now requires the LATEST QA evidence to pass AND the fix content to still be present on the branch (revert detection by CONTENT diff, never commit-grep — ref AP-22099); a `Reopened` issue is never ALREADY-RESOLVED. Reopened-with-merged-PR runs the **Step 0.5 fix-delivery check** (was the fix in the tester's build? if not → ONE informational comment, NO PR, no re-implementation — ref AP-24412). ALL distinct requirements on the ticket (description + comments) are enumerated and analyzed; cross-team routing comments are judged on evidence (ref AP-24801). Third-party analyzer comments are last-resort input — JIRA-AI analyzes independently (ref AP-24683). Data/environment-dependent symptoms split into `DB_REQUIRED-ACTIONABLE` (DB reachable from ticket/sibling/registry → §1.7 immediately, no request) vs `DB_REQUIRED-BLOCKED` (ONE info request per customer cohort); insufficient evidence is `INFO_REQUIRED` → ONE deduped **INFORMATION REQUEST** comment (+ `JIRA-AI-NeedInfo` label, additively) and STOP; unfixable-here is `CANNOT-FIX` → ONE details+recommendation comment (§6.5), never a silent skip. Never post duplicate info requests; never claim a root cause that was neither statically proven nor reproduced on a restored DB.
- **§1.7 DB restore:** all SQL Server parameters come from the `sqlServer` section of `%USERPROFILE%\.jira-ai-runbook-config.json` (never in a repo; secrets stay in that file or env vars only). Check the `knownServers` registry FIRST when the JIRA says the DB was already restored on a server — matched by name/alias only, never a guessed connection; when the SQL port is unreachable, fall back to the entry's `ssh` block (key-based; tunnel preferred, remote `sqlcmd` fallback; transport recorded in the run output) before declaring the server unreachable; shared-server DBs are used for reproduction only (no safety-script assumption, no §3.5 update/rollback there). Otherwise restore locally per JIRA (`i21_<JIRA>_<CUSTOMER>`), post-restore safety script MUST neutralize outbound integrations before any test, `liquibase update` aligns it to the branch, and the BEFORE/AFTER reproduction pair is the required proof for DB-dependent root causes.
- **Optional configurations are accuracy boosters, never guessed around:** at run start check the ONE consolidated `%USERPROFILE%\.jira-ai-runbook-config.json` — sections `atlassian` (attachment downloads; falls back to `~/.atlassian-token`/env), `sqlServer` (+ its `knownServers` registry), and `helpdesk` (HDTN session cookie — per user, refreshed via browser login when expired); report missing/empty sections in the run output and disclose every capability skipped because of a gap (RCA line or Information Request) — see **Optional configurations** at the top of this runbook.
- **No PR, no propagation.** This runbook stops after pushing `<TARGET_BRANCH>_<JIRA>` and posting the RCA / Acceptance Verification comment. It does not create or complete a Pull Request and does not fan out across branches.
- Parent Jira issue type must be one of `Bug`, `Bug-QC`, `Bug-UAP`, `Bug-Ongoing UAP`, `Technical Debt`, `Performance`, or `Data Fix`; STOP if the issue type is missing, inaccessible, or outside this list. (`Performance` → TECHNICAL_DEBT; `Data Fix` → DATA_FIX; everything else → BUG.) **`Feature`, `Gap`, `Paid`, `Suggestion` and `Config` are explicitly OUT OF SCOPE (operator 2026-08-11)** — there is no `FEATURE` category in this runbook; each is a silent STOP reported as `OUT-OF-TYPE (<issue type>)`, with no comment and no label.
- **`Data Fix` issues ALWAYS require the database (R-DATAFIX-DB)** — §1.6 can never classify one as `STATIC`; it is `DB_REQUIRED-ACTIONABLE` (→ §1.7 → §3.6) or `DB_REQUIRED-BLOCKED` (→ ONE information request → STOP). The delivery path is **§3.6**, not §3/§4/§5: author from the **JIRA Datafix Template** (page 434602044) keeping its log/idempotency/TRY-CATCH machinery intact, apply **Standards 1–4** of **Data Fix Standards (All Modules)** (page 705168896) plus the additional fail-checks **S5–S17** (no unbounded DML, single scope resolution, no schema DDL, no mass-destructive constructs, pre-image capture, posted-record guard, build stamp populated, ships with `@ysnCommit = 0`, §J binding, no credentials, every 2–4 verdict derived, log table resolved, not a sync-owned value) and whatever the module's own addendum adds, **test the fix on the restored DB inside the template's transaction and let it ROLL BACK** — then verify the rollback actually took (analysis query still reports the same rows, no `<DATAFIX_LOG_TABLE>` entry) — and deliver the script + impact analysis + QC test pointers on the JIRA. The DB is always left unfixed. Senior BA sign-off is the gate; this runbook never self-approves a data fix, and creates no branch, commit, or PR for one.
- **An HD (HDTN) ticket is OPTIONAL and never required.** It is read for additional information only — above all the **`Database Copy` tab / restore comment / restore screenshot** naming the server + database IT restored the copy onto, which feeds §1.7 step 0. No HDTN referenced → skip silently. Cookie missing/expired → record the gap and CONTINUE on the JIRA's own evidence (operator 2026-08-07; supersedes the former STOP); never ask a reporter for an HD ticket.
- **R-NOFIX-COMMENT — every run leaves the right comment, and only one.** The §6 RCA is reserved for a **successful fix** (branch pushed, or data fix delivered). Needs-information and needs-database → INFORMATION REQUEST + `JIRA-AI-NeedInfo`; unfixable-here → CANNOT-FIX (§6.5 A); fix-not-in-tested-build → the Step 0.5 informational comment; analyzed-but-not-fixed for any other reason (§3 FAIL, restore failure, `DB-VERSION-MISMATCH`, unresolvable branch) → the **§6.5 D TRIAGE comment** + `JIRA-AI-Triaged`. Only `ALREADY-RESOLVED` and the out-of-type/out-of-status gates post nothing. Dedupe applies to all of them.
- **R-QUEUE-LABEL-STATE — batch/scheduled passes select by label, never by status (operator 2026-08-11).** Because no ledger is written, the §6.6 outcome labels are the durable state: the selector JQL excludes `JIRA-AI-NeedInfo` / `JIRA-AI-CannotFix` / `JIRA-AI-Triaged` / `JIRA-AI-Fixed` / `JIRA-AI-DataFix`, and MUST include `labels IS EMPTY OR …` (Jira's `NOT IN` drops unlabeled issues — the never-processed ones). Never filter on `JIRA-AI-RegressionFlag` / `JIRA-AI-FixPropagated` (ref AP-24523). Re-entry is evidence-driven (label cleared, or a comment newer than the runbook's own), and the §1.6 dedupe guard — not the filter — decides whether to comment again. An explicit `JIRA_KEY` always overrides the filter. Unattended runs must terminate every operator-decision STOP through the §6.5 D triage comment + `JIRA-AI-Triaged`, or the next pass re-derives the same stall forever. Batch statistics are then JQL label counts, not a tracking file.
- **R-DB-SLOT-LIMIT — at most TWO locally restored databases at once (operator 2026-08-11).** Local restores are a pool of 2 slots, keyed **per cohort** (one restore serves the whole customer/environment cohort); a `knownServers` database occupies no slot. A third DB_REQUIRED cohort is parked `DB_QUEUED` — `FEASIBILITY` stays `DB_REQUIRED-ACTIONABLE`, and **no comment and no label** is posted (a queued ticket is not a blocked one). Release order: completion check (every ticket in the cohort has its terminal comment — disk pressure never cuts an analysis short) → harvest all BEFORE/AFTER, §3.7 and §3.9 evidence into the run output → §3.5/§3.6 rollback already verified (**dropping the DB is not a substitute for the rollback proof**) → `SET SINGLE_USER WITH ROLLBACK IMMEDIATE` + `DROP DATABASE` → **KEEP the backup archive (R-DB-KEEP-ARCHIVE — the database is dropped, the archive is not)** → record `slot released` and the retained archive path. Never drop or delete anything this runbook did not restore. `STATIC` / `INFO_REQUIRED` / `CANNOT-FIX` tickets never wait on a slot.
- **R-DB-KEEP-ARCHIVE — drop databases, keep archives (operator 2026-08-11).** A slot is the **restored database alone**; the archive in `backupStageDir` occupies no slot and is never counted against the pool. After a restore is verified `ONLINE` (§1.7 step 3a), a raw `.bak` is **compressed to `.zip`, the archive verified, and only then the `.bak` deleted** — never the reverse order, because an unverified archive plus a deleted `.bak` is a lost database; an artifact that arrived already archived keeps its original archive and loses only the extracted `.bak`. A failed/non-`ONLINE` restore compacts nothing. The archive then survives the rollback, the slot release, and the run itself, so §1.7 step 1.3 (already-staged) makes a re-restore a local extract instead of a multi-gigabyte re-download — while still facing the step-0 acceptance gate and the step-2.6 version check, since a retained archive is a candidate and never an authority. The ONLY file this runbook may delete in `backupStageDir` is a loose `.bak` whose archive it just verified; genuine disk exhaustion is reported for operator cleanup, never resolved by deleting evidence.
- **R-DB-LEDGER-REUSE — reuse before restoring, and keep no records.** Exhaust §1.7 step 0 (ticket, siblings, HD `Database Copy` tab, live `sys.databases` sweep of the configured `knownServers`) before any download or restore. **No ledger, index, or DB log is ever written by this runbook** — reuse is rediscovered from live evidence each run. **Never publish local (Philippines/workstation) restore details** — server, database name, or path — in any Jira comment, RCA, PR, or Confluence page; those belong in the run output only. Only DBs on shared servers the team already references may be named.
- **R-DB-PROVENANCE — every terminal comment that cites database evidence identifies that database (ref AP-24877).** "No ledger" constrains what is *stored*, never what is *disclosed*: the run output dies with the session, so the comment is the only durable record of which copy was executed against. A shared `knownServers` DB is named as `<server> / <dbname>` + build — **required**, not merely permitted; a local restore is identified by its **acquisition source** only (which HDTN's `Database Copy` / attachment / link / registry sweep), never its server or database name. When the ticket lists more than one DB-bearing HDTN, say which one supplied the copy — or `not traceable to a listed HDTN`. Never a speculative `may satisfy HDTN-<n>`.
- **R-DB-CANDIDATE-SET — rank the candidates, and keep the losers (ref AP-24877).** Gate **every** step-0 candidate before selecting one; rank by reported-artifact-present → newest → shared-over-local → most recently named HDTN. A rejected candidate is **retained, not discarded**: the set is a dated snapshot series, and the older copies are where the evidence the newest one lost still lives — purged rows, and above all the value the customer's own workaround overwrote. `NOT-REPRODUCED-TXN-ABSENT` may not be recorded until the whole set has been checked; a dated pair bounds §3.8 `DEFECT_ORIGIN` and separates §3.11's defect-broken rows from hand-corrected ones. Consulting a shared secondary is free; a secondary needing a local restore is restored only for a named question, through the slot pool.
- **DB version check (§1.7 step 2.6):** every database this runbook uses is checked with `SELECT TOP 1 strVersionNo FROM tblSMBuildNumber ORDER BY intVersionID DESC` and must match `TARGET_VERSION` on **main.major only** (`24.2` vs `24.2` — build/revision are expected to differ and are never compared). Mismatch → STOP with `DB-VERSION-MISMATCH` and the §6.5 D triage comment. Not determinable → continue read-only, but a hard STOP for `DATA_FIX`.
- **§3.7 regression impact (R-REGRESSION-IMPACT) — repo/DB layer only, NO app environment.** Runs after §3 whenever the CHANGESET alters a SQL logic object or a code artifact with callers (skipped for a data fix — §3.6 has its own collateral checks). **Tier 1 always runs, no DB needed:** build the caller graph (repo-wide `git grep` across every repo under `<REPO_ROOT>`, plus `sys.sql_expression_dependencies` when a DB is present) and apply the **fail-closed contract gate** — a changed parameter list, result-set shape, or column type with any dependent outside the CHANGESET is a **§3 FAIL** unless explicitly waived with the dependents named (this is the §J bind-error class one level up). **Tier 2 runs when a §1.7 DB is available:** build a `GOLDEN_SET` of the reported document(s) plus ~20 sampled keys that are NOT the defect (stratified by company/date/posted state), capture BEFORE/AFTER with deterministic ordering — views/functions by SELECT, procedures via the **§3.6 transaction harness** (`BEGIN TRAN` → EXEC → capture deltas → `ROLLBACK`, rollback verified, DB never left mutated) — and diff: only the reported defect class may differ. Unexpected deltas are a **review-blocking finding** (RCA + `JIRA-AI-RegressionFlag` + a `regression-flag:` marker on the §6.7 handoff so the PR is not auto-completed), **not** a §3 FAIL. Volatile columns (dates, identities, `NEWID()`, rowversion) are excluded for determinism and **every exclusion is disclosed**. Never run tier 2 against a shared `knownServers` DB (restore a local copy or disclose). No DB → tier 2 skipped without stopping, disclosed in the RCA. **Sampling is evidence, never proof — a clean differential must never be reported as "no regression".** UI/render/end-to-end behaviour is explicitly out of scope and stays with §1.7a.
- **§3.9 property & invariant test (R-PROPERTY-TEST) — proves the fix cannot drift.** Runs whenever the CHANGESET alters a **pure, deterministic** artifact (scalar/table function, converter, rounding/precision helper, formatter, parser); skipped with a disclosure for stateful procedures (§3.7 tier 2 covers those) and for changes with no computable contract. Deploy the **deployed pre-fix body and the working-tree body side by side under distinct names on a THROWAWAY LOCAL database** — never against the reported/shared/customer DB, and never by `ALTER`ing the real object — asserting first that the two bodies actually differ (a test comparing a function with itself passes and proves nothing); drop the scratch DB after. Build the grid from the **code's own decision boundaries** (thresholds, bucket edges, type precision/scale limits, values just under/over each carry point, every sign combination, the special-cased degenerates `0`/`1`/`-1`/NULL) crossed with real values from the §1.7 DB — a mechanism-derived grid finds what arbitrary numbers will not. Assert the defect's own invariant plus the object's claimed contract, and **always** V1 **new failures ⊆ old failures**, V2 **no drift** (`NEW == OLD` wherever OLD was already correct), V3 **accuracy never worse**, V4 **the oracle is computed OUTSIDE the system under test** (arbitrary precision in the harness — never by the engine being tested), V5 **every residual failure is characterised** (class, cause, reachability). V1–V4 violations are a **§3 FAIL**; a *pre-existing* residual is a finding to disclose, **never a licence to widen the CHANGESET** — name it in the RCA and leave any follow-up ticket to the operator. Report the counts on the mandatory RCA **Property test** line. (Ref AP-22786: 1,030 inputs / 10,300 evaluations reduced sign-asymmetry 129 → 32 with new ⊆ old, 0 unwanted drift and 0 accuracy regressions — and surfaced an unrelated pre-existing asymmetry in the `= 1` early-return shortcut that the fix deliberately does not touch.)
- **§3.8 defect lineage & fix-coverage map (R-DEFECT-LINEAGE) — who introduced it, and who already fixed it.** Runs after §3.7 whenever the root cause reduces to a **greppable construct** (skipped for data fixes and for causes that cannot be reduced to a searchable string; never a STOP). Pickaxe the *defective* construct (`git log -S "<construct>" origin/<TARGET_BRANCH> -- <path>`, `--follow` for renames) to name `DEFECT_ORIGIN` — the introducing commit + its JIRA — and confirm it with `git merge-base --is-ancestor`, never by assumption. Then build `FIX_COVERAGE` across the active lines, **searching BOTH repos** (`i21_sqlscripts` < 24.1, `i21_Liquibase` ≥ 24.1 — R-LB-24.1-TARGET; a one-repo sweep reports a false gap) and classifying by **CONTENT**, never by `git log --grep` (a revert matches the grep too). **A line is `FIXED` only when a counterexample that genuinely satisfies the failure condition passes on it** — an existing-looking fix is `PARTIAL` until proven, and a poorly-chosen example that misses the condition will falsely clear a still-broken line (ref AP-22786: `−999999.5` wrongly cleared 26.x/27.1; `−999999.70166666670 × 0.799` still reproduces there). When coverage is not uniform, the RCA MUST carry the vintage → observed-behaviour table so a reviewer testing on a different database does not conclude "no defect". `COVERAGE_GAPS` are **reported only** — named in the RCA and marked on the §6.7 handoff (`| coverage-gap: …`); this runbook never widens the CHANGESET to another line, never propagates, and never files a ticket in another team's project. **§3.8 step 5 is the confirmation pass for the §2.6 ownership verdict** — it re-reads the change history this section just built and returns a disagreement to §2.6 as a run defect, never as a footnote.
- **§2.6 object ownership (R-OBJECT-OWNERSHIP) — this runbook does not modify what another module owns (operator 2026-08-28; **partly superseded by the tier split of operator 2026-08-31 below** — where the two disagree, the tier split wins).** Runs **before §3 edits anything**, on `CANDIDATE_CHANGESET`, from four static signals: the file's location (module-owned vs shared path), the caller distribution by observed object prefix, the JIRA keys on **every** prior commit to the file (a file only ever changed under one project's keys belongs to that project), and which object actually writes the bad rows. `FOREIGN` needs **two or more** signals naming the same other project with at least one of them callers-or-history — location alone never carries it; absent evidence is not a foreign signal (a file this JIRA creates is `OWNED`); conflicting signals are `UNDETERMINED` and are **held exactly like `FOREIGN`, fail-closed on the write**. A hold restricts **writes, never understanding**: reproduction, root cause, origin trace, regression impact, property test and lineage all still run, and the corrected body is authored **outside the repository** into `<JIRA>Patch.sql` (§3.10, mandatory there, executed and proven like any other patch). Nothing under `REPO_PATH` is modified — §3 proves it with a clean `git status --porcelain` for every held path, `git add -A` is forbidden for the run, §4/§5 are skipped for held artifacts, an inseparable mixed changeset holds whole, and §6.7 emits `ROUTING-REQUIRED`, never `READY-FOR-PR`. **R-NO-REHOME: the ticket does not move** — no project change, no reassignment, no transition, no ticket raised in another project; the RCA states the owner, the evidence counts, the three routing options and that `<JIRA>` was left where it is. Ownership is never a route back to `CANNOT-FIX` and never a substitute for the analysis (ref AP-22786: `fnMultiply` — shared path, 214 callers of which 143 IC / 9 AP, every prior change an IC ticket, on an `AP-` ticket).
- **R-GATE-NOT-SELF-EXCUSED — a gate may not be switched off by the run's own choice of fix (operator 2026-08-31; ref AP-24960).** §1.7b, §3.4 Proof 1 and §3.11 phrase their triggers around *the implicated path* / *the symptom* / *the defect*, and a single run skipped all three by substituting **the changeset it had selected**. The trigger is evaluated against the **observed evidence**, never against the changeset; `not run` / `N/A` is never justified by "the fix I chose does not touch that layer"; and **any stored value in the EVIDENCE_SET the run cannot attribute to a writer arms all three**. On AP-24960 the three skips between them left a stale `dblAmountDue` — the actual root cause — filed as a side-note under *Related defects found*.
- **R-DATA-CAUSE — the issue type never rules out a data cause (§1.6 Step 2c, operator 2026-08-31).** `ISSUE_CATEGORY` records how a ticket was filed, not what is wrong with it. Every run resolves both directions whatever the type — **upstream**, is a stored value raising the symptom (trace it under §3.4, never file it as a curiosity); **downstream**, did the program write rows already wrong (§3.11) — and records `DATA_CAUSE = none | present: <value, rows, count> | undetermined: <why>` in the run output and the RCA. `none` is reportable only after the check ran.
- **R-STALE-DATA-WRITERS — a stale stored value is not a stale deployment until the writers have been enumerated (§1.7d, dev review 2026-08-30; ref AP-24915).** `DEPLOYED-STALE` is conclusive on an object **body** — nothing writes one but a deployment — and ambiguous on a data **row**, which has many: *never applied* and *applied then overwritten* produce the identical observation, and the stale route exits before §3, so §3.4 Proof 1 — the only gate that asks *what else writes this value* — never runs. Sweep every writer of the table and column **organization-wide** (a capped grep is not an absence), classify each `ONE-TIME` or `RECURRING` — `*CommitListing` / `*UpdateStageListing` / `*Sync*` / `*Seed*` and every `runOnChange` object are standing suspects on configuration tables — and read the recurring one's **input**: an input still carrying the stale value proves *overwritten* offline, with no database at all. `RE-ASSERTED` makes the one-time correction **structurally transient**, so it may not be offered as the fix in any form (patch, data-channel re-run, or data fix); the durable route is the writer's input, an in-writer exemption, or the consumers' binding, and that artifact goes through §2.6 because the writer is usually another module's — whose rules this run does not know and must not guess.
- **R-CHANGELOG-TABLE-CONFIGURED — never test Liquibase execution against the default table name (§1.7d step 4).** i21 sets `databaseChangeLogTableName = tblSMLiquibaseChangeLog` in the Liquibase repository's `liquibase.properties`, so a query against `DATABASECHANGELOG` returns *no such table* on every i21 database, healthy or not. Resolve the name from the repository before making any claim about what has or has not executed. Reported as “Liquibase has never run here”, the default-name miss is a **fabricated finding** — on AP-24915 it was the evidence a wrong recommendation rested on.
- **R-ORIGIN-COMPARAND — “the predicate does not match the data” is a value defect on the DATA side (§3.4 Proof 1, dev review 2026-08-31; ref AP-24889).** A join, filter, `IN` list or lookup key compares a literal we own against a column somebody **wrote**. `ORIGIN TRACE = N/A — read-path defect, no stored value is wrong` excuses the proof with the wrong test: *nothing is wrong at rest* is not *nothing wrote this*, and `w0` is the writer of the compared column. Enumerate that column's writers exactly as §1.7d does for a stale value — the writer settles who owns the remedy, whether the consumer-side change is a fix or a mask, and which lines actually carry the symptom.
- **R-WRITER-OWNERSHIP and R-HANDOFF-DECISION — ownership follows the cause, not only the edit (§2.6 step 3a, §6.7).** §2.6 read `CANDIDATE_CHANGESET` alone, so a consumer-side fix to an object we own cleared it `OWNED` on a ticket whose cause was another module's. `ROOT_CAUSE_WRITER` is now evaluated on the same four signals even though nothing edits it; a `FOREIGN-*` or `UNDETERMINED` writer yields **`DIRECTION-UNDECIDED`**, which holds neither the write nor the branch — it holds the **claim**. The RCA then states the competing remedies (correct or exempt the writer at source, versus move every consumer bound to the old value, naming all of them) and self-selects neither, and the §6.7 handoff carries `decision-required` so the PR is not raised until the owning module answers. R-NO-REHOME is unchanged: no ticket moves. Ref AP-24889 — an AP view fix shipped as settled while the naming standard behind it was an open SM decision, still open on its sibling AP-24915.
- **R-PRIOR-ART-ROW — once the cause is a configuration-row value, re-sweep prior art on the ROW (§1.7d step 7).** The §1.6 Step 0.1 sweep runs early and is keyed on this ticket's wording, component and object, so it cannot reach a sibling whose screen, summary and implicated file all differ while the table, the row family and the writer are identical. Re-key it on the table name, the namespace, the stale and corrected literals and the writer's name, over Jira text search and the repositories. Ref AP-24889/AP-24915 — one ticket apart, same cohort and build, the writer already named in the sibling's dev review, and the sweep missed it.
- **R-COVERAGE-WRITER-CONDITIONED — a data-dependent symptom is graded `predicate present × writer present` (§3.8 step 2 item 4).** Grading a line `DEFECT` because it carries the defective construct overstates coverage when a writer must also be present for the symptom to appear — and the propagation decision is made on that grade. One `git grep` for the writer per line settles it. Ref AP-24889 — 26.3Prod carries the sync and 26.3Dev does not, so two branches of one release line grade differently.
- **R-DATAFIX-DELIVERED — when a data issue is proven, the script ships on the ticket in hand (§3.11 → §3.6, operator 2026-08-31, superseding the withhold rule).** §3.6 is no longer gated on `ISSUE_CATEGORY = DATA_FIX`: its real PRE-REQs are a usable database, a matching build and the policy sources, all satisfiable on a `Bug`. A sweep that finds rows goes on to author, dry-run and roll back the script, with impact analysis and QC pointers. **Preserved and non-negotiable:** `@ysnCommit = 0`, log/idempotency/TRY-CATCH machinery intact, database left unfixed, shared-server guard, and **Senior BA sign-off as the gate** — delivering is not approving, and this runbook still applies nothing and files no ticket. Ref AP-24960: a five-line `UPDATE` was withheld as *“not run”* and hand-rebuilt by the developer four and a half hours later.
- **R-ERROR-TEXT-NARROWS — an exact error-text search narrows, it never certifies (§1.6 Step 2a, operator 2026-08-31).** One hit is evidence of one *wording*, not one *producer*: message strings drift by a word between producers of the same invariant. Before `candidates = 1`, run a second pass on the **predicate** — the comparison, the invariant, the field — not on the message. The error-class table gains a **UI / client-side validation** row: controller validator · `Ext.data.validator` in the model's `validators:` block · shared-package validator with a variant message · server-side API validation; for ExtJS the model's `validators:` block for the implicated field is read before any `candidates = 1` is recorded. Ref AP-24960 — *“… payment schedules total.”* vs *“… payment schedules.”*, one word apart, and the delivered fix guarded one of the two.
- **Prior art gets three more reaches (§1.6 Step 0.1 / §1 step 7b, operator 2026-08-31).** **R-PRIOR-ART-DATAFIXLOG** — a fourth mandatory search: the restored database's own datafix log, the one prior-art source that is customer-, build- and environment-specific, one query (ref AP-24960, which held AP-24868 four days ahead of the report and was never read). **R-PRIOR-ART-CONSUMERS** — the object-history sweep covers the files that CONSUME the implicated object, not only the object (ref AP-24914: `VoucherViewModel.js`'s own history carried AP-13728 all along). **R-PRIOR-ART-NO-EXPIRY** — the 12-month window does not apply to component- or screen-scoped prior art; a same-screen fix never ages out (ref AP-24914: AP-13793, January 2024).
- **R-ORIGIN-BINDING and R-ORIGIN-DELETED-CHILD — two blind spots in the origin trace (§3.4 Proof 1, operator 2026-08-31).** Proof 1 now fires on a value defect **anywhere in the causal chain the analysis establishes**, not only on a reported one. **A binding is a value:** when the symptom is *“the consumer called E and E failed”*, `w0` is the statement that CHOSE E, not E's body — and a `FOREIGN-*` verdict on the fix artifact for a symptom on our own screen forces a re-check before authoring (ref AP-24914). **“No surviving child row” is not “no event”:** before `WRITER-UNIDENTIFIED`, run the identity gap on the child table, script the reversal and test whether it is `INNER JOIN`-dependent on those rows, and check the arithmetic identity (ref AP-24960: 18,763.69 − 17,701.19 = 1,062.50, `uspAPUpdateBillPayment @post = 1`, 717 deleted detail identities).
- **R-ALIGN-CONSUMERS and R-LINEAGE-RELOCATION — look where the choice was made, and follow the file when it moves (§2.5 / §3.8, operator 2026-08-31).** The sibling sweep diffs the **consumers** on symptom-free lines, not only the object being fixed — a symptom-free line is often symptom-free because of what its viewmodel binds. And `git log -S` walks simplified history and stops silently at a moved path: pickaxe with **`--full-history` across both path generations**, and treat a relocation whose content is not carried verbatim as a **candidate introducing change** whose diff must be read. Ref AP-24914 — the regression lived inside the AP-22443 / AP-22608 relocation and stayed invisible through two prior RCAs.
- **R-JS-CLIENT-TREE hoisted into §1 (§1.6 Step 2 item 0, operator 2026-08-31).** `SERVED_TREE` is resolved **before the first client-side search**, and every search after it is `git grep origin/<TARGET_BRANCH> -- <SERVED_TREE>/` rather than a filesystem grep. §3.4a governs reading as well as writing but was filed under §3, so §1 was searching repo-wide with no tree constraint — returning the dead tree, gitignored `build/` bundles, and line numbers pinned to whatever branch the working copy sat on. §3.4a remains the placement check on the CHANGESET; only the determination moved.
- **§2.6 splits into two tiers, and never prompts (operator 2026-08-31; ref AP-24892, AP-24914).** A new **signal 0 — the repository boundary** — is dispositive on its own, unlike a shared path. `FOREIGN-SHARED` (**Tier 1**, the object is in our repo and this JIRA's own project is among its consumers): fix, branch, push as normal, with **the owning team's reviewer REQUIRED before any PR is raised**, carried on the handoff by **R-HANDOFF-OWNERSHIP** (`| owner: <project> (FOREIGN-SHARED) — <project> review REQUIRED before this PR is raised`) — the one §6.7 marker that is a precondition rather than an annotation. `FOREIGN-EXTERNAL` (**Tier 2**, another project's repository) and `UNDETERMINED`: **stop at the diagnosis** — full RCA and evidence naming the owning project, artifact, lines and introducing commit, and **no fix authored at all**, no working-tree edit and no `<JIRA>Patch.sql` (§3.10 does not run for a held artifact). **R-NO-OWNERSHIP-PROMPT:** the gate self-decides and records; a run never asks the operator whether to branch, commit, push or hand off — in a scheduled run or an interactive one — and no pull request is created by this runbook in any branch of the gate.
- **§6 gains a COMBINED form, and the DB name must be literal (operator 2026-08-31).** A ticket carrying **both** a code fix and a data fix had no form: CODE_FIX has nowhere for the script, DATA_FIX declares §3.10/§3.11 `N/A`. The **COMBINED form** is the CODE_FIX form plus the DATA_FIX delivery blocks after **Affected data**, whose wording becomes *“the code fix does not repair these rows; the data fix delivered below does — pending Senior BA sign-off”*; the *never a second sweep* prohibition is lifted there because §3.11's sweep and §3.6 Standard 1's analysis query are the same query. **R-DB-PROVENANCE-LITERAL:** the `<dbname>` on the **Database** line is the literal value from `SELECT name FROM sys.databases` on the named server — copied, never paraphrased (ref AP-24960, which cited a database name that does not exist on the server it named).
- **§2.4 premise gate (R-PREMISE) — the symptom occurring is not the symptom being wrong.** §1.8 proves the behaviour happens; nothing used to ask whether it *should*. Acceptance criteria are an **instruction, not evidence**, so a run that treats them as evidence delivers a faithful fix for a defect that does not exist and every downstream gate passes it — each checks that the fix is correct, none that a fix was needed. Ref an RK ticket delivered to acceptance and overturned at dev review with *"the reporter's issue is not an issue"*. Classify first: a `SELF-EVIDENT` symptom (exception, failed invariant, corruption, blank render, contradiction of the ticket's own evidence) is its own authority and the gate exits in one line; only a `PREMISE-DEPENDENT` one (a value, label, order, default, rounding, visibility, timing) walks the **authority ladder** — **A1** a specification page baselined *on this branch* (iNet, one Confluence space per module, cited as page id **and** version), **A2** a test asserting the current output, **A3** an invariant the requested change would break, **A4** deliberateness (delegates to §3.8 step 1 on a *different input* — the construct producing the disputed behaviour — where a found origin means a **decision**, not a regression, and only when the originating ticket's own criteria asked for it), **A5** consistency with peer objects. **A1–A3 may refute; A4–A5 may only contest** — "someone decided this in 2023" raises the burden, it does not settle whether the decision was right. `REFUTED`/`CONTESTED` are terminal *before* any branch, via the §6.5 E premise challenge + `JIRA-AI-PremiseChallenged`; `UNVERIFIED` is conditioned on blast radius from §3.7 tier 1 — contained proceeds with the R-PREMISE-ANCHOR banner opening the RCA, wide stops. Absence is never a signal (R-PREMISE-ABSENCE): an unbaselined page, an unwritten specification or an inconclusive pickaxe is **not** evidence the reporter is right, and the relocation trap makes a false "no origin found" fail in exactly the direction the gate exists to prevent (R-PREMISE-LINEAGE). Read-only throughout (R-PREMISE-READ-ONLY): the gate cites iNet pages, it never edits one. Measured 2026-09-08 — `1` page of `3,710` in the `RM` space carries a baseline table, so *pointer* is today's expected outcome and *authority* the exception. **Two rules were added by dry-running the gate against RM-13191, which it would otherwise have missed:** the `SELF-EVIDENT` invariant clause admits only an identity **something other than the ticket** requires (every premise-dependent ticket asserts one, so accepting the ticket's own claim skips the gate entirely); and **R-PREMISE-MAGNITUDE** — where the disputed quantity is derived as `price × quantity`, divide it back out and read the per-unit figure against its stored unit before trusting either side, since a unit-scale error yields an output that is arithmetically perfect and physically absurd (≈3,909 USD/KG on a 12,000 KG coffee lot: a per-tonne price in a per-kilogram field). Its companion at §2.7 is **R-REMEDY-TAUTOLOGY** — a remedy that makes the criterion true by construction has made it unfalsifiable, and re-enters this gate as evidence rather than being selected.
- **§2.5 sibling-line alignment (R-ALIGN-TO-SIBLING) — is the fix a port, and did anyone check? (ref AP-24880).** Runs **before §3 authors anything**, for every changed logic object (SP/function/view/trigger) or code artifact that also exists on another active line; skipped with a disclosure for `DATA_FIX` and for a single-line object. Enumerate the active lines carrying the object from a fresh `ls-remote` scan across **BOTH repos** (R-LB-24.1-TARGET), then **diff the object BODY** (`git diff origin/<TARGET_BRANCH>:<path> origin/<sibling>:<path>`, Liquibase wrapper lines ignored) — not the defective construct: pickaxing the construct answers "was this defect fixed there", which is the wrong question when the sibling is merely **more complete**. Classify each sibling `IDENTICAL` / `SIBLING-AHEAD` / `TARGET-AHEAD` / `DIVERGED`, read the ahead hunks against the pinned **mechanism**, and record exactly one `ALIGN_VERDICT`: `PORT-AVAILABLE` (take the sibling body as the starting point; `PORT_SOURCE` named in the RCA), `NO-SIBLING-BEHAVIOUR`, `NOVEL-JUSTIFIED` (**allowed, but only with a written justification in the RCA** naming what the sibling does that this deliberately does not — the AP-24880 failure mode is this verdict reached silently), `N/A`, or a disclosed `NOT-RUN`. **Fail-closed on the sweep, never on the verdict:** reaching §3 with no verdict for a changed logic object is a §3 FAIL. A port is **not** self-certifying — §3.4, §3.7, §3.9, §3.10 and §3.11 all still run on the ported body, and a debit/credit-shaped acceptance criterion is proven **per account, not on the batch total** (a balanced batch is reachable by a wrong distribution). This gate exists because §1.6 Step 0.1 and §3.8 `FIX_COVERAGE` are both scoped to *this defect* and §3.8 runs after the fix is authored besides, so neither fires when a branch is simply behind (ref AP-24880: `fnAPGetVoucherDetailDebitEntry` on the WaMa/CTRM line already carried the load-shipment-cost branch the Sucden 26.3 line never received; the run's correctly-diagnosed but invented fix was rejected on review and replaced by the port).
- **§2.5 step 4 port-dependency check (R-PORT-DEPS) — a port drags its prerequisites with it.** Runs for **every ported hunk regardless of `ISSUE_CATEGORY`** — the runbook's only other dependency check sits in the §3 TECHNICAL DEBT GATE and so did not run for AP-24880, a `BUG`. Enumerate every JIRA key named in the sibling's `--comment:` line and inside the ported region, plus every object/column/UDT/table/parameter/config key/changeset the ported statements touch; verify each prerequisite on `TARGET_BRANCH` **by CONTENT** (§J exact binding for identifiers; `git log -S` on the construct a referenced JIRA introduced, **never `--grep`** — a revert matches the grep too). Per smallest separable portion: all prerequisites present → **PORT**; missing and separable → **STRIP** and record it; missing and **not** separable → **STOP** as a blocked port naming the missing prerequisite — never ship half a feature to make a voucher balance, and never hand-write a local substitute for the missing prerequisite (that is a novel fix wearing a port's clothes and it goes through `NOVEL-JUSTIFIED` or not at all). `PORT_EXCLUSIONS` is **mandatory in the RCA in both directions** — an unrecorded strip reads as an oversight at review, an unrecorded non-strip means a half-feature shipped under this JIRA's key (ref AP-24880: the AP-20381 portion was correctly stripped because its companion fixes are not on the Sucden 26.3 line, with nothing in the runbook then guiding or recording the call).
- **R-COMMENT-MENTIONS (operator 2026-08-08):** every comment this runbook posts @-mentions the issue's **current assignee** and, when §3.8 named related JIRAs, **their assignees and commit authors**. Use `contentFormat: adf` with real `mention` nodes — a markdown `@Name` is inert text that notifies nobody. Resolve ids with `lookupJiraAccountId`; state plainly when one cannot be resolved.
- **APP_ENV / §1.7a runtime reproduction (R-RUNTIME-REPRO):** OPTIONAL input, **never provisioned by this runbook** — no i21 app environment is built, deployed, or configured here. When provided, it is used only to reproduce UI/render/HTTP symptoms via Playwright (console + network + screenshot capture, optionally correlated with an Extended Events capture). Its version must match `TARGET_VERSION` and `DB_BUILD_VERSION` on **main.major**; on mismatch the runtime evidence is **discarded** and the mismatch reported. Read-only on any environment that is not a controlled restore. Never a STOP; when absent and the symptom is UI-level, disclose `runtime reproduction NOT run — no APP_ENV provided`. **Session handling:** one headed login, then headless replay from a saved Playwright `storageState` held outside every repo; a login redirect is the expiry signal and triggers a fresh headed capture, never a retry or a guessed credential. **Resolution and memory are §1.6c's** — the parameter is only the first of three sources, and what a run learns about an environment is written back to the `appEnv` registry. **Concurrency (R-BROWSER-ISOLATION, operator 2026-09-08):** every run drives a browser **it launched itself** — never a shared persistent profile, never one this run did not start — so two JIRAs worked at once are two processes and both work. A second run that finds the same `<envKey>` already leased does not log in beside it: it records `app layer deferred — <envKey> held by <JIRA>`, reports that the app layer is **queued, not skipped**, continues on every other layer, and runs §1.7a once the holder releases. The saved session file, the `nav\<envKey>.json` merge and the `appEnv` write-back are write-exclusive under the same lease (`%USERPROFILE%\.jira-ai-harness\locks\`); a lock that cannot be taken is recorded, never forced. Never a STOP.
- **§1.6c app-environment registry (R-APP-ENV-REGISTRY / R-APP-ALIVE / R-APP-ENV-PERSIST):** an environment found once is remembered. `APP_ENV` resolves from three sources in order — the explicit parameter, a URL found **on this ticket** (description, comment, a screenshot's address bar, an `Apply patch` HDTN), then the `appEnv` node of `%USERPROFILE%\.jira-ai-runbook-config.json` matched by **recorded identity, never a guessed URL** — and *no `APP_ENV`* is only true once all three have been tried. Every resolved environment is **probed alive before use** (one unauthenticated GET, 10s; a redirect to a login page *is* aliveness), and the result is **written back**: `status`, `lastCheckedAt`, `lastAliveAt`, `consecutiveFailures`, `lastError`, plus `lastBuildStamp` from §1.7a and `storageState` when a session is captured. Entries are **retired, never deleted** (`status: stale` after three consecutive failed probes); ticket-borne credentials are never persisted; nothing in the node reaches a Jira comment, RCA, PR, or log. This is the **one** node the runbook writes, and §1.6c step 4 reconciles it with R-DB-LEDGER-REUSE: a dead environment fails loudly in one probe, while a stale DB ledger corrupts evidence silently.
- **§1.6e knowledge base (R-KB-RESOLVE / R-KB-FIRST / R-KB-EXTRACT / R-KB-CONFIRM / R-KB-WIDEN / R-KB-ABSENCE / R-KB-READ-ONLY):** a **private git repository**, `https://github.com/erick-delacruz_irely/i21_AI-JIRAKnowledgeBase`, resolved from the `knowledgeBase.path` config key then from `<REPO_ROOT>\i21_AI-JIRAKnowledgeBase`, cloned once when absent and `pull --ff-only`ed before the first lookup. A clone or pull failure is recorded and the run continues base-less — it is our gap, never the ticket's, and nothing about it reaches the Jira. Access is a per-developer collaborator invite. The base read at §1.6 Step 0.1, keyed on what the ticket already gives you — an error code, a quoted message, an object name, a screen namespace — for **one keyed extraction against `derived/_index.json`, never a read of it** (R-KB-EXTRACT): the index is 532 KB, about 130k tokens, and a `node -e`/`jq` lookup returns ~200 bytes hit or miss, after which only the ~4 KB record the hit names is read. One extraction already searches all 32 modules, so nothing at this rung is scoped or retried per module. **Earned** records (`cases/`, `modules/`) are prior art: cite them, check them, and read a `refuted` fact as a trap already fallen into. **Derived** records are pointers stamped to `26.3Prod` and carrying `confirm_on_target_branch: required`; one `git grep` on `TARGET_BRANCH` (through `refs/remotes/origin/`) confirms a hit before it enters the analysis, and **an unconfirmed hit may not appear in the RCA as a finding** — an unconfirmed base makes a run faster and wronger. A message hit does not say which layer raised it (`stated_in` does), and a rule stated only in the client is enforced only in the browser. **Absence is never a signal:** one branch of 6,216 is indexed and none of `SqlScripts`, so a miss never shortens a sweep. Absent or stale base → a slower run, never a STOP. This runbook never writes to the base; it states claims in the §6.9 `KNOWLEDGE-DRAFT` block, names what it read in `KB-CONSULTED`, and `JIRA-AI-Reconcile.md` grades both.
- **§6.9 knowledge draft (R-KNOWLEDGE-DRAFT):** four one-line claims — mechanism, cause, fix-pattern, verified-by — closing the §6 RCA comment immediately before `READY-FOR-PR`, plain text and never linked, so the reconciler can grade what the run believed against what actually merged. A claim never stated is never graded, and the base learns nothing from the run. C4 states how far the claim was actually taken; `static reasoning only` is a legitimate answer and a better one than a verification that did not happen. An unconfirmed §1.6e pointer may not be restated here — that launders a candidate into a finding. **The four claims are graded individually** — `C1 mechanism` true with `C3 fix-pattern` wrong is the corpus's most common outcome, and a block written as one argument cannot express it. Two further blocks close the comment beside it: **`KB-CONSULTED`** names every base record actually read and whether it was `used` / `confirmed-not-used` / `unconfirmed`, which is the only thing that makes the dev review's `kb=` field answerable from a fresh session; and **`RUN-GATES`** collects the gate verdicts the run has already recorded (symptom, repro, origin, align, remedy, coverage, ownership, data cause) into one line. `RUN-GATES` computes nothing — it copies — and a token in it that disagrees with the prose above it is a §3 FAIL, which is how the `not-followed` failure mode becomes visible to a reader who never opens the transcript.
- **R-KB-KEY-CANONICAL — strip the schema qualifier before an object lookup (§1.6e step 1).** The index is keyed on bare object names and **none** of its object keys carries a `dbo.` prefix, while a run that has just read a SQL body is holding `dbo.uspX`. An exact lookup of the prefixed form misses, and a miss is indistinguishable from "nothing was indexed" (R-KB-ABSENCE), so the run never learns the record was there. `dbo.uspX` and `uspX` are one object and this normalisation alone is allowed; stemming, truncating and fuzzy-matching are not, because a neighbouring object's record believed is worse than no record.
- **§1.6e is read TWICE (R-KB-REMEDY).** The step 1–4 lookup answers *what caused this*, keyed on the ticket's error code, message, object or screen. The step 5 lookup answers *what fix is acceptable here*, keyed on the objects the §2.7 candidates would touch, and reads a different set of records: `constraint` (a module rule this runbook does not carry — unresolved on a written table it is a STOP), `conventions` (person-owned, prescriptive house style for a remedy), `known-gap` (an open defect a remedy lands beside), and any `refuted` fact (an approach already tried here and found not to hold, which rules its candidate out). Same trust rules throughout: earned records are prior art, derived records are pointers to confirm on this branch, and a miss means nothing was indexed — never that the module has no convention. **The step 5 read widens, and only by name (R-KB-WIDEN):** the rules that bind belong to the module that *owns the object a candidate writes to*, which the `owner_module`, the `caller_modules` count and the §1.7d writer routinely put outside the ticket's prefix — so read the ticket's module, then every other module a candidate object actually implicates, then stop. Widening to modules nothing named is a scan of 32 directories and 1,591 rule files that costs more than the sweep it replaces; each module consulted is named in `KB-CONSULTED`, so widening-and-finding-nothing stays distinguishable from never widening.
- **§2.7 remedy selection (R-REMEDY-SELECT / R-REMEDY-ONE-CANDIDATE / R-MODULE-STANDARD) — which fix, and why not the others.** Runs after §2.6 and **before §3 authors anything**, on every run that authors, ports or recommends a remedy — data fixes and diagnosis-only Tier-2 runs included; skipped only when the run delivers and recommends nothing. It exists because the graded corpus measured **the mechanism right every time and the remedy wrong or incomplete in four of six delivered fixes**, and no other gate asks the question: §1.6–§2.6 settle the cause, the port and the write permission, and everything after §3 validates a change that already exists. Enumerate at least two candidates at different layers, built from work already done (the §3.4 write chain, the binding or comparand consumer, the §1.7d writer verdict, a §2.5 sibling body, surviving §1.6 Step 2a producers) — **a single-candidate list is not an enumeration** unless it records why no other layer can carry the fix. Score each on four axes that are checks rather than opinions: **durability** (does a recurring writer re-assert it — §1.7d), **coverage** (how many sites of the mechanism it closes, the count §3.4 Proof 4 then proves), **blast radius** (caller count, settled by one `git grep` over every call shape, not `EXEC` sites alone), **precedent** (a working sibling body, the module's published standard, or an approach a prior ticket had rejected). Record `REMEDY_VERDICT` and **every rejected candidate with the axis that rejected it** — a preference is not an axis. Where a module states a standard this runbook does not carry, the module wins: the org-wide standards are the floor, and a constraint the module's addendum states and the remedy does not satisfy is a **STOP** (ref IC-29836, template-clean and rejected as "half baked and did not follow the IC standards"). Fail-closed on the enumeration, never on the choice: reaching §3 without a verdict is a §3 FAIL, exactly as a missing `ALIGN_VERDICT` is.
- **§3.4 Proof 4 pattern coverage (R-PATTERN-COVERAGE) — the reported site is not the only site (ref CT-17265).** Proofs 1–3 all reason about the statement the fix touched; none counts the others. Enumerate every occurrence of the mechanism's **construct and invariant** — never its message — across the changed objects, the §2.5 consumers, and `SERVED_TREE` only for client assets; classify each `CLOSED` / `OPEN` / `NOT-A-SITE (<why>)`; and require `|CLOSED|` to equal the numerator §2.7 counted, a disagreement in **either** direction being a failure (fewer means the fix is narrower than claimed, more means the denominator is untrusted). Hidden, default-off and rarely-rendered sites count — they are precisely the ones a symptom-driven search misses, because the reporter could not see them either. Every OPEN site is carried into the CHANGESET or named under **Related defects found**, never left silent. A Proof 4 failure returns the run to §3 rather than to §1: the fix is in the right place, there is simply less of it than was claimed.
- **R-CHAIN-BEFORE-CHOICE — the write chain is identified at §2.7 and proven at §3.4 Proof 1.** Proof 1 is fail-closed and necessarily runs after there is a changed statement to test, but the chain itself is analysis rather than validation, and **a layer cannot be chosen among layers nobody has identified**. So §2.7 builds `W` by Proof 1's own procedure and scores its candidates against it; Proof 1 then confirms the statement the CHANGESET actually touches is the `wi` that gate selected. A disagreement between the two is a finding, not a re-write: the analysis moved after the choice was made, and the choice is re-made on the corrected chain. A run that reaches §2.7 unable to name `w0` has not finished §1.6 Step 2.
- **R-WRITER-BUILD-BUMP — a symptom that survives a newer build has a writer (§1.7d).** A delivery gap is closed by the next build; a recurring writer is not. When the environment took a newer build during the ticket's life and the symptom did not move, the delivery-gap explanation is dead. It costs one comparison of the reported build stamp against the current one and it settles the gate before any sweep runs.
- **§1.6d UI navigation & control catalogue (R-UI-CATALOGUE / R-CATALOGUE-BACKGROUND / R-CATALOGUE-FIRST):** the token-expensive part of app-layer work is discovering *what to click*, so that knowledge is derived once and stored under `%USERPROFILE%\.jira-ai-harness\` (created by the runbook itself on first need — bootstrap from this document alone, nothing shipped). Control maps come from the module's ExtJS **source** (`Generate-ControlCatalogue.ps1`, materialized from §1.6d, keyed `<Module>@<branch>` with the deriving commit; collision names are removed from `byName`, never guessed); menu payloads come only from a **live logged-in shell** (`a.i21-menu-link[data-menu]` → `nav\<envKey>.json`, merged across runs, opened via `iRely.Functions.openMenu` because the anchors are an unclickable template). Generation runs as a **background agent** armed by §1.6b/§1.6c while the main run proceeds through the DB and code layers. §1.7a consumes a **slice, never the file**; every hit is a claim confirmed by one visible-instance component query; misses fall back to live discovery and are **written back**. Absent or stale files are a slower run, never a STOP, never an excuse to skip §1.7a.
- **§1.5a build-number → branch resolution (R-BUILD-RESOLVE):** `https://i21connect.com/#/release` maps a build number to the branch that produced it and to its build time — authoritatively, because the build system emits it. This precedes §1.5 rules 4–5, whose string-parsing cannot recover the mainline shape (`24.22.0824.5121` → `24.2Dev`, `22.12.0829.4808` → `22.1Dev`) or abbreviations (`26.1DevIB` → `26.1DevInternalBooks`); those rules remain the offline fallback and an unresolved stamp is recorded as `BUILD_BRANCH UNRESOLVED`, never asserted. Access is the same SSO SPA pattern as the helpdesk — prefer the XHR the release page itself calls (captured from the first headed run’s network trace and stored as `releaseApi`), else drive the page headless with the saved `storageState`. It also yields **`REPORTED_ENV_KIND`** (R-REPORTED-ENV-KIND): **a JIRA is often reported on a Dev build, and the prose is not reliable about which** — the resolved branch is. On a Dev report, `APP-STALE` means a dev box is behind its own branch head (a redeploy), not that a customer is missing a build, and a §1.6b B1/B2 patch signal means someone hand-patched a dev box. Never a STOP.
- **§1.6b APP_REQUIRED classification (R-APP-REQUIRED):** mandatory on every run, and it decides *whether* the app is needed rather than leaving it to whoever launched the run. Two sufficient trigger families — **A**, the client is the only layer that can raise the symptom (blank/absent dialog text, grid or field state contradicting a correct dataset, client-side JS errors, document *render*, hangs, client-resolved permissions); and **B**, the app-layer deployed state is unknown or disputed (an `Apply patch <JIRA>` HDTN, repro steps gated on applying a patch, a four-part build stamp posted next to "still occurring", dev and QA disagreeing about reproducibility, a §1.7b drift verdict on a path that also contains non-DB files, a reopen of a delivered JIRA whose changeset touched non-DB files). Routes to `APP_REQUIRED-ACTIONABLE` (→ §1.7a + §1.7c) when an environment is reachable; when one is not, it **never stops** — it carries the question forward to §1.8b. Worked example AP-15931, which closed `Cannot Reproduce` with four of these signals visible on the ticket.
- **§1.8b app-required elimination gate (R-APP-ELIMINATION):** the STOP is earned, not classified (operator 2026-08-24). Runs after §1.8 and assembles an **elimination ledger** — one row per reachable layer, naming what was executed and what it produced (`EXEC <object>` with the reported parameters, the §1.7b diff, any replayable request, each excluded R-ERROR-CLASS candidate). A layer reachable but unexercised makes the STOP unavailable. Only when nothing raised the symptom **and** it belongs to a §1.6b Trigger A class does the run reach `APP_REQUIRED-PROVEN` and post an **ENVIRONMENT REQUEST that carries the ledger**, states why the application is the remaining layer, and names the experiment it would run — then STOP. Every `no error raised` row is a `REPRO-ATTEMPTED-DISPROVEN` at that layer, and it is what makes the request credible instead of a shrug.
- **§1.7c app-layer deployed fidelity (R-APP-DEPLOY-DIFF):** §1.7b for the half of the codebase a database cannot describe — the DB does not record the application build, only a running app does. Captures `APP_BUILD_STAMP` while being explicit about what it is: the app reports the version it reads from **`tblSMBuildNumber` on its connected database**, so app-vs-DB matching is a tautology when both point at the same DB, and — because **a hand-applied patch never bumps `tblSMBuildNumber`** — the stamp is structurally blind to the patch cases (§1.6b B1/B2). **Git carries no build numbers**, only main.major, so a four-part stamp maps to a commit only by bridging through the Azure DevOps build that produced it and reading that build’s source commit; unresolvable → `APP-STALENESS UNDETERMINED`, never inferred from the stamp’s digits. `APP-STALE` then routes exactly like §1.7b `DEPLOYED-STALE` (the fix exists and has not reached this environment — deploy instruction, no code fix). Diffs each implicated **served ExtJS asset** over HTTP against `origin/<TARGET_BRANCH>` — the only direct read of deployed app code, needing no build or deploy, and the only thing that can see a hand patch; compiled C# stays out of reach and the ledger says so. Keeps a **patch-provenance ledger** in which an unconfirmed patch is `PATCH-UNVERIFIED`, never assumed applied. With `APP_ENV_PROD` **and** `APP_ENV_DEV` it runs the **three-way prod/dev/branch comparison** — prod observes (read-only, no Axis-B writes ever), dev exercises, the branch adjudicates — whose headline case is *dev already carries the fix and prod has not received it*: a deployment gap, not a defect.
- **§6.8 run telemetry (R-RUN-TELEMETRY):** `RUN_START_UTC` + `RUN_SESSION_ID` are stamped before the first Jira read, and every comment the run posts (RCA, CANNOT-FIX, TRIAGE, INFORMATION REQUEST) closes with a two-line footer giving active and wall minutes, input/output tokens and API turns — measured from the run's own harness transcript by the §6.8 PowerShell block, summed across compaction predecessors, and marked `measured to comment time`. Tokens and minutes only: no cost figure, no headless-child attribution, and an unmeasurable run says so verbatim rather than estimating.
- **§6.6 status handoff (R-STATUS-HANDOFF):** after the comment, resolve the transition **by name** via `getTransitionsForJiraIssue` and move a delivered fix (code or data) to the project's **"code written, not yet in review or test"** status (reference scheme: `Coding`) with `JIRA-AI-Fixed` / `JIRA-AI-DataFix` — skipping the transition and keeping the label when the workflow forbids it or its screen requires fields this run must not invent; every not-fixed outcome keeps its current status and takes only its label (`JIRA-AI-NeedInfo` / `JIRA-AI-CannotFix` / `JIRA-AI-Triaged`). Labels are always additive. Assign the operator only when the issue is **unassigned** — never reassign someone else's ticket. **Never** transition to `Testing`, `Ready to Test`, `Closed`, or `Done`. No available transition → skip and report, never force.
- **§6.6 AI-Assisted stamp (R-AI-ASSISTED, operator 2026-09-02):** every run sets the ticket's **AI-Assisted** field to `Manual AI` — written by **id** `customfield_14679`, because the field is spelled `AI-Assissted` in Jira and no name match will find it. Payload `{ "customfield_14679": { "value": "Manual AI" } }`; options are `No` / `Full AI` / `Manual AI`. **Every** run outcome takes the stamp — including `ALREADY-RESOLVED` and every outcome that earns no label — because the field records that analysis was applied, not what it concluded. The only tickets left untouched are those refused by the issue-type / issue-status gates, which by definition were never run. Never downgrades an existing `Full AI`; a rejection is reported as a skip and the run continues.
- **§6.7 PR handoff (R-PR-HANDOFF):** end a successful code-fix run by emitting `READY-FOR-PR: <PRODUCT> | <ADO_REPO> | <FEATURE_BRANCH> → <TARGET_BRANCH> | <JIRA> | <n> file(s)` as the last line of BOTH the run output and the §6 RCA comment (one line per repository; append `| schema-confirmation: pending` when §3.5 is still running). Values come from what was actually pushed — no push, no handoff line. A data fix emits `READY-FOR-REVIEW (data fix): …` instead. This creates no PR.
- **§3.4a client-tree placement (R-JS-CLIENT-TREE) — a `.js` fix in the tree the branch does not serve fixes nothing (operator 2026-08-29).** i21 module repositories carry two parallel ExtJS trees with near-identical filenames — legacy `app/` and modern `universal/`, sharing **455 basenames** on `AP` 24.1 — and `universal/` exists on **23.1 and up only**; on 22.x and below `app/` is the only tree. Detect `SERVED_TREE` from `git ls-tree origin/<TARGET_BRANCH>` (both present → `universal`; only `app` → `app`; neither → no split), **cross-check it against `TARGET_VERSION` ≥ 23.1** and confirm it with 24-month per-tree commit counts (`AP` `26.1Dev`: universal 575, app 15) — never hardcode the threshold, and never let the version overrule the branch. Every changed client asset must be `PLACED` in `SERVED_TREE`: a `MISPLACED` file is moved and §3.4 re-run on the new path; an absent counterpart must be **proved loaded** (entry-point reference, or a §1.7c served-asset diff) before the dead tree may be edited; editing both trees is not a compromise. Reading counts too — a root cause traced through the unserved tree is void. Fail-closed, because this is the one defect class that passes review, merge, propagation and QA while leaving the customer's symptom untouched. Reported on the mandatory RCA **Client tree** line in both directions.
- **R-RCA-LINKS (operator 2026-08-29) — the RCA is navigable, not merely readable.** Every address the comment names is a link: the feature branch, the commit, each changed file at the branch it was changed on, related JIRA keys, and any cited guideline page — **and neither a branch-vs-target diff nor a pull request, which the comment does not name at all (operator 2026-09-01)**. A mandatory **Delivery** block at the top of the RCA carries branch / commit only, and §6.7's `READY-FOR-PR` line stays unlinked beside it because that one is parsed rather than clicked. URLs are built from what §5 actually pushed and from `ADO_REPO` resolved off the origin remote, with the branch URL-encoded; a §2.6-held or unpushed path is named **without** a link, because a link asserts the thing exists. **Posted as `adf` for R-COMMENT-MENTIONS, markdown `[text](url)` is inert** — links become `link` marks on the text nodes, the exact counterpart of the `mention`-node rule.
- **Issue status must mean `Open` or `Reopened`** (matched against the project's own workflow, reference-scheme names) — any other status (reference scheme: `Coding`, `In Progress`, `Testing`, `Ready to Test`, `Investigating`, `Closed`, …) is a STOP with no comment, reported as `OUT-OF-STATUS (<status>)`: the issue is already being worked or verified, and an automated run would collide with or duplicate that work.
- Acceptance criteria drive both the implementation and the Acceptance Verification block. If they are missing/insufficient and cannot be reliably derived -> STOP.
- **When the change touches SQL scripts (`IS_LIQUIBASE_STANDARD_CASE = true`): apply the Liquibase standard compliance rules (§A–§J of `JIRA-PR-Automation.md`).** Every new changeset uses a timestamp ID in the correct folder/file, with preconditions where it may already exist, a rollback, and `endDelimiter:GO` where required. Never commit a version-style changeset or a raw SSDT/`SqlScript` file. **EXCEPTION (R-LB-24.1-TARGET): Liquibase exists only for i21 versions ≥ 24.1.** On a < 24.1 target branch (22.x/23.x) the SQL fix is a direct **i21_sqlscripts SSDT edit** (raw `.sql` commit IS correct there), `i21_Liquibase` is not a valid repo for that branch, §A–§I changeset mechanics are skipped, and §J binding stays fully enforced.
- **§3.10 deployable patch (R-PATCH):** when the CHANGESET touches a database object, the run also delivers `<JIRA>Patch.sql` — whole `CREATE OR ALTER` bodies from the validated files in dependency order, re-runnable, no data DML and no schema DDL, §J-bound, carrying the build it may be applied to. When a DB is reachable it is **applied, compiled, re-tested against the reported transaction, and rolled back by restoring the pre-fix bodies** (§1.7b's scripted originals; the DB is left unfixed, and a failed restore is a review-blocking finding). Attached to the JIRA and inlined in the §6 comment. A non-SQL changeset says `N/A` explicitly — an absent verdict is a STOP. On §1.7b `DEPLOYED-STALE` this patch (sourced from `origin/<TARGET_BRANCH>`) is the entire deliverable: no code fix, no branch, no PR.
- **§3.11 affected-data sweep (R-DATA-SWEEP):** a code fix stops the defect; it repairs nothing already broken. When the defect persisted a wrong value AND a database is available, the run delivers ONE **read-only** query derived from the mechanism §3.4 proved (never from the symptom), returning business identifiers + stored vs re-derived value + delta + posted state, scoped to what the defect can reach. **Fail-closed calibration:** the ticket's reported transaction must appear in the result set — if it does not, STOP and reconcile before reporting any count, because either the query or the root cause is wrong. Rows found → the §6 comment carries the count, the identifiers, the scope, and the statement that a `Data Fix` JIRA is required; zero rows is reported as the finding it is. Missing either trigger condition → the sweep is skipped, the reason is disclosed, and **no query is delivered** — an unexecuted sweep looks like a finding, carries no count, and gets run unvalidated against production. This runbook never files the Data Fix JIRA and never authors a data fix under a code-fix key (§3.6 is the path, on its own `Data Fix` issue, behind the Senior BA gate).
- **§3.5 schema-change confirmation:** `liquibase update` is ONLY a confirmation function. DB known for the JIRA → run it on a **separate agent** (update → `rollback-count <N>` verification, DB left rolled back — never re-applied; full logs under `<liquibaseLogDir>\<JIRA>\`; ✅/❌ result posted as ONE PR comment on the `<FEATURE_BRANCH>` PR, or on the Jira when no PR exists yet) while the main run continues to the next step/JIRA. DB not known → skip WITHOUT stopping and disclose `liquibase update NOT run` in the §6 RCA. **Pre-24.1 branch → case C instead:** save the pre-fix object definitions, execute the changed script on the JIRA's DB to confirm it deploys cleanly, capture the AFTER evidence, then **restore the pre-fix definitions — the DB is always left unfixed** (allowed even on a shared `knownServers` DB because the restore removes the mutation; a failed restore is a review-blocking finding reported immediately). §J static object binding stays fail-closed in every case. Never edit the repo's `liquibase.properties`; the DB URL is passed per run.
- Validation runs **before** any branch/commit/push. Create and push the feature branch only if validation passes with no issue and every acceptance criterion is satisfied.
- For TECHNICAL_DEBT issues: before pushing, verify linter checks pass with no new errors and all dependencies resolve (including exact column/identifier binding); STOP if either fails.
- One push for the repository. STOP if: JIRA_KEY is missing/invalid; REPO_PATH cannot be resolved (auto-resolution ambiguous and the user did not answer), cloned, or loaded; `<REPO_PATH>` is the `<REPO_ROOT>` container folder rather than a repository, or is not a git repo; an explicitly provided TARGET_BRANCH does not exist on origin; §1.5 cannot derive an `EXPECTED_BRANCH` that exists on origin; the Azure DevOps MCP preflight fails; any required validation check fails or cannot be run and is not explicitly waived; the push fails; or the Jira tool is unavailable.
- Jira activity on the parent issue: **exactly ONE comment per run**, selected by outcome per R-NOFIX-COMMENT — the **RCA / Acceptance Verification** comment (§6) after a successful fix (branch pushed, or data fix delivered per §3.6); else a deduped **INFORMATION REQUEST** (+ `JIRA-AI-NeedInfo`), a **CANNOT-FIX** (§6.5 A), a **fix-delivery informational** note (Step 0.5), or a **TRIAGE** comment (§6.5 D, + `JIRA-AI-Triaged`). Plus the §6.6 label/transition/assignment writes. An ALREADY-RESOLVED verdict and the out-of-type/out-of-status gates post nothing at all.
