# Fuime — Setup Notes

## Handoff (most recent first)

**2026-08-02 — Security keys, third attempt.** Two bugs, both hidden from the
suite. (1) `webauthn-ruby` only infers the RP ID when *exactly one* origin is
allowed; we listed two, so the RP ID was `nil` and every registration and
sign-in raised `WebAuthn::RpIdVerificationError` in production. `config.rp_id` is
now explicit. (2) The `use_two_factor_authentication` toggle lived inside the SMS
card, which is hidden without Twilio — so the "admins must enable 2FA" banner
pointed at a page with no way to enable it. It's now its own card, gated on
`User#second_factor_available?`. 157 auth-related examples green (this includes
fixing three stale `logins_controller_spec` assertions that still said "HCB").
**Any key registered on the deployed app before this must be re-registered** —
the RP ID is baked into a credential. Untested against physical hardware.

**2026-08-02 — Milestone 3 close-out.** Branch `fuime/m3-finish-brand-sweep`.
Finished the brand sweep and wrote the missing `docs/fuime/BRAND_STRINGS.md`
(read that before touching any `HCB`/`Hack Club` string — it classifies which
are branding, which are ledger data, and which are legally required to stay).
Disabled four surfaces that made claims Fuime cannot make — the fiscal
sponsorship and verification letters (PDFs on Hack Club letterhead with a real
employee's signature and EIN, one attesting an FDIC banking relationship), the
termination agreement, and the Perks page — and closed three "trap pages"
(Cards, Donations, Google Workspace) that showed a nav item, rendered fully,
then bounced the only action on them. Also killed a credentialed cross-origin
`fetch` to `blog.hcb.hackclub.com` that ran on every authenticated page load,
and fixed the admin header logo rendering full-size over the page.
**Verified against a `cafd73bba` baseline with assets built on both sides:
zero new failures in all three scopes.** Two measurement traps are documented
at the end of that UPSTREAM_DIVERGENCE entry — read them before trusting a
spec run; one of them makes an early-terminated run look green.

**2026-08-02 — Approval crash fixed; money-in wired up.** Branch
`fuime/m3-finish-brand-sweep`. Approving a teen-led application 500'd on a nil
contract (no DocuSeal template configured) — guarded, with a regression spec
proven to catch it. The storefront Pay button was hardcoded `disabled` and
nothing called `PaymentLinkService`; added `Fuime::CheckoutsController` +
`POST /b/:slug/pay`. The 4% fee now posts as a visible ledger line and rebates
proportionally on refunds/chargebacks (it previously lived only in Stripe
metadata, so a refund would have left a teen net negative by the fee).
**Gotcha that cost time:** several rspec containers can pile up against the one
`bank_test` database and deadlock each other — `docker ps`, stop the strays, then
`SELECT pg_terminate_backend(...)` before `rails db:schema:load`. Also note
`db:test:prepare` can exit 0 having left the schema unloaded; `db:schema:load`
is the reliable call.
Also fixed the other half of that outage: approved applications never became
businesses. `activate_event!` raised on a nil contract *inside* `with_lock`, so
`Event.create!` rolled back with it; `tags:` blew up on `params[:tags]` being nil
(a Ruby default does not apply to an explicit nil — this failed on ANY activation
with no tags selected, contract or not); and the only Activate button in the app
lived on the contract-party page, which does not exist without a contract.
**Next:** click the payment through against live test-mode Stripe
(`STRIPE__TEST__*` + `stripe listen`) — that is the one part not yet executed.
**Also note:** the dashboard card bug reported this session was reproduced on the
deployed Render app, which lags this branch. Check what is deployed before
debugging a symptom you cannot reproduce locally.

**2026-08-01 — Production hardening pass.** Branch `fuime/production-hardening`.
Closed every *engineering* blocker from `PRODUCTION_READINESS.md`: guardianship is
now an enforced control rather than a redirect, the webhook no longer double-posts
or fronts unsettled money, tax math uses net earnings, receipts go to S3, and
money-out modules are blocked at the request level. Added 68 specs (there were
zero). Remaining blockers are legal — identity verification, money transmission
structure, CPA review — and gate launch regardless of code.
**Before this branch helps anyone:** set the `S3__*` vars in Render and re-sync
the Blueprint, or the app will refuse to boot (by design). Then `rails db:migrate`.

---

## Running the app locally

The host toolchain on this machine does **not** work directly: Homebrew ships
Ruby 4.0.6 while the app pins 3.4.9, and no version manager (rbenv/mise/asdf) is
installed. `bundle install` exits 0 but installs nothing, so `bundle exec rspec`
fails with "command not found: rspec". Use Docker.

```bash
# One-time
cp .env.development.example .env.development   # then fill in the blanks
docker build -f Dockerfile -t fuime-dev .      # ~10 min first time

# Services
docker compose up -d db redis

# Database (first run, or after pulling new migrations)
docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rails db:test:prepare
docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rails db:migrate
```

### Running specs

```bash
docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rspec spec/models/guardianship_spec.rb
```

The full suite takes a long time. Run the Fuime-specific specs first:

```bash
... web bundle exec rspec \
  spec/models/guardianship_spec.rb \
  spec/models/user_guardianship_spec.rb \
  spec/services/fuime/ \
  spec/controllers/fuime/
```

## Gotchas hit

- **Build BOTH the JS bundle and the CSS before running controller or request
  specs.** They render real views, and `app/views/layouts/_head.html.erb` calls
  both `javascript_include_tag "bundle"` and `stylesheet_link_tag
  "application"`. In a fresh container these produce two different errors and
  ~115 failures that look exactly like a mass regression:

  - no JS → `ActionView::Template::Error: The asset "bundle.js" is not present
    in the asset pipeline`
  - no CSS → `LoadError: cannot load such file -- sassc`

  The `sassc` error is misleading. `sassc` is not in the Gemfile and is not
  meant to be: CSS is built by postcss (`yarn build:css`). Sprockets only
  reaches for its sassc processor because the prebuilt `application.css` is
  missing, so the fix is to build the CSS, not to add the gem.

  ```bash
  docker compose run --rm -e RAILS_ENV=test \
    -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
    web bash -c 'yarn install && yarn build && yarn build:css'   # ~5 min
  ```

  Both write to `app/assets/builds/` (`bundle.js`, `application.css`,
  `admin.css`, `mailer.css`), not `public/`. CI runs these as part of setup,
  so neither failure shows up there.

- **`DATABASE_URL` must be passed explicitly** to `docker compose run`. The
  compose file only sets `REDIS_URL`; without the override, Rails looks for a
  local socket and fails.
- **`db:test:prepare` does not run pending migrations.** It loads the schema,
  so newly added migrations still report `PendingMigrationError`. Run
  `db:migrate` after it.
- **`strong_migrations` blocks `add_reference ... foreign_key:`** in one step.
  Split into three migrations: add the column with
  `index: {algorithm: :concurrently}` and `disable_ddl_transaction!`, then
  `add_foreign_key ... validate: false`, then `validate_foreign_key`.
  See `20260801170000`–`170002`.
- **The user factory now sets a birthday** (adults by default). Fuime treats
  unknown age as a minor requiring a guardian, so a birthday-less factory user
  is barred from operating a business — correct in production, but it silently
  turns unrelated specs into tests of the guardianship gate. Use the `:minor`,
  `:minor_with_guardian`, and `:unknown_age` traits to test that gate on purpose.
- **Request specs don't have `create_session`.** `SessionSupport` uses
  `cookies.encrypted`, which needs `type: :controller` plus an explicit
  `include SessionSupport`. `spec/controllers/fuime/` follows this pattern.
- **The boot-time safety check raises in production/staging** on ephemeral
  Active Storage, a half-configured live Stripe key, or a hackclub.com host.
  That is intentional. `FUIME_SKIP_SAFETY_CHECK=true` bypasses it for one-off
  recovery work only — never for serving traffic.

## Seeded / real accounts

Production currently has three real user accounts plus `bank@hackclub.com`
(`User::SYSTEM_USER_ID` — required by the app, not a seed account) and 12 HCB
system orgs referenced by hardcoded id in `EventMappingEngine::EventIds`.
Do not delete either; see the "Production Data Reset" section of
`UPSTREAM_DIVERGENCE.md` for why and for the FK ordering that reset required.
