# The waitlist front door: plan

Drafted 2026-10-01 from a Q&A with the founder. Target: live **Thu 2026-10-08**.
When this ships, `BRIEF.md` gets a dated section recording what it supersedes
(see Build §4). Until then BRIEF.md still governs every page that isn't `/`.

## What was decided

| | Decision |
|---|---|
| Purpose | **Gate new signups.** New people join a list and are invited in batches. The current product stays behind a small *Log in* for existing sellers and parents. |
| Scope | `/` becomes one full-screen page with no scroll. The other pages go offline (files kept, not deleted) and unlock later. |
| Format | **Living background**: one full-bleed loop behind the headline and form, all visible at once. |
| Footage | **A montage of three worlds**: young people working, the night desk, money moving as abstract shapes. **AI-generated**, with code-drawn motion graphics on top. |
| Message | **One-line promise, "Earn it. Track it. Spend it."** No pricing, no how-it-works. |
| Brand | **New brand, same name.** Feel: *sharp & a bit weird* (reference: Arc / The Browser Company). Near-black ground with **one hot accent**. **Evolve the arch** mark. Flat colour, no gradients, no glass (standing rule). |
| Join form | Email + one tap for **"I am a…"**: starting something / parent / freelancer / school or programme. |
| After join | **Real position number + referral link** that moves you up. |
| Sound | Muted by default, with a toggle for an **original score**. |
| Build | In the current `site/`, on Render, reusing the tested waitlist capture. |

## Rules this page has to work inside

1. **No bank words until a partner bank signs.** That means bank, banking,
   neobank, checking, savings, deposits, insured, FDIC, and "your money is
   safe". Under state statutes (Cal. Fin. Code § 562; 205 ILCS 5/46 makes it a
   Class A misdemeanor) these are offences, not style choices
   (LEGAL_RESEARCH §4, §7). "Earn it. Track it. Spend it." passes as written.
   **"Financial platform" is fine today** (founder's call, 2026-10-01). It's
   the wording LEGAL_RESEARCH §7 and CLAUDE.md L5 recommend in place of the
   bank nouns, so it's the right word now and stays right after a bank signs.
   The day a contract is signed: add *"Banking services provided by X Bank,
   Member FDIC"*, run counsel review, and then the vocabulary opens up.
   **No card in the footage either**, until then. A debit card on screen implies
   the deposit product the words can't name.
2. **The disclosure stays on the one screen.** It's a small line at the bottom:
   *"fuime is a financial technology company, not a bank. fuime does not hold
   deposits and does not offer FDIC-insured products."* The guard specs check
   the substring `financial technology company, not a bank` case-sensitively.
   The "seller of record" sentence goes, because it stops being true.
3. **No gradient scrim, so the footage has to make room for the type.** Text
   over video is usually rescued with a dark gradient, and that's banned here.
   So every shot is generated with dark negative space where the headline sits
   (subject right, type left; on a phone the subject sits high and the type
   low), then graded to the palette. That goes into every generation prompt,
   not fixed afterwards.
4. **The gate shipped first, on 2026-10-01** (founder: "make sure the app
   itself doesn't allow signups"). This used to say "ship the gate and the
   page together". The dead end that rule guarded against is closed by the
   founder's other ask the same day: the current landing page carries the
   waitlist form (`#join`, source `home-waitlist`), and the app sends anyone
   without an account there. So every "Start your business" button on the
   site already ends at the list. **The new page must keep `id="join"` and the
   `[data-account-none]` note**, because the app links to both. Opening sign-ups
   again means setting `FUIME_SIGNUPS_OPEN: "true"` in `render.yaml`.
5. **The number is real.** It's a count from the store, with no seeded or padded
   figure. The brief already bans invented user counts, and a fake "#40,000" is
   an FTC problem.
6. **Minors get transactional email only (L7).** The list sends exactly two
   emails, *confirm your address* and *you're invited*. There are no "you moved
   up" nudges to anyone. Position lives on a status page they return to.
   Under-13s are asked to have a parent join for them (COPPA: an under-13's
   email isn't collected without consent).
7. **The chargeback page stays served, just unlinked.** Past buyers' statements
   say `Fuime* <venture>`, and card dispute windows run ~120 days past the last
   charge. Taking `/why-has-fuime-charged-me` down turns confused buyers into
   chargebacks fuime pays for. `/privacy` and `/terms` stay linked from the
   footer line, because a form that collects emails needs them.

## The screen

```
┌────────────────────────────────────────────────────────────┐
│ ⌒ fuime                                  Log in   ❚❚   🔈  │
│                                                            │
│   ░░░░░░░░░░ montage loop, full bleed, ~24s ░░░░░░░░░░░░    │
│                                                            │
│   Earn it.          ← each verb lights up while its        │
│   Track it.            world is on screen                  │
│   Spend it.                                                │
│   The financial platform for people who work for themselves.│
│                                                            │
│   [ you@email.com                 ] [ Join the list ]      │
│   I am:  starting something · a parent · freelance · school│
│                                                            │
│ fuime is a financial technology company, not a bank. …     │
│                                          Privacy · Terms   │
└────────────────────────────────────────────────────────────┘
```

After joining, the panel swaps in place: **"You're #1,204."**, the referral
link with a copy button, and one line on how referrals move you up. The ❚❚
pause control is required: WCAG 2.2.2 requires a pause control on anything that
autoplays longer than 5s.

**The loop, ~24s, cut to the score:**

| Time | World | Verb lit | What's on screen |
|---|---|---|---|
| 0–8s | Young people working | Earn it. | Golden-hour mowing, a camera on a shoot, a tutoring table, hands on decks. Quick cuts, every 2s. |
| 8–16s | The night desk | Track it. | Laptop, city window, numbers settling into a ledger drawn as motion graphics. |
| 16–24s | Money in motion | Spend it. | The arch mark and flat shapes in the palette moving. It lands back on the mark, so the loop seam is invisible. |

**Edge cases that break no-scroll pages:**
- Under ~560px tall (a landscape phone, a zoomed laptop), the page **scrolls**
  rather than clipping the form or the disclosure.
- On a phone, opening the keyboard must not cover the email field.
- `prefers-reduced-motion` and Save-Data get the poster still and no video.
- Phones get their own vertical 9:16 cut, not a crop of the 16:9.

**Weight:** poster AVIF ≤ 120KB, which together with the headline text is the LCP
(< 2.5s on 4G). Desktop loop ≤ 5MB (AV1 WebM + H.264 MP4); phone loop ≤ 3MB,
fetched after first paint. Score ≤ 600KB, fetched only when the toggle is pressed.

## The week

| Day | Work | You |
|---|---|---|
| **Thu 10/1 to Fri 10/2** | **Brand board**: 3 accent candidates on near-black, 2 type pairings (a characterful display face and a clean sans, Arc-weird not kid-app), 3 arch evolutions, motion feel (springy, precise), the headline set in each. Published as a page to pick from. | Pick one direction by Fri |
| Fri 10/2 to Sat 10/3 | **Footage**: shot list (3 worlds × 3–4 shots, each with the type zone built in), generate, select, grade, 16:9 and 9:16 cuts. | Approve the selects |
| Sat 10/3 to Mon 10/5 | **Build** (below): page, capture API, server allowlist, guards. | |
| Mon 10/5 | **Score**: original, cut to the loop's edits. Motion-graphic layer finished. | Listen once |
| Tue 10/6 to Wed 10/7 | **Verify**: screenshots at 390 / 768 / 1440 and a landscape phone, reduced motion, slow network shows the poster first. A real join → confirm email → referral moves the position. Keyboard-only join. | Click through the preview |
| **Thu 10/8** | **Ship**: page and gate in one deploy, then check on fuime.com itself. | Send the first invite batch |

## Build

1. **`site/index.html` rebuilt** as the one screen, with its own stylesheet holding
   the new brand's tokens. The old `style.css` stays for the offline pages.
   A small script handles the video, the pause and sound toggles, the form
   states and the referral view. Still no framework, no CDN, no build step.
2. **`site/api/waitlist.js` extended**, a deliberate infrastructure change the
   brief allows when tests pass and the **two-independent-sinks design stays**
   (the store fails and the address still reaches a human by mail). It adds
   `role`, a referral code per signup, `ref` on join, a double opt-in confirm
   link, and position from the store. **A referral only counts once the friend
   confirms their address**, otherwise fake emails farm the line. New tests
   cover each piece.
3. **`site/server.js`**: `PUBLIC_FILES` shrinks to `/`,
   `/why-has-fuime-charged-me` (unlinked), the referral route `/r/<code>` and
   the status page. `/login`, `/privacy` and `/terms` keep pointing at the app.
   The pages going offline stay on disk. `sitemap.xml` shrinks to match.
4. **Guards and the brief, changed on purpose in the same PR:**
   `copy-guard.mjs`, `spec/fuime_marketing_copy_spec.rb` and
   `server.test.mjs`. For `/`, the "primary CTA is `/get-started`" assertion
   becomes "primary action is the join form". `index.html` leaves the price-page
   lists (a teaser that quotes no price breaks no pricing rule). The
   queue-language bans don't need lifting, because nothing on this page says
   "early access" or "your turn". `BRIEF.md` gets a dated section listing what
   this supersedes on `/`: open signups, the MoR description, "motion is almost
   nothing", no video, the 1.2MB budget.
5. **Rails gate: done 2026-10-01** (`Fuime::Signups`; see
   `UPSTREAM_DIVERGENCE.md`). No public door makes an account while it's
   closed, existing users sign in as before, and invited people get through
   because every invite creates their account first. **Still to do with the
   referral work:** `invite_next` takes people in referral-adjusted order
   rather than oldest-first.

## Defaults I'll use unless you say otherwise

- **Referral reward**: each confirmed friend moves you up 10 places. Easy to
  change later because position is computed rather than stored.
- **Voice**: the current one carries over (specific, direct, a little angry,
  no exclamation marks or emoji). The brand board tests it against the new look.
- **Fonts**: if the new type isn't on the foundry the CSP already allows, it's
  self-hosted rather than loosening the CSP.

## Not mine to decide, and not on this page's critical path

- **Counsel on the neobank copy** the day a bank signs (LEGAL_RESEARCH §7: post-bank
  "banking" language is counsel-sign-off only).
- **Winding down MoR**: what existing sellers are told, and when the last
  MoR charge happens (that date starts the chargeback page's clock).
- **Invite cadence**: how many people per batch, and how often.
