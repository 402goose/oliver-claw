---
name: ship-report
description: Generate a weekly 'what we shipped' update email from journals, commits, and code for a broader executive/stakeholder audience. Aggregates activity into outcome-level themes, not a dev changelog.
---

# Ship Report

Turn a week of commits, journals, and code into a short, scannable email that an exec or partner can read in under 90 seconds and understand what the team actually delivered.

## When to Invoke

- User asks "what did we ship this week/past week/past N days"
- User asks for an update email / stakeholder report / exec summary
- User says "lobster beach visa" or similar shorthand for "the email format"

## Inputs — Gather All Four Before Writing

Run these in parallel. Do not skip any source — each one surfaces signal the others miss.

### 1. Git activity (the ground truth of what code changed)
```bash
git log --since='1 week ago' --pretty='%h %s' --all | head -80
git log --since='1 week ago' --stat --all | head -200   # which files
```

Filter out noise: `auto:` pre-compact saves, `session: end` markers, bot commits, merge commits. Keep the human-authored commits that describe actual features/fixes.

### 2. Journal entries (the narrative the team wrote as they worked)
```bash
find .tenet/journal -name '*.jsonl' -newer /tmp/.week-ago 2>/dev/null
# Or scan all recent journal entries
ls -t .tenet/journal/*.jsonl | head -5 | xargs -I{} tail -50 {}
```
Journal `type: feature` and `type: fix` entries are goldmine — they already have human-authored summaries. Use them verbatim when possible.

### 3. Code purpose headers (what each module *is*)
```bash
# Top of each file often has @purpose or a multi-line comment explaining what it does
grep -r '@purpose\|^#!/.*\n#.*—' --include='*.ts' --include='*.mjs' --include='*.sh' --include='*.py' -l
```
Read the first 10 lines of any file touched this week to get the module's self-described purpose.

### 4. Knowledge docs (the framing — why this work matters)
- `knowledge/VISION.md` — what this project is for
- `knowledge/ROADMAP.md` — where we said we were going
- `README.md` — the user-facing description

Use these for the "what it is" intro and for deciding which shipped items are strategically important vs incidental.

## Synthesize — Group Activity Into Outcome Themes

Raw commits are useless to an exec. Your job is aggregation.

**Aggregate rule:** 5-20 commits collapse to 1 outcome bullet. Ask "if a stakeholder asks what changed, what's the *thing* that got better?"

Good themes (outcome-level):
- "End-to-end generation pipeline shipped — brief in, deck out."
- "Self-evaluating pipeline — every run is graded on narrative arc, tone, data consistency."
- "Dual output format — browser HTML + editable PowerPoint side by side."

Bad themes (implementation-level, do NOT write these):
- "Added scripts/run.sh"
- "Fixed regex bug in compose.mjs line 32"
- "Refactored render.ts helper functions"

**Rule of thumb:** if the reader needs to know a filename, you're too low. If the reader would say "wait, what is that for?", go one level higher until the outcome stands alone.

## Output Format

Produce a markdown block the user can paste into email. Use this skeleton (adapt sections as relevant):

```markdown
## <Project> — <Week of Date>

**What it is:** One or two sentences. Plain English. No jargon. The outcome framing: *what does this let someone do?*

**What we shipped this past week:**

- **<Outcome name>.** One-sentence expansion. What it lets you do / what problem it solves.
- **<Outcome name>.** ...
- (5-7 bullets max; collapse if you have more)

**Quality signals:** (optional — only if you have real numbers)

| Metric | Value |
|---|---|
| ... | ... |

**Live uses / proof points:** (optional — customers, partners, use cases)
- ...

**Next week:**
- One-line forward-looking item
- One-line forward-looking item
```

Include a table of metrics only when you have real data (eval scores, latencies, adoption counts). Don't pad with vanity stats.

## Voice Guidelines

- Past tense for shipped work ("shipped", "ran", "caught"), present tense for what it is ("Dexter turns a brief into a deck").
- Short sentences. Executives skim.
- Specific outcomes, not abstract themes. "Shipped a line-chart archetype for growth curves" beats "improved data visualization."
- Include concrete numbers when available. "Scored 8.4/10" is tangible; "improved quality" is not.
- No apologies, no "we hope to", no hedging. Stakeholders want confidence.
- Never name internal files, functions, or line numbers.
- Never include commit hashes, PR numbers, or ticket IDs.

## After Generating

1. Show the user the markdown block.
2. Ask if they want to adjust voice, add/remove sections, or include specific people/stakeholders.
3. Record a journal entry: `tenet_journal_write` with `type: decision`, title "Generated ship-report for <week>", summary of key themes.

## Examples

### Input signal
- 38 commits (28 are auto-save / session-end noise)
- 5 journal entries tagged `type: feature`, 2 `type: fix`
- README says the project is "a composable deck generation engine"
- Commits include: new renderer archetype, eval framework, pipeline script, an infra bug caught by the eval itself

### Output section
```
**What we shipped this past week:**

- **End-to-end pipeline.** One command turns a brief into a rendered deck. No hand-authoring.
- **20 slide archetypes.** Covers every pattern a board deck needs — covers, data-flow, roadmap gantts, comparison tables, charts.
- **Self-evaluating.** Every run is graded 0-10 on narrative arc, tone, data, audience fit, and visual continuity.
- **The eval caught its own infrastructure bug.** A screenshot-dir collision was silently contaminating scores; the pattern miner surfaced it automatically.
```

## Anti-Patterns

- **Don't enumerate commits.** Nobody wants `- fix: bump version to 1.2.3`.
- **Don't list every file touched.** "Touched 40 files" is not a shipped thing.
- **Don't bury the lede.** The biggest outcome goes first, not last.
- **Don't report what's in progress as shipped.** If it's not merged/working end-to-end, it goes in "Next week."
- **Don't embed internal bugs in the summary.** "Fixed a NaN parseFloat" has no place in an exec email. Unless the bug itself is the outcome (e.g., "caught its own eval contamination"), exclude it.
- **Don't skip journals.** If the journal says `"shipped X with Y behavior"`, that's the gold — use the team's words, not your reconstruction from git log.
