# The density brief

Measured off paddle.com on 2026-09-14 — rendered at 1440×900, visible text only,
five pages. These are not preferences. They are the numbers the site is being
edited to.

## The targets

> **Recalibrated 2026-09-14, after the first cutting pass.** The first version
> of this table capped a whole section at 45 words, which counted the contents
> of a card grid against the same budget as the heading above it. Pages then
> lost rows for budget reasons rather than redundancy — `/api` ended up with a
> four-row band cut to two and a visibly empty dark space beneath it. Paddle's
> mean section is 39 words but its **densest is 130**, being ten cards of
> thirteen. The budget is now split between the prose that frames an object and
> the object itself, and collapsed `<details>` content does not count at all.

| | paddle.com | fuime, before | fuime, target |
|---|---|---|---|
| **Prose** per section (eyebrow + h2 + lead) | ~39 | 104–242 | **≤ 45** |
| **Total** visible per section | 39 mean, 130 max | 104–242 | **≤ 130** |
| Visible words per page | 325 home, 421–819 elsewhere | 803–1,455 | **≤ 420** |
| Collapsed FAQ answers | not counted (819 visible / 1,099 expanded) | — | **not counted** |
| Words above the fold | 34–84 (≈10% of the page) | ~120 | **≤ 45** |
| Headline words | 2–9, median 6 | 5–12 | **≤ 9** |
| Card / row blurb | **13 words** (91% ≤ 20) | 25–45 | **≤ 20** |
| Longest paragraph | 50 visible | 60+ | **≤ 40** |
| Objects per section | **1** (60 of 69 sections) | 1–4 | **1** |
| Body links (excl. nav/footer) | 8–19 | 20–40 | **≤ 20** |
| Measure | ~48ch | 46–62ch | **46–52ch** |

## The rules that produce those numbers

1. **One object per section.** A card grid, OR a table, OR a ruled list, OR an
   FAQ, OR a worked example, OR prose. Never two. On paddle.com a comparison
   table gets a whole section to itself with one heading above it and nothing
   else. Zero sections anywhere contain a table AND a card grid.

2. **A section is a heading plus one thing.** Eyebrow (2–5 words), `.h2` (one
   sentence, ≤9 words, ends in a full stop), optionally a `.lead` of ≤30 words
   that adds a fact the headline cannot carry, then the object. That is the
   entire budget.

3. **Cards get one sentence.** Median 13 words. A four-card grid is ~52 words
   total, not 180. If a card needs two sentences, the second one is usually the
   first one restated — cut it.

4. **Nothing is explained twice.** The single biggest source of bloat here is
   the same fact appearing in the lead, then the card, then the FAQ. Pick the
   one place it belongs.

5. **Cut qualifiers, not facts.** Every number, constraint and honest limit
   stays. What goes is the sentence explaining why the number is the number.
   `docs/AUTHORING.md` still binds in full — the forbidden claims, the
   verified-facts list, and the requirement that every page own a limit.

6. **Never delete a card, a row or an FAQ question to hit a number.** Cut
   because a thing is said twice, never because a budget is tight. A band of
   two rows where four belong reads as a broken layout and saves twenty words.
   If a section cannot fit, shorten its prose — not its object.

7. **The limit section stays, and gets shorter.** "Where this stops" is house
   style and it survives the cut as a ruled list of ≤13-word rows.

## How to check

```
node tools/density.mjs            # every page against the table above
node tools/density.mjs index.html # one page, section by section
```
