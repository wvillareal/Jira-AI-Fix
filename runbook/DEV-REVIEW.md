# Dev Review — format and procedure

> **Version.** `2.0.0` · source copy — hand-distributed, not unpacked from a release zip
>
> Major, because the operating model inverted: the review is **posted**, not dropped in chat as a
> draft for approval (see **The prompt**). Anything built around the draft step no longer applies.

> **This is the shipped review, and it depends on no knowledge store.** It carries the full
> procedure — the posting discipline, the comment template, the pre-post check, the machine-read
> trailer and the runbook-improvement items — with none of the store's reading or writing.
> **Local merge note (2026-09-24):** knowledge-store / `DEV-REVIEW-KB` wiring is deferred while the
> store is still in development and testing — use **this** file. A future store-enabled variant
> (same review, plus `KB-CONSULTED` reading rules, a `kb=` trailer field and reconciliation) will
> diverge in exactly that one dimension; any improvement that is not about the store belongs in
> **both** when that variant lands.

A **Dev Review** is a judgement posted on a JIRA about work that already exists: it confirms or
overturns an RCA, accepts or replaces the proposed fix, and states what happens next. Every claim in
it is proven — by evidence the run produced, or by the developer's own reading and testing — and it
never introduces an unproven one.

**Run by the developer who did the verification, not by an automated sweep.** They analyse and test
the fix themselves, then invoke this skill with the verdict that testing produced. This skill turns
that judgement into a defensible comment; it does not form the judgement.

> **What the store would add, and why its absence costs this review nothing.** A store-enabled
> review can tell a run that read a record and ignored it from one that never looked, and it can
> promote a confirmed finding into a rule the next run reads. Neither is how *this* review reaches
> its verdict. The discipline that does the work — grading the run's claims one at a time, naming
> why a remedy fell short, grading the reviewer's own replacement, keeping content out of the
> runbook — is all here, and all of it survives with no base at all.

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

Post it. Everything else still waits for me: no owning-module ticket created,
no branch renamed, no file attached, no label or status changed.
```

Everything below is standing format — the developer supplies only the verdict and the testing lines.

**The review is POSTED, not drafted (operator 2026-09-14).** The developer has already done the
analysis and the testing; the draft-and-wait step made them approve their own judgement a second
time, and the wait was the slowest part of the loop. So the comment goes up in the same turn, and
the chat afterwards reports what went up and what is still outstanding on it.

**The post is the only thing authorized.** Everything else in the procedure still stops and asks:
creating an owning-module ticket, renaming a branch, attaching a file, and every label or status
change. Those change who owns work; a comment does not, and a comment can be repaired in place.

**Where an independent reading disagrees with the developer's verdict, say it IN the comment, not
before it.** The draft step used to be where that surfaced. It now surfaces as prose in Section 2 or
Section 3 — which is where it belonged anyway, because a disagreement settled in chat leaves no
trace on the ticket. Never quietly drop a finding because there is no longer a draft to raise it in.

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
prompt carry it, and Section 5 reports it. Never assume it, never invent it, and never leave it out
silently. A review that skips verification the developer actually performed throws away its best
evidence.

**A MISSING Section 5 HOLDS THE POST (operator 2026-09-14).** This is the one gate the
post-directly change does not lift. When lines 5 and 6 are absent, do not post. Ask once, in one
line, naming what would fill it: environment URL, build stamp, database, and a transaction whose
guard actually fires. Then wait.

**Silence holds the post; a stated `not tested` does not.** `not tested — <why>` is a complete answer
and the review posts on the verdict alone, with Section 5 omitted and `verification: not-tested` in
the trailer. What must never happen is a review going up because nobody was asked. The distinction is
the whole point: a developer who decided not to test has made a judgement the review can report; a
developer who was never asked has had one invented for them.

**The routing exception still applies.** A review confirming the defect is owned by another module
posts with no Section 5 and no ask — see the exception below. Nothing of ours was verified because
nothing of ours was fixed.

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
- **`RUN-GATES`** collects the gate verdicts the run recorded — symptom, repro, premise, origin,
  align, remedy, coverage, ownership, data cause. **Read it against the prose above it.** Every token is
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

## The comment template — the shape every review is filled into

**This block is the format authority for what the comment CONTAINS.** [AP-24953](https://irely.atlassian.net/browse/AP-24953?focusedCommentId=1275674)
remains the reference for how it *looks* on a rendered ticket; when the two disagree on wording, this
template governs the slots and AP-24953 governs the rendering. Copy it, fill it, delete what did not
fire. Two readers of this document must not be able to produce two differently-shaped reviews.

**How to read it.** `<angle brackets>` are placeholders — every one is replaced or its section is
deleted, and **a placeholder that reaches Jira is a defect in the review**. `[omit when …]` lines are
conditions on the section above them and are never posted. Identifiers keep their inline `code` marks.
Nothing in the template is a heading except the first line.

````
### Dev review - <short outcome, e.g. "RCA confirmed, fix accepted" | "RCA overturned, fix replaced" | "defect owned by CT">

**Bottom line.** <One or two sentences. No object names, no file paths, no gate ids, no counts.
Answer only: does the proposed fix work, and what happens next. This is the line a BA or a manager
reads, and it is the one question they actually asked.>

**RCA verdict - <correct | correct but incomplete | wrong>.** <The mechanism, short sentences, one
claim each. Put arithmetic on its own line rather than in prose.>

    <input>  ->  <result>        <what it should be>   -> <the discrepancy>

<Grade the four KNOWLEDGE-DRAFT claims, one line each, when the RCA carries that block:>

* C1 mechanism - <true | half | wrong | ungraded>. <why>
* C2 cause - <true | half | wrong | ungraded>. <why>
* C3 fix-pattern - <true | half | wrong | ungraded>. <why>
* C4 verified-by - <true | half | wrong | ungraded>. <why>

**What made the proposed fix look right.** [omit only on a clean pass]
<One sentence naming what the run actually observed that made its remedy correct on the evidence it
had. This is not a concession - it is what tells the runbook owner which gate to reach for, and a
verdict without it reads as carelessness and produces the wrong rule.>

**Solution.** <The correct solution, from verdict line 3. What was accepted, rejected or replaced,
where a replacement comes from, and what was deliberately excluded. Name the shape when a remedy
falls short: wrong layer | not durable | incomplete coverage | below standard | not enumerated.>

**The replacement, graded.** [omit when the proposed fix stood, or when no replacement code exists yet]
<The same four questions the Solution section put to the proposal, put to the replacement. The
reviewer wrote this one, which is exactly why it is asked here and not assumed.>

* Reachable on the reported symptom? <does the changed statement execute on the reported record - name
  the guard and both sides of it>
* Sites of the mechanism closed? <n of m, counted - never estimated>
* Dependencies the target module does not already carry? <none, or name them>
* Alternative enumerated? <the candidate considered and why this one won, or "not enumerated">

**Why this approach rather than the proposed one.** [omit when the fix stood]
<Concrete numbers, checked per account / per row - never on totals alone.>

**Verification.** [omit on a routing review, or when the developer did not test]
Environment `<URL>`, build `<stamp>`, database `<server or restore>` / `<database>`.
<State that the deployed object matches the reviewed code, or that it has since been reverted.>
<The observed result, and why the tested transaction is discriminating - the guard inputs and both
outcomes. A transaction whose guard does not fire proves nothing.>

**Developer's Testing:**

1. "<acceptance criterion, quoted from the ticket>" - <PASS | FAIL | NOT TESTED | NOT REPRODUCED>.
   <what was observed, or the blocker named>
2. <...>

Screenshots of `<transaction>` to be attached for verification support.

**Disposition.** <Branch, commit, patch artifact, who raises the PR, and what this supersedes. When
no routing ticket is created, say explicitly that the ticket is not being moved.>

**What needs to improve in the runbook.** [omit on a clean pass - RCA correct AND fix correct]
<The GENERAL failure in one short paragraph, stated as a property of the run's reasoning rather than
of the domain.>

1. <slug> - <no-gate | trigger-narrow | wrong-answer | mis-sequenced | not-followed>
   Gate:           <section id and rule id, or NONE - and when NONE, name what was searched to
                    establish it>
   Signature:      <one line, written to match the same failure on another ticket>
   Position:       <where in the sequence it belongs, and what it gates>
   Cost:           <what this check costs every future run>
   Counterfactual: <the observable this gate would have produced on THIS ticket>
   Supersedes:     <rule id, or nothing>

<Close with which single item would have caught the ticket dead, stated as an observable.>

---

cc <mention> <mention>

DEV-REVIEW: <JIRA> | rca=<correct|incomplete|wrong> | fix=<accepted|replaced|qualified>
claims: C1=<...> C2=<...> C3=<...> C4=<...>
remedy: <sound | wrong-layer | not-durable | incomplete-coverage | below-standard | not-enumerated>
premise: <confirmed|refuted|contested|unverified|not-reached>:<A1|A1b|A2|A3|A4|A5|self-evident|none> | agree=<yes|no>
verification: <tested|not-tested|routing> | pot=<attached|outstanding|n-a> | criteria=<passed>/<total>
objects: <dbo.uspX, File.js>
errors: <80236>
screen: <Module.view.Screen>
````

### Three slots that are new, and why each earns its place

- **`Bottom line` opens the comment**, before any verdict. The corpus reason: on SC-9264 the module
  lead asked *"Did AI fixed this or not?"* and a two-thousand-word review never answered it in a
  readable line. A dev review is read by people who will not parse a gate taxonomy, and the technical
  body is no less useful for having one plain sentence above it.
- **`What made the proposed fix look right`** carries the causal account that claim grading cannot.
  `C2 cause - wrong` is a verdict; it does not say what the run saw. On SC-9264 the account is one
  sentence — a nearly-exhausted contract is the only route by which an over-long number reaches that
  grid — and skipping it is why two of the three runbook items came out misfiled.
- **`The replacement, graded`** closes the document's one structural blind spot. Everywhere else the
  reviewer is the judge; here they are the author, and until this slot existed nobody graded their
  code. Measured on SC-9264: the replacement carried three of the five named shapes and the review
  named none of them.

### Pre-post check — four lines, before the comment goes up

Run these against the comment body, in order, immediately before the call that posts it. Each one is
a defect the corpus has actually produced:

1. **Every slot resolved** — no `<placeholder>` and no `[omit when …]` survives into the body.
2. **Trailer present**, after the cc divider, plain text, nothing following it. A review with no
   trailer cannot be read in bulk, which downstream is the same as not having been written.
3. **cc present**, naming the owners the disposition implicates, as `mention` nodes.
4. **Every token in the trailer traceable to prose above it** — `criteria=` is arithmetic over the
   Developer's Testing list, `remedy=` matches the shape named in Solution, `claims:` matches the four
   graded lines. A token that disagrees with the comment is a defect in the review.

---

## The trailer — Section 9

Every review ends with this block, **including a clean pass**. It is the review's machine-read
summary: plain text, after the cc divider, never rendered as a heading and never linked — a machine
reads it, for the same reason the fix runbook's own closing blocks are plain.

```
DEV-REVIEW: <JIRA> | rca=<correct|incomplete|wrong> | fix=<accepted|replaced|qualified>
claims: C1=<true|half|wrong|ungraded> C2=<…> C3=<…> C4=<…>
remedy: <sound | wrong-layer | not-durable | incomplete-coverage | below-standard | not-enumerated>
premise: <confirmed|refuted|contested|unverified|not-reached>:<A1|A1b|A2|A3|A4|A5|self-evident|none> | agree=<yes|no>
verification: <tested|not-tested|routing> | pot=<attached|outstanding|n-a> | criteria=<passed>/<total>
objects: <dbo.uspX, File.js>
errors: <80236>
screen: <Module.view.Screen>
```

**`premise:` grades the run's §2.4 verdict, and `agree=` is the only field here that is not a copy.**
The first half restates what the run recorded — its verdict and the rung that answered. The second
is the reviewer's own judgement of whether that verdict was right, and it is what makes an
overturned premise gradeable rather than merely logged. `not-reached` is correct and common: the
gate exits in one line on a self-evident symptom, and a review that pretends otherwise is inventing
a check nobody ran.

**`premise: refuted … agree=yes` is the most valuable single outcome here.** It means the run
concluded the reported behaviour was intended, a person checked that conclusion, and the two agree.
Say plainly in Section 5 what the intended behaviour is, because that sentence is the answer the
next ticket making the same claim needs — and a reviewer who agrees without stating it leaves the
next run to re-derive it from nothing.

**`claims:` grades `KNOWLEDGE-DRAFT` claim by claim**, in the same order the run stated them. All four
`ungraded` means the review re-derived nothing; say that in chat rather than posting it.

**`verification:` is the developer's own testing, in three tokens.** `tested` when they exercised the
change, `not-tested` with the reason carried in Section 5's absence, `routing` when the defect is
owned elsewhere and there was nothing here to verify. `pot=outstanding` is the normal state at
posting time — the testing happened, the captures are a human step and not yet attached. `criteria=`
counts the acceptance criteria observed to pass against the total the review graded; it is arithmetic
over the Developer's Testing list, never an estimate.

**Every token is copied from the review above it.** Like the fix run's own gate line, this block
computes nothing. A token disagreeing with the prose in the same comment is a defect in the review,
and the fix is the prose or the token — never a quiet edit of one to match the other after posting.

---

## Verification — the developer's manual testing, and the ticket's Proof of Testing

**This section is the verdict on an AI-authored change, and it is the ticket's POT.** The work under
review was written by a run; what makes this a judgement rather than a second opinion is that a
developer exercised that change by hand. Section 5 is where that testing is reported, and it is the
same artifact the code-fix task guide calls a Proof of Testing — one activity, one record, no second
document to produce.

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

- **Post the review; do not draft it (operator 2026-09-14).** The comment goes up in the same turn
  the verdict arrives. The post is the ONLY authorized action — an owning-module ticket, a branch
  rename, an attachment, and every label or status change still stop and ask.
- **One thing still holds the post: missing testing lines (operator 2026-09-14).** No lines 5 and 6
  and not a routing review → ask once and wait. A stated `not tested — <why>` is an answer and
  posts; silence is not. A review must never go up carrying a verification verdict nobody gave.
- **Emit the trailer on every review, including a clean pass.** A review with no Section 9 cannot be
  read in bulk, and a review nothing can read in bulk teaches nothing beyond its own ticket. Full
  shape in **The trailer — Section 9**.
- **Run the pre-post check before the comment goes up.** Four lines, fail-closed: no surviving
  placeholder, trailer present, cc present as `mention` nodes, and every trailer token traceable to
  the prose above it. Full shape in **Pre-post check — four lines, before the comment goes up**.
- **Section 5 is the Proof of Testing, not a summary of one.** The developer's manual testing of the
  AI-authored change is what the task guide means by POT. Report it here, grade each acceptance
  criterion honestly, and record whether the captures are attached or still outstanding. Never mark
  a criterion `PASS` the developer did not observe.
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
- **ADF, not markdown — because of MENTIONS specifically (corrected by measurement, 2026-09-11).**
  Posting markdown and inspecting the stored ADF on AP-23251: `[text](url)` **does** convert to a
  proper `link` mark (5 of 5 survived), but an `@name` or `[~accountid:…]` **does not** — it is
  escaped and stored as literal text, 0 mention nodes, so nobody is notified and the reader sees
  raw bracket syntax. So links are not the reason to reach for ADF; **mentions are the only reason,
  and they are reason enough** whenever a comment must notify someone. Use `mention` nodes, and
  resolve ids with `lookupJiraAccountId`.
- **Whichever format you post, the BODY SYNTAX must match it (R-COMMENT-MARKDOWN, measured on AP-23251, 2026-09-11).** The rule above settles *which* format a review uses; this one is about not mixing them up. `contentFormat: markdown` converts **Markdown** to ADF and passes **Jira wiki markup straight through as literal text** — so `h2.`, `{{mono}}`, `{code:sql}` and `|| header ||` render as visible garbage on a ticket the whole team reads. The trap is that both syntaxes look like markup to whoever is writing, and the parameter name is the only clue. In Markdown use `## heading`, `**bold**`, `` `inline` ``, triple-backtick fences and `-` bullets, and **prefer a bulleted list to a table**. Repair in place via `commentId`, as above.
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
  others, so it hides. This bites hardest when a **developer copies the review's prose onward** into
  a PR description or a chat: copy the prose, but let the identifiers carry their code marks.
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
