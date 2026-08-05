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

## Not proven

- **Cards.** `card_issuing` cannot even be requested until Stripe onboards the platform
  onto Issuing — sales-gated **even in test mode**. Blocked on a Stripe conversation,
  not on code. When activated: `PROFILE=cards_enabled rake fuime:stripe_pass:onboard`
  then the `card` / `authorize` / `freeze` tasks.
- **ToS on Stripe-collected profiles.** Only the account holder can accept, in the
  embedded component at `/:slug/payments/setup` (the platform API call is refused).
  The embedded page rendered for the first time today, against prod, for a school org.
- **Settlement.** The recorder posts the *pending* ledger line. The settled side is a
  separate webhook path, unexercised — venture balances stay $0 until it runs.
- **Webhooks end-to-end.** Everything here fed events to handlers directly. Live
  delivery needs `FUIME_STRIPE_WEBHOOK_SECRET` / `FUIME_STRIPE_CONNECT_WEBHOOK_SECRET`
  configured and a `stripe listen` (dev) or endpoint registration (prod). The
  stale-mirror payout failure shows what breaks without `account.updated` flowing.

## Bugs found by running (all fixed)

1. `StripeConnectedAccount#sync_from_stripe!` called `account.livemode` — no such field
   on v1 Accounts; crashed on the first account ever created.
2. `ConnectPaymentRecorder` is webhook-shaped (`new(event: <Stripe::Event>)#handle`);
   events *listed* from a connected account lack the `account` field that *delivered*
   events carry — the recorder keys venture lookup off it.
3. Local mirror staleness blocks payouts even when Stripe says `payouts_enabled=true`;
   production depends on `account.updated` to prevent this.
