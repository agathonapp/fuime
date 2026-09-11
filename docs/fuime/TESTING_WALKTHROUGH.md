# Test everything — 15 minutes

How Rushmore (or anyone) exercises Fuime end-to-end **without real teens or
parents**. Stripe **test mode only**. The living checklist lives in the app —
do not treat this file as a second copy.

| If you want… | Open |
|---|---|
| The click-through | **`rake fuime:demo`** then **`/admin/demo`** |
| MoR sale → ledger (`stripe listen`) | `MOR_WEBHOOK_PASS.md` |
| Connect / cards / payouts against Stripe | `STRIPE_PASS.md` |
| Automated lock on the seed + checklist | `spec/services/fuime/demo_sandbox_spec.rb`, `spec/requests/fuime_demo_sandbox_smoke_spec.rb` |

## One command

```bash
# App running (Docker path from SETUP_NOTES.md)
docker compose up -d web

# Optional but needed for waitlist + first-sale:
#   WAITLIST_REDIS_URL=…          (or your local Redis)
#   FEATURE_MERCHANT_OF_RECORD=true

docker compose run --rm -e RAILS_ENV=development \
  -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rake fuime:demo
```

Bare metal: `rake fuime:demo`.

That **resets** the `demo+…@fuime.test` cast, **seeds** it, and prints every
mailbox, URL, and next click. Then:

1. Sign in as `demo+admin@fuime.test` (mint a code from the rake banner, or
   impersonate Ada if you already have an admin).
2. Open **`/admin/demo`**.
3. Work the numbered checklist. **Become** is the existing admin impersonate
   action — not a new login door. Use a minted code only when you want to
   test `/login` itself.

Reset later: `rake fuime:demo:reset` (this cast only) or the button on the page.

### Staging

Stripe must stay **test**. Set `FUIME_DEMO_SANDBOX=1` and
`FUIME_DEMO_CONFIRM=yes-seed-demo-cast`. The page and rake refuse if
`STRIPE_MODE=live`. Never seed against live keys.

### Cheat sheet

| Thing | Value |
|---|---|
| Test card | `4242 4242 4242 4242`, any future date, any CVC |
| Mailboxes | `demo+<role>@fuime.test` (`creation_method: demo`) |
| Live cohort code | `DEMOFOUNDERS` |
| Storefront | `/b/demo-lawn-care` |
| Listen | `POST /fuime/webhooks/stripe` — see `MOR_WEBHOOK_PASS.md` |

Maya (`script/seed_demo_business.rb`), playground, `fuime:stripe_pass`, and
`fuime:mor_webhook_pass` still exist for their slices. This sandbox is the
one command that fills **every** admin queue.

## What the checklist covers

Waitlist invite · parent accept (checkbox) · admin waive · solo admit ·
cohort auto-admit · operator vetting · MoR guest checkout → ledger ·
billing / Pro · guardian reminder / stale queue.

The titles, URLs, and “expect” strings are `Fuime::DemoSandbox::CHECKLIST_IDS`.
If a path rots, `rake fuime:demo:smoke` and the request spec go red.

## What this does not replace

- **Cards / Issuing / Connect payouts** — `rake fuime:stripe_pass:*` + `STRIPE_PASS.md`
- **School / playground ledger** — `rake fuime:seed_school` and
  `script/seed_playground_org.rb` (playground is fake money on purpose)
- **Maya cookies** — `script/seed_demo_business.rb` (food category; cannot
  sell under MoR's services/digital allowlist — use Demo Lawn Care)
- Live-mode anything. The sandbox will not seed if `STRIPE_MODE=live`.
