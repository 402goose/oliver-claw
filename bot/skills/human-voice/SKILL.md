---
name: human-voice
description: >-
  Strip AI-sounding patterns from writing and enforce human voice. Use when
  drafting or editing prose that must not read as AI-generated: exec comms,
  thought leadership, investor updates, blog posts, docs. Composable with
  /content, /geo-content, and other writing skills. Invoke with /human-voice
  [mode] where mode is "draft", "edit", or "audit".
argument-hint: "[draft|edit|audit] [topic or paste]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
---

# Human Voice

Write like a human. Not like a helpful assistant.

This skill enforces voice rules that make AI-generated prose indistinguishable from writing by a sharp, opinionated human. It is not a grammar checker. It is a pattern detector that catches the cadence, structure, and word choices that mark text as machine-written.

## Commands

```
/human-voice draft [topic]     # Write from scratch with human voice enforced
/human-voice edit [file|paste] # Rewrite existing text to remove AI patterns
/human-voice audit [file]      # Score text and flag AI tells without rewriting
```

## Modes

### draft

Write original prose on the given topic. Apply all rules below from the first word. Do not produce a draft and then clean it up. Write clean the first time.

### edit

Take existing text (file path or pasted content) and rewrite it. Preserve the meaning and structure. Strip every AI pattern. Return the rewritten version with a brief change log.

### audit

Read the text. Score it 0-100 on human-voice fidelity. Flag every violation with the line, the rule broken, and a suggested fix. Do not rewrite. Output format:

```
HUMAN VOICE AUDIT — [title or first 8 words]
Score: [N]/100

[line]: "[flagged text]"
  Rule: [rule name]
  Fix:  [suggested rewrite]

...

Summary: [1-2 sentences]
```

---

## The Rules

These are non-negotiable. Apply all of them, all of the time.

### 1. Mirrored Cadence (the master rule)

If the rhythm or structure across two or more sentences is mirrored, it sounds AI. Strip it. Humans do not write in tight parallel cadence. AI does, constantly. If you can hear a beat across consecutive sentences, rewrite one of them.

**Kill on sight:**

| Pattern | Example | Why it fails |
|---------|---------|-------------|
| Mirrored short sentences | "SEO clicks. GEO cites. ACO transacts." | Same length, same shape, noun-verb swaps |
| Parallel triplets | "Measure. Score. Create." | Rhythmic staccato, reads as tagline |
| X/Y contrast pairs | "SEO won the click. AEO won the citation." | Identical frame, different nouns |
| "X is not Y, X is Z" | "It's not a tool, it's a platform." | The most overused AI reframe |
| "X today, Y tomorrow" | "Manual today, automated tomorrow." | Temporal parallel, always AI |
| Sentence-fragment punchlines | "And that changes everything." | Ad copy posing as insight |

**How to test:** Read three consecutive sentences aloud. If they land with the same rhythm, rewrite the middle one to be longer, shorter, or structurally different. Break the beat.

### 2. Banned Constructions

Never use these. No exceptions.

- **"It's not just X but Y"** / **"more than just X"** — hedging filler
- **"The X is the new Y"** — unless the writer's own established phrase
- **"Everything is changing"** / **"The landscape is shifting"** — declarative AI-flourish openers that say nothing
- **Rhetorical question openers** — "What if your agent could pay for itself?" is an AI-essay tic. Open with the answer or the stake, not the question.
- **"Let's dive in"** / **"Let's break it down"** / **"Let's explore"** — assistant voice leaking
- **"In today's rapidly evolving..."** / **"In an era of..."** — throat-clearing
- **"Here's the thing"** / **"Here's why that matters"** — false intimacy
- **"Game-changer"** / **"Paradigm shift"** / **"Revolutionary"** — empty superlatives
- **"Leverage"** (as a verb) / **"Utilize"** / **"Facilitate"** — corp-speak for use, use, help
- **"Robust"** / **"Seamless"** / **"Cutting-edge"** — AI comfort words with no information content
- **"At the end of the day"** / **"When all is said and done"** — filler closers
- **"It goes without saying"** — then don't say it

### 3. Voice

- **State what something IS, not what it does for you.** "The API returns JSON" not "The API empowers you with structured data."
- **No marketing tone.** Do not sell. Describe.
- **Conversational, not formal.** Short fragments are fine. ("Still cheap to enter.")
- **The first concrete sentence carries the meaning.** No setup line before it. No "Before we get into that..." preamble.
- **Concrete nouns over abstractions.** "Reddit, GitHub, Stack Overflow" not "developer communities". "PostgreSQL on Fly" not "a modern database solution".
- **Prefer a concrete example over a definition.** When introducing a concept, show it working before explaining what it is.
- **Vary sentence length deliberately.** A short sentence after two long ones creates rhythm. Three sentences of similar length creates AI.
- **Use "you" sparingly.** Overuse of second person is a hallmark of AI writing trying to sound personal.

### 4. Structure

- **No more than three bullet points in a row without a prose sentence between groups.** Long bullet lists are an AI tell.
- **No heading-then-single-paragraph-then-heading pattern repeating more than twice.** Mix section lengths.
- **Bold is for emphasis, not decoration.** If more than 15% of a paragraph is bold, un-bold the least important parts.
- **Summaries must not be exhaustive.** A summary that covers every point is a table of contents. A good summary picks the two things that matter most.
- **Trailing summary paragraphs are usually unnecessary.** If the reader just read the content, they do not need you to restate it. Cut "In conclusion" and "To summarize" sections unless the piece is 2,000+ words.

### 5. Punctuation

- **No em dashes (—) anywhere.** Replace with periods, commas, parentheses, or colons. Em dashes are the single most statistically common AI punctuation tell.
- **Oxford comma.** Always.
- **"Whichever" when picking from a set.** Not "Whatever".
- **Periods over exclamation marks.** One exclamation mark per 1,000 words maximum.

### 6. Framing

- **Ask vs FYI.** If the text is informational, there is no ask paragraph. If there is an ask, state it plainly. ("What we need is..." / "The decision is whether to..."). Do not bury the ask in implication.
- **Lead with the conclusion.** Journalists call it inverted pyramid. State the point, then provide evidence. Do not build up to a reveal.
- **One idea per paragraph.** If a paragraph contains two ideas, split it.
- **Attribute claims.** "Revenue grew 40% (Q3 earnings)" not "Revenue grew significantly". Unattributed claims sound like marketing. Attributed claims sound like reporting.

---

## Composability

This skill is designed to layer on top of other writing skills:

```
/human-voice draft [topic]              # Standalone
/content thread [topic]                 # Then /human-voice edit on the output
/geo-content create [topic]             # Then /human-voice audit the result
```

When composed with other skills, human-voice rules override style guidance from the other skill wherever they conflict. The other skill provides structure and domain knowledge. This skill provides voice.

---

## Calibration

Every writer and context has a register. These rules enforce a default that works for:

- Executive communications
- Thought leadership and bylines
- Investor updates and board decks
- Technical blog posts
- Product announcements
- Internal strategy docs

For **casual social content** (tweets, short posts), relax rules 4 and 6. Keep rules 1, 2, 3, and 5.

For **formal/legal/compliance writing**, relax rule 3 (conversational voice) but keep everything else, especially rule 1 (cadence) and rule 5 (punctuation).

For **documentation and READMEs**, relax the bullet-list limit in rule 4. Technical docs need lists. Keep all other rules.

---

## Scoring Rubric (audit mode)

| Category | Weight | What it measures |
|----------|--------|-----------------|
| Cadence | 30 | No mirrored rhythm across consecutive sentences |
| Banned patterns | 25 | Zero instances of constructions from rules 1-2 |
| Voice | 20 | Concrete nouns, no marketing tone, example-first |
| Structure | 15 | Varied section lengths, no bullet avalanches |
| Punctuation | 10 | No em dashes, Oxford commas, restrained exclamation |

**90-100:** Reads human. Ship it.
**70-89:** Minor tells. One editing pass fixes it.
**50-69:** Multiple AI patterns. Needs rewrite of flagged sections.
**Below 50:** Structural AI voice. Full rewrite recommended.

---

## Quick Reference: The 12 Deadliest AI Tells

For fast editing passes, scan for these first:

1. Em dashes
2. Mirrored sentence pairs
3. "It's not X, it's Y"
4. Parallel triplets
5. Rhetorical question openers
6. "Here's the thing" / "Here's why"
7. "Robust" / "Seamless" / "Leverage"
8. Trailing summary paragraph
9. "In today's..." / "In an era of..." openers
10. Five or more consecutive bullets
11. "Game-changer" or equivalent superlative
12. Three paragraphs of identical length in a row
