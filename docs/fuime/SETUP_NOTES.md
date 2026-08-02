# Fuime — Setup Notes

## Handoff (most recent first)

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
