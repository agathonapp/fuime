# The first Stripe pass — what is proven, and what is not (2026-08-05)

Until today, **nothing in this repo had ever talked to Stripe** in any mode; every
parameter shape was documentation-derived (see CLAUDE.md, docs/fuime/README.md).
`rake fuime:stripe_pass:*` changed that. This file is the scoreboard; the rake file's
comments carry the detail.

## Proven, in test mode, end to end

| Flow | Evidence |
|---|---|
| Connected account creation (`ConnectOnboardingService` shape) | `acct_1U1DpR2WL7iAvZOC` (payments_only), `acct_1U1EBOJvQ1BSjJCo` (harness) |
| API prefill on Stripe-collected profiles | everything accepted except `tos_acceptance` |
| KYC via `RequirementCollectionService` (application-collected) | requirements -> `[]`, charges+payouts enabled |
| Money in: direct charge on the connected account | `pi_3U1EHWJvQ1BSjJCo…` $25 succeeded |
| Ledger: Stripe event -> `ConnectPaymentRecorder#handle` -> canonical pipeline | `cpt#3` $25 mapped via `CanonicalPendingEventMapping` |
| Money out: `PayoutService` teen request -> guardian approve -> Stripe payout | `po_1U1EQ9JvQ1BSjJCo…` $10 |
| Settlement: `ConnectSettlementSweep` pending -> settled -> balance | venture balance $0.00 -> $25.00 on the harness account |
| Refunds: partial refund -> `charge.refunded` -> clamped reversal line -> settled | `re_3U1EHWJvQ1BSjJCo…` $5; balance held at $20 through settle, as the semantics require |

## Not proven

- **Cards.** `card_issuing` cannot even be requested until Stripe onboards the platform
  onto Issuing — sales-gated **even in test mode**. Blocked on a Stripe conversation,
  not on code. When activated: `PROFILE=cards_enabled rake fuime:stripe_pass:onboard`
  then the `card` / `authorize` / `freeze` tasks.
- **ToS on Stripe-collected profiles.** Only the account holder can accept, in the
  embedded component at `/:slug/payments/setup` (the platform API call is refused).
  The embedded page rendered for the first time today, against prod, for a school org.
- ~~Settlement~~ **Built and proven** (2026-08-05, same day): `Fuime::ConnectSettlementSweep`
  on a 30-minute schedule settles pendings whose balance transaction Stripe reports
  "available", via RawCsvTransaction -> the engine's own imports -> upstream Settle.
  Refund reversals settle when every refund balance transaction on the intent is
  available (exercised live the same day); dispute-kind reversals stay excluded
  until a dispute has been exercised for real.
- ~~Webhooks end-to-end~~ **Prod endpoints fixed and registered** (2026-08-05, by API):
  the one existing platform endpoint pointed at `fuime.com` — the marketing site,
  which 404s, and Stripe does not follow redirects — so every event ever sent had
  died there. Repointed to `app.fuime.com/fuime/webhooks/stripe` (same signing
  secret, so the Render var kept working). A Connect endpoint did not exist at
  all; created `app.fuime.com/fuime/webhooks/stripe/connect` with the 11 events
  the handlers cover, and installed `FUIME_STRIPE_CONNECT_WEBHOOK_SECRET` on
  fuime-web and fuime-worker. One trap for the future: an endpoint's signing
  secret is returned ONLY at creation — losing it means delete-and-recreate,
  which is exactly what happened to the first attempt. Remaining verification:
  a real delivery observed end-to-end in prod (the next embedded-ToS completion
  fires `account.updated` and should sync the mirror unattended).

## Bugs found by running (all fixed)

1. `StripeConnectedAccount#sync_from_stripe!` called `account.livemode` — no such field
   on v1 Accounts; crashed on the first account ever created.
2. `ConnectPaymentRecorder` is webhook-shaped (`new(event: <Stripe::Event>)#handle`);
   events *listed* from a connected account lack the `account` field that *delivered*
   events carry — the recorder keys venture lookup off it.
3. Local mirror staleness blocks payouts even when Stripe says `payouts_enabled=true`;
   production depends on `account.updated` to prevent this.
