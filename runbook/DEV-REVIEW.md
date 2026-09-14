# Dev Review — format and procedure

A **Dev Review** is a judgement posted on a JIRA about work that already exists: it confirms or
overturns an RCA, accepts or replaces the proposed fix, and states what happens next. Every claim in
it is proven — by evidence the run produced, or by the developer's own reading and testing — and it
never introduces an unproven one.

**Run by the developer who did the verification, not by an automated sweep.** They analyse and test
the fix themselves, then invoke this skill with the verdict that testing produced. This skill turns
that judgement into a defensible comment; it does not form the judgement.

> **This is the interim version and it depends on no knowledge base.** `DEV-REVIEW v4.md` is the
> other one, wired to the JIRA-AI Knowledge Base and its reconciler: it emits a machine-read trailer,
> reads the run's `KB-CONSULTED` block, and routes corrections into the base as facts. While the
> knowledge-base approach is still being settled, use **this** file. The two are meant to diverge;
> the discipline that survives without a base — grading the run's claims one at a time, naming why a
> remedy fell short, keeping content out of the runbook — is kept here in prose instead.

Reference examples:
[AP-24880](https://irely.atlassian.net/browse/AP-24880?focusedCommentId=1268543) (fix replaced by a
sibling port) and [AP-24912](https://irely.atlassian.net/browse/AP-24912?focusedCommentId=1273844)
(fix works, ownership routed to another module).

**Format authority:** [AP-24953 comment 1275674](https://irely.atlassian.net/browse/AP-24953?focusedCommentId=1275674)
(operator 2026-09-03 — the AP-24985 review was corrected against it). When this file's section table
and that comment's rendering disagree, the comment wins: the table below governs WHICH sections appear
and in what order; AP-24953 governs HOW they look on the ticket.

---

## The prompt

```
Create a Dev Review on <JIRA-KEY>.

Verdict:
1. RCA is <correct | correct but incomplete | wrong>. <one line of why>
2. The proposed resolution <works | was rejected on review | works but ...>. <one line of why>
3. The correct solution: <as delivered | what should be done instead, and where it comes from>.
4. Disposition: <what happens next and who owns it>.

What I tested:
5. Environment <URL>, build <stamp>, database <server / restore>.
6. Transaction <id> — <what I did and what I observed>.
   (or: not tested — <why>)

Drop the draft here first — do not post it.
Nothing leaves this chat until I say so: no comment posted, no owning-module
ticket created, no branch renamed, no file attached, no label or status changed.
```

Everything below is standing format — the developer supplies only the verdict and the testing lines.

**Lines 5 and 6 are the developer's own work, and they are why this review carries weight.** The
verdict comes from having exercised the fix, not from reading about it. Supply them with the verdict
rather than being asked for them afterwards. `not tested` is a legitimate answer with a reason
attached — a routing review tests nothing by design, and a defect that cannot be raised on any
reachable environment is a real state — but it is never the silent default.

**Verdict line 3 is what Section 3 reports, and it is not always the delivered fix.** When line 2 says
the resolution works, line 3 is usually `as delivered` and Section 3 records what was accepted. When
line 2 rejects or qualifies it, line 3 is the developer naming the fix that *should* land — a sibling
port, a different object, a narrower change — and that becomes the subject of Section 3, with
Section 4 carrying the numbers for why it beats the proposal. Never infer line 3 from line 2: a
rejected fix does not tell you what the right one is, and guessing it is how a review ends up
advocating a change nobody chose.

**Verification is normally INCLUDED, because the developer already did it.** Lines 5 and 6 of the
prompt carry it, and Section 5 reports it. Ask only when they are missing: one line — *"you didn't
give me the environment and transaction — include a Verification section, or post the verdict
alone?"* Never assume it, never invent it, and never leave it out silently. A review that skips
verification the developer actually performed throws away its best evidence.

**Exception — do not ask, and skip Verification entirely, when the review CONFIRMS the defect is owned
by another module** (operator 2026-09-03). A routing review verifies nothing: no fix lands here, so
there is no corrected behaviour to exercise and no environment of ours to exercise it on. The
deliverable is the diagnosis and the routing, and the owning module does its own verification once it
writes the fix.

---

## Where the context comes from

**Take the AI analysis already on the ticket as the reference** (operator 2026-09-03). The fix run
leaves an RCA comment, and that comment is the durable record of what was found: root cause and
mechanism, sibling alignment and port exclusions, regression and property-test numbers, defect lineage
and coverage gaps, the object-ownership verdict, and the handoff line naming the branch and commit.
Read it first, whatever else is available.

**The RCA may close with structured blocks — read the ones that are there** (operator 2026-09-05).
Older comments carry none, and their absence changes nothing about the review.

- **`KNOWLEDGE-DRAFT`** states the four claims the run believed: mechanism, cause, fix-pattern, and
  how far each was actually taken. **Grade them one at a time, and say so in Section 2.** `C1
  mechanism` true with `C3 fix-pattern` wrong is the single commonest outcome in the corpus — it is
  exactly what "correct RCA, rejected fix" means — and a ticket-level verdict cannot express it.
  `half` is the grade for a claim right in substance and wrong in scope: a cause correct for the
  reported row and not for the population. A claim the review had no evidence to judge is *ungraded*,
  which is honest and common for the fourth. A review that grades all four as ungraded re-derived
  nothing — say that rather than posting it.
- **`RUN-GATES`** collects the gate verdicts the run recorded — symptom, repro, origin, align,
  remedy, coverage, ownership, data cause. **Read it against the prose above it.** Every token is
  copied from somewhere else in the same comment, so a disagreement is visible without opening a
  transcript, and it is the one thing that exposes a gate that fired and was not honoured. Two live
  examples: a reproduction verdict of `NOT-REPRODUCED-NO-ENV` sitting above a ledger naming the
  database that was touched, and an origin trace recorded `N-A` on a ticket whose own RCA reports a
  stale stored value twice. Both are `not-followed`, and no new rule fixes either.

Do not confirm the draft's claims out of the draft itself — the same trap as confirming an RCA out of
its own comment, below.

Two situations, and they are not equally easy:

- **Same session as the fix run.** Its work is still in context — the code that was read, the queries
  that were run, the diffs. Use that directly; it is richer than the comment, which is a summary.
- **A fresh session.** Only the ticket exists. Reconstruct from it: the RCA comment, the branch and
  commit it names (read the actual diff), the attached patch artifact, the issue description and
  attachments, and **any comment posted after the RCA** — a QA retest or a reopen changes the verdict
  and is the one thing a stale reading misses.

**The trap: do not confirm an RCA out of its own comment.** If the review reads the analysis and
restates it, it has endorsed a conclusion using that conclusion as the evidence — which fails exactly
when it matters, i.e. when the analysis is wrong. Re-derive the load-bearing parts independently before
agreeing with them: read the changed object on the branch, re-run the sibling diff across the active
lines, and check the deployed body where a database is reachable. *(AP-24880 is the shape to keep in
mind: the RCA was correct and the fix was wrong. No amount of re-reading the RCA would have surfaced
that — it took diffing the object against sibling branches. AP-24953 is the milder version: re-deriving
turned up a second discriminator the RCA had not used, and a screen column that would have been cited
wrongly.)*

**The developer's verdict is the input, not the analysis.** They supply the verdict and testing lines; this skill
turns that judgement into a defensible comment and declines to dress it in evidence that does not
exist. Where an independent reading disagrees with the verdict, say so before posting — not after.

---

## Section order

Post as a Jira comment in **ADF** with real mention nodes and live links.

**Rendering (operator 2026-09-03 — match AP-24953, not this table's numbering):**

- ONE small heading for the whole comment: `### Dev review - <short outcome>`. Nothing else is a heading.
- Every following section is a **bold lead-in paragraph** — `**RCA verdict - correct.**`,
  `**Solution.**`, `**Verification.**`, `**Disposition.**` — followed by its prose. **Never render the
  sections as numbered or `###` headings**; the `#` column below is ordering only, and writing
  "1. RCA verdict" into the comment is the exact mistake the AP-24985 review had to be edited for.
- Verification carries a `**Developer's Testing:**` numbered list (see the Verification section below)
  and closes with the screenshots-to-attach line.
- **No long paragraphs (operator 2026-09-03, ref AP-24991 review).** Short sentences. At most 2–3
  sentences after a bold lead-in. Anything longer becomes a bullet list, one fact per bullet. A
  computation is never buried in prose — set it out on its own line (or a short code line). If a section
  needs a fourth sentence, it is carrying material that belongs in a list or should be cut.
- cc goes last, after a divider.

| # | Section | Contents |
|---|---|---|
| 1 | Heading | `Dev review - <short outcome>` |
| 2 | RCA verdict | Correct or not, the mechanism in one paragraph, and the arithmetic or observation that proves it |
| 3 | Solution | **The correct solution, from verdict line 3** — what was accepted, rejected or replaced, where a replacement comes from, and what was deliberately excluded. **Grade the choice of fix, not only its correctness** — see the selection review below the table |
| 4 | Why this approach rather than the proposed one | **Only when the fix changed.** Concrete numbers, checked per account / per row — never on totals alone |
| 5 | Verification | **From the developer's own testing (prompt lines 5–6). Omitted only when they did not test, and never present on a foreign-ownership routing review.** Carries the environment URL and the tested transaction, plus `<server or restore> / <database>` and build `<stamp>`. State that the deployed object matches the reviewed code, then the observed result — then the **Developer's Testing** numbered list (one line per acceptance criterion, honest verdicts: `PASS` only when observed, pending items named as pending), closing with the screenshots-to-attach line |
| 6 | Disposition / handoff | Branch, commit, patch artifact, who raises the PR, and what this supersedes |
| 7 | What needs to improve in the runbook | **Only when a verdict is wrong, and only for items that survive the content test.** Opens with the GENERAL failure in one short paragraph, then numbered **candidates**, each classified by failure mode and carrying the six-line shape. See the diagnosis discipline below the table |
| 8 | cc | The module owners the disposition implicates |

Section 4 self-skips when the fix stood. Section 5 self-skips only on a routing review or when the
developer states they did not test.

**The selection review — Section 3 grades the CHOICE, not only the code (operator 2026-09-05).** A
fix can be correct at every line it changes and still be the wrong fix: made at the layer where the
symptom surfaced rather than where the value was decided, or on data some writer re-asserts next
build, or on the one site of a mechanism the reporter could see. Those are the failures the corpus
actually shows, and reading a diff for correctness cannot find any of them. The fix run now records
its own answer — a `REMEDY_VERDICT` naming the layer it chose and the candidates it rejected, with
the axis that rejected each. Read it, and put four questions to it:

- **Was there a candidate at another layer?** If the run enumerated one and rejected it, is the
  rejecting observation true? If it enumerated none, the choice was a default rather than a decision
  — say so, however well the fix works.
- **Does the correction hold?** Name the writer, if any, that re-asserts what this fix sets.
- **How many sites does the mechanism have, and how many did this close?** The run states a count;
  the review is where an over-count is caught.
- **Does the owning module impose a rule this fix does not meet?** Template-clean is not
  module-clean, and the module's own developer is usually the only person who knows.

Where the RCA carries no `REMEDY_VERDICT` at all — every run before 2026-09-05 — say so and grade the
choice yourself from the diff and the sibling lines. The absence is a finding about the run, not a
reason to skip the question.

**Name the shape when a remedy falls short**, in Section 3 or 4, using this vocabulary rather than
prose that varies review to review. *Wrong layer* — fixed where the value was observed, not where it
was decided. *Not durable* — a correction some recurring writer re-asserts. *Incomplete coverage* —
the reported site closed, siblings of the same mechanism left open. *Below standard* — correct, and
short of a rule the owning module imposes. *Not enumerated* — no alternatives were recorded, so
nobody can tell whether the layer was chosen or defaulted to. These five are what the corpus actually
shows, and a review that names one gives the next reader something to check.

**Section 7 appears only when the root cause analysis or the proposed solution was INCORRECT**
(operator 2026-09-02) — i.e. verdict 1 is `wrong`/`correct but incomplete`, or verdict 2 is
`was rejected on review`/`works but ...`. On a clean pass — RCA correct *and* resolution correct — it
is **omitted entirely**: there is no rule failure to report, and a section speculating about one on
work that came out right is noise on a customer-facing ticket. **A finding worth keeping from a clean
run belongs in Sections 2 and 3, where it is a statement about this ticket, not in the runbook**
(operator 2026-09-05). "Straight to the runbook" is an ungated route into the document whose growth
this whole scheme exists to stop, and a finding from a run that came out right is the weakest
possible case for a new rule.
(The reviews that produced `R-ALIGN-TO-SIBLING`,
`R-PORT-DEPS` and the Tier-1 ownership escalation were all *overturned* verdicts — AP-24880's fix was
rejected, AP-24912's ownership was re-routed — which is exactly the case this section is for.)

**Section 7 diagnosis discipline (operator 2026-09-03, ref AP-24991 comment 1276531 — the exemplar).**
Diagnose the GENERAL failure, not the scenario. A rule patched to the surface detail ("resolve the
currency", "read the rate") catches only the next currency ticket; the review must name the failure
class that produced the miss. How to get there:

1. **Open with the general failure in one short paragraph.** State it as a property of the run's
   reasoning, not of the domain. AP-24991's: *the run claimed a root cause whose story required an
   INVENTED fact, while the true cause required only an UNREAD one.*

2. **The scenario test, and the content route it opens (operator 2026-09-05).** If the proposed rule
   names the domain detail that was missed (a currency, a UOM, a rate, a table, a screen), it is too
   narrow — lift it until it would also have caught the same miss with a different detail. First
   drafts of AP-24991's items were currency rules; the accepted items are: substitute-row
   observations never select a candidate, every candidate carries an unobserved-assumption ledger,
   and an RCA must re-derive the reported numbers from observed values before delivery.

   **If it cannot be lifted — if it stops making sense the moment the specific object is removed —
   it is CONTENT, not a rule.** It leaves Section 7 entirely and is stated in Section 2 or 3, where
   it reads as what was actually true about this defect. This is the common case, not the exception:
   measured over the review corpus, **seven of eight** pieces of developer feedback are content-shaped
   and one clears the bar. A runbook that absorbs every correction grows without limit, and a rule can
   only ever accumulate — where a statement about one defect is read, used, and left behind.

   *(This is the seam the knowledge base was designed to fill: content routed out of Section 7 has no
   durable home yet, so it lives on the ticket. Keeping it out of the runbook still matters — a rule
   written from one object is worse than no rule.)*

3. **Classify the failure mode. Three of the five are not new rules (operator 2026-09-05).** Naming
   the mode is what tells the runbook owner which instrument to reach for, and it is the difference
   between a workflow fix and a bolted-on check:

   | Mode | What actually happened | Instrument |
   |---|---|---|
   | `no-gate` | nothing in the runbook asks this question | a new rule |
   | `trigger-narrow` | a gate exists; its trigger did not match this shape | widen the trigger, no new rule |
   | `wrong-answer` | a gate fired and returned the wrong result | fix that gate's logic |
   | `mis-sequenced` | a gate exists and is correct, but ran too early or too late to help | re-run or re-order it |
   | `not-followed` | a gate fired, and the run did not honour it | **no rule at all** — a rule added here fixes nothing and is pure bloat |

   `mis-sequenced` is the one with no expression before this edit, and it is a real category: the
   AP-24915 correction was not a new check but a re-run of the prior-art sweep, later and keyed on
   the configuration row, because the early sweep is keyed on wording and cannot reach a sibling
   whose screen differs.

4. **Each surviving item carries this shape.** Every line is something only the reviewer knows,
   holding the failure and the runbook in view at the same time:

   ```
   <slug> — <failure mode>
   Gate:           §<id> <rule id>, or NONE          # plain text, never a link
   Signature:      <one line, written to match the same failure on another ticket>
   Position:       <where in the sequence it belongs, and what it gates>
   Cost:           <what this check costs every future run>
   Counterfactual: <the observable this gate would have produced on THIS ticket>
   Supersedes:     <rule id, or nothing>
   ```

   **Gate** is required even when the answer is `NONE`: promotion cannot clear its third condition
   without it, and an unchecked proposal is exactly what that condition exists to stop. Cite it as
   plain text — the runbook lives elsewhere, so a path resolves on one machine and nowhere else, and
   its line numbers drift within a single editing session. **Signature** is what lets recurrence be
   counted across tickets; prose cannot be matched and a stated signature can, and recurrence is the
   one promotion condition no single review can check. **Cost** is what keeps the runbook fast rather
   than merely short, and the reviewer is the only person who knows whether the missing check was one
   query against a log or a database restore.

5. **Say which single item would have caught the ticket dead — as an observable, not an assertion.**
   Not *"this would have caught it"* but *"candidates would have gone 3 → 1 and the run could not
   have claimed a root cause."* That is what tells the runbook owner which change to take first, and
   it is the only form of the claim anyone else can check.

**These are candidates, not decisions (operator 2026-09-05).** Promotion runs a four-condition test
elsewhere, and two of those conditions — recurrence across independent tickets, and whether an
existing gate already covers it — cannot be settled from one ticket. Write them as proposals a
runbook owner will adjudicate. It also keeps a customer-facing ticket from carrying what reads as a
settled change to a document its readers cannot see.

---

## Verification — the developer's own testing, reported

**Skipped outright on a routing review.** When the review confirms the defect is owned by another
module, Section 5 does not appear and the question is not asked — see the exception under **The
prompt**. Nothing is being verified: no fix lands here, and verification belongs to whoever writes it.

**Otherwise it comes from prompt lines 5 and 6**, because the developer tested before invoking this
skill. Report what they observed; never generate it. If those lines are missing, ask once, and if the
answer is that no testing happened, Section 5 is omitted and the review stands on the verdict alone —
a verification block invented to fill a slot is worse than none.

**When it is included, it carries all of this:**

- the **environment URL** and the **tested transaction** — both required, both from the developer's
  own testing lines;
- `<server or restore> / <database>` and build `<stamp>`;
- a statement that **the deployed object matches the reviewed code** (or that it has since been reverted);
- the **observed result** on that transaction;
- a **`Developer's Testing:` numbered list** grading each acceptance criterion (operator 2026-09-03 —
  the AP-24985 review was corrected for omitting it). Same verdict honesty as the fix runbook: `PASS`
  only for an observed result with the evidence named; anything resting on the developer's own test is
  written as *to be evidenced on `<transaction>`*, and anything not raised is `NOT REPRODUCED` /
  `NOT TESTED` with the blocker named. See AP-24953 comment 1275674 for the shape.

**The tested transaction must be a discriminating one, and the review must say why.** A document only
proves the fix if the defect's guard actually fires for it — otherwise old and new code produce the same
screen and the test proves nothing. State the guard inputs and both outcomes. *(Worked example —
AP-24953 / `PIDE-178`: item type Inventory and transaction type 1 put it inside the `IN (1, 16)` guard,
and contract UOM `4419` ≠ receipt UOM `4415`, so pre-fix code would have stored `4419`; the row holds
`4415`, and `dblUnitQty` holds `60` where the old body would have written `1`. Had the type been outside
the guard, or the two UOMs equal, the same voucher would look identical either way.)*

**Screenshots are a human step — note them, do not attempt them.** Close the Verification section with a
line inviting the developer to attach captures, e.g. *"Screenshots of `<transaction>` to be attached for
verification support."* Capturing them needs a signed-in application session and, in practice, a person
at the keyboard; the runbook never types credentials, and the Browser pane's screenshot cannot be written
to a file for upload. So the review names what a capture would show and leaves the attaching to the
operator. Never fabricate or synthesise an image, never attach a login page as proof, and never crop a
capture so a contradicting value falls outside the frame.

**Know which field a screen actually renders before citing it.** *(AP-24953: the Search Vouchers grid's
`UOM` column shows the **cost** UOM — `intCostUOMId`, KG — while the voucher entry screen's detail grid
shows `intUnitOfMeasureId`, "60 Kg Net". A capture of the first would have read as though the defect were
still present.)*

**If the environment cannot be signed into — ASK THE OPERATOR TO LOG IN.** When a capture or a live check
is wanted and the app shows a login screen:

1. Open the environment in the **Browser pane** (`navigate`) and check for a session — `screenshot`, or
   `read_page` and look for Username / Password / Login fields.
2. **Ask the developer to log in, naming the environment URL**, and wait for them to confirm. Log in *in
   the Browser pane*: a login in their own Chrome does not carry over unless the Claude-in-Chrome
   extension is connected (`list_connected_browsers` returns non-empty). **Never type credentials** — not
   the username, not the password, not the company — even when the developer supplies them in chat.
3. **Check `tabs_context` for "The Browser pane is currently hidden" before asking at all** — an ask to
   type into a pane the developer cannot see is unactionable, and nothing fixes it from this side:
   `tabs_select` and `preview_start` both succeed while the pane stays hidden.
4. **Re-check after they confirm** — the pane can still be unauthenticated (wrong company, failed login,
   or they logged in elsewhere). If it is still the login page, say so and ask once more rather than
   proceeding.
5. **Still no session → post the review without the capture**, say in chat that it is outstanding and why,
   and offer to attach later. The screenshot blocks itself, never the review.

---

## Routing a confirmed foreign-owned defect to the owning module

**Applies only when the dev review CONFIRMS the defect is owned by another module.** This does not
weaken **R-NO-REHOME** (the fix runbook's object-ownership gate): that rule forbids the *runbook* from
re-homing a ticket on its own judgement. Here a human has made the ownership call, and this is the
authorized consequence.

**Section 5 (Verification) is omitted on this route** — no fix lands here, so there is nothing of ours
to exercise, and the owning module verifies once it writes the fix. Do not ask the developer for an
environment or a tested transaction on a routing review.

**Create a new ticket directly in the owning module's project — do not clone, and do not move the
original.** A clone drags the source project's sprint, labels and workflow state with it and shows up
in the owning team's board as somebody else's artifact; a move takes the reported ticket away from the
reporter and the QC cycle that raised it. A directly created ticket carrying the same content is
cleaner in both directions.

1. **Create the ticket** in the owning module's project:
   - **Keep the JIRA title exactly as-is** — no `CLONE - ` prefix, no re-wording. QC and support search
     by that summary.
   - **Keep the description as-is**, including the HDTN reference line, the repro steps and the
     embedded images.
   - Carry across: attachments, reported build, customer, environment, Fix Version, priority, and the
     issue type. Do not carry the source project's sprint or labels.
   - Link it to the original (`relates to`), both directions.
2. **Comment on the new ticket** explaining why it landed there — this is the whole point of creating
   it rather than moving one. Include: the original key, the confirmed root cause, the object and lines
   at fault, the ownership evidence (file path, caller distribution, and that every prior commit to the
   object carries the owning module's keys), the introducing commit/JIRA, and where the proven fix and
   patch artifact already are.
3. **Assign it from the Module Assignments page** —
   [HR/Module Assignments](https://irely.atlassian.net/wiki/spaces/HR/pages/61309417/Module+Assignments).
   Resolution order:
   1. Find the row whose **`SQL Table Naming`** column matches the owning module's object prefix
      (`CT`, `AP`, `IC`, `GL`, `AR SO POS`, `LG - CTRM`, `MFG`, `RK TRF`, `FRM`, `SM`, …). That column
      is the join key — match on it, not on the `Module` display name, which is ambiguous across LOBs
      (`Manufacturing` and `WMS` each appear under two LOBs, and `Logistics` under three).
   2. Assign to the row's **Business Analyst**. If that cell is empty or unusable, fall back to the
      **Product Manager**.
   3. **Skip any name marked `(Deactivated)`, `Former user`, `(Deleted)` or `(Unlicensed)`** — the page
      is not pruned, and several rows' BA/PM cells hold only retired accounts. Prefer a name without a
      `(Training)` marker over one with it.
   4. Several usable names in the cell → pick one and **name the alternates in the comment**, so the
      owning team can re-assign without re-deriving the list.
   5. **No usable BA or PM for that row → assign to the reporter**, i.e. the account creating the new
      ticket. Never leave it unassigned, and never guess a developer from the `Developers` column.
   - Resolve each display name to an accountId with `lookupJiraAccountId` before assigning; if a name
     cannot be resolved, say so in the comment and fall through to the next candidate.
4. **Rename the branch** when one already exists — `<base>_<NEW-KEY>` — and re-point the commit
   message, the patch artifact filename, and every link in the comment at the new key:
   ```bash
   git push origin <base>_<OLD-KEY>:<base>_<NEW-KEY> && git push origin --delete <base>_<OLD-KEY>
   ```
   then `git branch -m <base>_<OLD-KEY> <base>_<NEW-KEY>` locally and amend the commit message.
   **Only while no PR exists on the old branch** — if one does, stop and say so. Rename *before*
   posting, so every link in the comment resolves.
5. **On the original ticket**, add the dev review (or a short follow-up if it is already posted) naming
   the new key, who it was assigned to and why, and restate the handoff line against the new key. The
   original keeps its own status — it is not closed by this routing, and closing it is the reporting
   team's call.

> **Worked example — CT.** Object prefix `CT` → row `AG | Contract Management | … | CT`. BA cell holds
> Guru Prasadh and Vijaya Kumar (both usable); PM is Anup Kivade **(Deactivated)** and so unusable —
> which is exactly why BA is tried first. Assign to one of the two BAs, name the other as the alternate.

---

## Rules

- **Keep responses brief and concise.** Focus only on the important or relevant details and avoid
  unnecessary explanations. This governs the posted comment and the chat around it: a reviewer reads a
  dev review to learn the verdict and what happens next, not to be walked through the reasoning. State
  the mechanism once, give the number that proves it, and stop. Cut anything a reader would skip —
  restated context, narration of steps taken, hedging, and any section whose condition did not fire.
- **Avoid long paragraphs; avoid long sentences (operator 2026-09-03).** Write short sentences — one
  claim each. Cap a paragraph at 2–3 sentences; past that, convert to bullets. Put arithmetic and guard
  inputs on their own lines, never inline in prose. Drafts shown in chat follow the same shape as the
  posted comment.
- **Ground every claim in evidence — the run's, or the developer's own.** A dev review is a judgement
  on existing work plus the testing that judged it, never a fresh analysis invented at writing time.
- **Keep the RCA verdict and the solution verdict separate.** They are independent: AP-24880 was
  correct RCA / rejected fix; AP-24912 was correct RCA / working fix.
- **Report verification; never invent it.** Section 5 comes from the developer's own testing lines and
  names the **environment URL** and the **tested transaction** they gave, plus server or restore,
  database and build stamp. If any of it is not in context, say so rather than inventing it. Never
  substitute a neighbouring document for the one named: reading a *similar* record is an analogy and
  cannot grade a criterion `PASS`. Full detail in **Verification — the developer's own testing,
  reported**.
- **Verify against the deployed body, and say if it has since been reverted.** An environment where the
  patch was applied, tested and rolled back is back on defective code — the stored row is still valid
  evidence, but a re-test there will fail, and the reviewer must be told.
- **Screenshots are the developer's to attach.** The review notes what a capture would show and invites
  one for verification support; it does not produce one. Never fabricate or synthesise an image, and
  never attach a login page as proof.
- **State what the disposition supersedes** (e.g. `READY-FOR-PR is superseded by ROUTING-REQUIRED: CT`).
  When no routing ticket is created, say explicitly that the ticket is not being moved.
- **Never move or clone the reported ticket.** Ownership routing is always a *new* ticket in the owning
  module's project, created directly, with the original left in place and linked.
- **Every routing ticket leaves with an assignee** — BA, then PM, then the creating account. An
  unassigned ticket in another team's project is indistinguishable from noise on their board.
- **ADF, not markdown.** In a mention-bearing comment, markdown `@names` and `[text](url)` are inert —
  use `mention` nodes and `link` marks. Resolve ids with `lookupJiraAccountId`.
- **Render to the AP-24953 shape** (operator 2026-09-03): one `###` heading, bold lead-in paragraphs for
  sections (never numbered/`###` section headings), Developer's Testing inside Verification, cc after a
  divider. A review posted in the wrong shape is edited **in place** (`addCommentToJiraIssue` with
  `commentId`), never re-posted as a second comment.
- **Label** the ticket `JIRA-AI-OwnerReview` (additively) when the disposition routes ownership
  elsewhere.
- **Wrap every object, branch and path name in inline `code`** (operator 2026-09-05). Jira renders
  paired underscores as italics and the underscores are then *gone* from the stored comment,
  surviving only as an `em` mark — measured on a real handoff line, where `i21_Liquibase` and
  `26.3DevCTRMFeatures_DunkinBrands_IC-29794` both arrived stripped. It corrupts some names and not
  others, so it hides. This bites hardest when a **developer pastes the draft themselves**, which is
  the expected workflow: paste the prose, but let the identifiers carry their code marks.
- **Grade the four claims separately, and grade the CHOICE of fix** (operator 2026-09-05). A single
  RCA verdict is ticket-level and cannot express the corpus's commonest outcome — a true mechanism
  carrying a wrong remedy. Say which claim failed, and say why the fix was inadequate using the five
  named shapes. A fix that works and whose run never enumerated an alternative is *not enumerated*,
  because being right is not evidence the question was asked.
- **Read `RUN-GATES` against the prose, every time.** It costs one line and it is the only check that
  catches a gate the run recorded and then contradicted. A disagreement between a token and the
  comment above it is a finding about the run, and it is classified `not-followed` — which produces
  no runbook rule, because the gate already existed.
- **Route feedback by shape, not by how it was phrased** (operator 2026-09-05). If it cannot be
  stated without naming a specific object, table, screen or module, it is content: it belongs in
  Section 2 or 3 and never in Section 7. Seven of eight pieces of real feedback are this shape.
- **A runbook item names its failure mode and the gate it checked** — `no-gate`, `trigger-narrow`,
  `wrong-answer`, `mis-sequenced`, `not-followed`. `not-followed` produces no rule: the run had the
  gate and did not honour it, and a second rule fixes nothing. Cite gates as plain text, never as a
  link or a path.
- **This skill writes Jira and nothing else.** It never edits the runbook, never opens a branch,
  never touches a repository. A Section 7 item is a proposal the runbook owner adjudicates, and a
  correction to the analysis is prose on the ticket. Both are read by people, not applied by a
  machine.
