# Test everything — 15 minutes

How Rushmore (or anyone) exercises Fuime end-to-end **without real teens or
parents**. Stripe **test mode only**. Companion docs:

| If you want… | Open |
|---|---|
| This click-through | **this file** |
| MoR sale → ledger (`stripe listen`) | `MOR_WEBHOOK_PASS.md` |
| Connect / cards / payouts against Stripe | `STRIPE_PASS.md` |
| Automated path specs (no Stripe) | the list in §10 |

The demo sandbox seeds a known cast. It invents **no** Stripe money and
**refuses to run when Stripe is live**.

## 0. Spin up (~2 min)

```bash
# App running (Docker path from SETUP_NOTES.md)
docker compose up -d web

# Optional but needed for waitlist + first-sale:
#   WAITLIST_REDIS_URL=…          (or your local Redis)
#   FEATURE_MERCHANT_OF_RECORD=true

docker compose run --rm -e RAILS_ENV=development \
  -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rake fuime:demo:seed

docker compose run --rm -e RAILS_ENV=development \
  -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rake fuime:demo:status

docker compose run --rm -e RAILS_ENV=development \
  -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rake "fuime:demo:login_code[demo+admin@fuime.test]"
```

Bare metal: drop the `docker compose run … web` prefix.

Sign in at `/login` with `demo+admin@fuime.test` and the printed code.
Then open **`/admin/demo`** — roster, mint-a-code buttons, links to every queue.

Or impersonate any `demo+…` user from their `/users/:id/admin` page.

Reset (this cast only):

```bash
rake fuime:demo:reset
```

Staging: Stripe must stay test. Set `FUIME_DEMO_SANDBOX=1` and
`FUIME_DEMO_CONFIRM=yes-seed-demo-cast`. The page and rake refuse if
`STRIPE_MODE=live`.

### Cheat sheet

| Thing | Value |
|---|---|
| Test card | `4242 4242 4242 4242`, any future date, any CVC |
| Login codes | rake above, `/admin/demo`, or `/letter_opener` |
| Demo mailboxes | `demo+<role>@fuime.test` (`creation_method: demo`) |
| Live cohort code | `DEMOFOUNDERS` |

Maya (`maya.demo@fuime.com`) and the school seed still work; this sandbox is
the one command that fills **every** admin queue.

## 1. Waitlist → admin invite → login (~1 min)

1. `/admin/waitlist` — `demo+waitlist.fresh@fuime.test` is uninvited.
2. Invite (optional: attach `DEMOFOUNDERS`).
3. Open the letter_opener / mailed link **or** mint a code for
   `demo+waitlist.invited@fuime.test` (already invited) and sign in.
4. ✅ Expect: a waitlist user, onboarding, not a second auth system.

No Redis? Status warns. Set `WAITLIST_REDIS_URL` and re-seed.

## 2. Teen / guardian invite → parent accept (~2 min)

**Already seeded (click accept):**

1. Mint a code for `demo+parent.pending@fuime.test` and sign in.
2. Open `/admin/demo` (as admin) or the invite URL from
   `rake fuime:demo:status` / the guardianship row.
   Direct: sign in as the parent, then hit
   `/guardian/<invite_token>` (token is on the pending row).
3. Tick **I confirm I am the parent… 18 or older** and accept.
4. ✅ Expect: guardianship **active**. Teen `demo+teen.pending@fuime.test`
   can operate.

**From scratch (real signup):** log out, `/login` with a fresh
`kid+you@…` address, attest 13+, apply or `/guardian/new` with a parent
email, accept as that parent. Same checkbox.

## 3. Admin waive guardian (~1 min)

1. As admin, open `demo+teen.unguarded@fuime.test` → user admin.
2. Guardianship panel → **Waive guardian requirement** (optional reason).
3. ✅ Expect: warning badge; they can operate / you can activate without
   a parent accept. **Restore** puts the gate back.

## 4. Apply → admit: solo + cohort (~2 min)

**Solo (already in the queue):**

1. `/admin/applications` — **Demo Solo Lawn** is under review
   (`demo+teen.solo@fuime.test`, parent already accepted).
2. Approve, then activate (Applications → the application).
3. ✅ Expect: a venture; teen is manager.
   Counter-test from a *new* minor with no guardian: activate is refused
   under Connect; under MoR the wall is money-out, not activation.

**Cohort auto-admit:**

1. `/admin/cohorts` — live code **DEMOFOUNDERS**. Roster already has
   Demo Cohort Studio.
2. To watch auto-admit: sign in as a new 16-year-old, apply, type
   `DEMOFOUNDERS`. ✅ Expect: approved + venture + vetting recorded
   in the creator's name. Age floor / services-only still apply.

## 5. Operator vetting / activate storefront (~1 min)

1. `/admin/operator_vetting` — **Demo Window Wash** is unvetted.
2. Approve with a note.
3. ✅ Expect: they may sell only after this (and MoR / connected account
   / category). Do not turn vetting off.

**Demo Lawn Care** (`/demo-lawn-care`, storefront `/b/demo-lawn-care`) is
already vetted so you can skip to checkout.

## 6. Offer → MoR guest checkout → ledger (~3 min)

Needs `FEATURE_MERCHANT_OF_RECORD=true` (production already has this).
If status says the storefront cannot sell, set the flag and re-seed.

1. Guest: `/b/demo-lawn-care` → Buy, or
   `/pay/demo-lawn-care/front-and-back`.
2. Pay with `4242…` on Stripe Checkout.
3. Forward events (Fuime test account, **not** Hack Club Shop):

   ```bash
   rake fuime:mor_webhook_pass:listen
   # stripe listen --forward-to localhost:3000/fuime/webhooks/stripe \
   #   --events payment_intent.succeeded,checkout.session.completed,...
   ```

4. ✅ Expect: two pending lines (gross + platform fee) on the venture.
   Settle: `SLUG=demo-lawn-care rake fuime:mor_webhook_pass:settle`

Headless (no browser): `SLUG=demo-lawn-care rake fuime:mor_webhook_pass:charge`
— still test-mode only; see `MOR_WEBHOOK_PASS.md`.

## 7. Billing / Pro upgrade (~1 min)

1. `/my/billing` as `demo+teen.store@fuime.test` → pitch, parent's name,
   no Upgrade button.
2. `/my/billing` as `demo+parent.store@fuime.test` →
   **Upgrade — $19.99/mo**, take-rate stays 7%.
3. Pay with 4242. Platform webhook:
   `stripe listen --forward-to localhost:3000/fuime/webhooks/stripe`
4. ✅ Expect: welcome callout; second venture slot + API keys. Fee stays 7%.

## 8. Guardian reminders / stale queue (~1 min)

Already time-traveled:

| Who | State |
|---|---|
| `demo+parent.remind@fuime.test` | due for day-3 mail |
| `demo+parent.stale@fuime.test` | 7 days+, **Stale** tab |

```bash
rake fuime:demo:remind
# or from /admin/demo → Run reminder job
```

✅ Expect: reminder mail for Remy (same `invite_token`, clock not reset).
Stale row on `/admin/guardianships`. Resend mints a new token.

Console time-travel on any pending invite:

```ruby
g = Guardianship.pending.last
g.update!(invite_sent_at: 8.days.ago)                    # stale
g.update!(invite_sent_at: 3.days.ago - 1.hour,
          invite_day3_reminded_at: nil)
Fuime::GuardianInviteReminderJob.perform_now
```

## 9. Admin queues — one lap (~1 min)

From `/admin/demo` or the Organizations nav:

| Queue | Seeded row |
|---|---|
| Waitlist | `demo+waitlist.*@fuime.test` |
| Applications | Demo Solo Lawn |
| Cohorts | DEMOFOUNDERS |
| Operator vetting | Demo Window Wash |
| Guardian invites | Sky Stale (stale) + Pat Pending (all-pending) |
| Subscriptions | empty until you upgrade in §7 |

## 10. Automated proof (no live Stripe)

```bash
bundle exec rspec \
  spec/services/fuime/demo_sandbox_spec.rb \
  spec/requests/fuime_demo_sandbox_smoke_spec.rb \
  spec/requests/family_signup_flow_spec.rb \
  spec/requests/fuime_full_business_flow_spec.rb \
  spec/requests/fuime_waitlist_invite_spec.rb \
  spec/requests/fuime_waitlist_admin_spec.rb \
  spec/requests/fuime_cohorts_admin_spec.rb \
  spec/requests/fuime_operator_vetting_spec.rb \
  spec/requests/fuime_guardianships_admin_spec.rb \
  spec/requests/fuime_billing_spec.rb \
  spec/requests/fuime_mor_checkout_ledger_spec.rb
```

`rake fuime:demo:smoke` asserts the seeded rows after a local seed.

## What this does not replace

- **Cards / Issuing / Connect payouts** — `rake fuime:stripe_pass:*` + `STRIPE_PASS.md`
- **School / playground ledger** — `rake fuime:seed_school` and
  `script/seed_playground_org.rb` (playground is fake money on purpose)
- **Maya cookies** — `script/seed_demo_business.rb` (food category; cannot
  sell under MoR's services/digital allowlist — use Demo Lawn Care)
- Live-mode anything. The sandbox will not seed if `STRIPE_MODE=live`.
