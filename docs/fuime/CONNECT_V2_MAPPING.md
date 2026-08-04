# Connect Accounts V1 → V2 migration

**Status: gem upgraded and verified. The code rewrite has NOT been done.**

Every mapping below was verified empirically on 2026-08-04 by creating real test-mode
accounts on Fuime's own platform account (`acct_1TznaN2Uz4P3wrXO`), not read off
documentation. Probe accounts: `acct_1U0ra62Uz4VyYPFs`, `acct_1U0rzj2Uz4A6iAlm`.

## Why this migration is not optional

`POST /v1/accounts` is now refused for new Connect integrations:

> Stripe no longer recommends Accounts v1 for new Connect integrations. Create connected
> accounts with `POST /v2/core/accounts` instead. If your integration requires v1 account
> creation for a supported compatibility scenario, enable Accounts v1 support in the
> Dashboard.

So the options were a Dashboard compatibility flag or this migration. Migration was chosen
while **zero connected accounts exist**, which is the cheapest this decision will ever be.
It gets permanently more expensive the day the first family onboards, because V1
`controller` is create-only and existing accounts cannot be converted.

## The mapping

### Creating an account

| V1 | V2 |
|---|---|
| `controller.stripe_dashboard.type = "none"` | `dashboard: "none"` |
| `controller.losses.payments = "stripe"` | `defaults.responsibilities.losses_collector: "stripe"` |
| `controller.fees.payer = "account"` | `defaults.responsibilities.fees_collector: "stripe"` |
| `controller.requirement_collection` | **NOT WRITABLE.** Readable on retrieve, rejected on create ("Unknown field"). |
| `capabilities.card_payments` | `configuration.merchant.capabilities.card_payments.requested` |
| `capabilities.transfers` | `configuration.recipient.capabilities.stripe_balance.stripe_transfers.requested` |
| `capabilities.card_issuing` | **NO V2 EQUIVALENT.** "Unknown field" under both merchant and recipient. |
| — | `configuration.customer: {}` is new, and is what enables `customer_account:` subscriptions. |

The verified working `payments_only` body:

```json
{
  "display_name": "…", "contact_email": "…",
  "identity": { "country": "us" },
  "dashboard": "none",
  "defaults": { "responsibilities": { "fees_collector": "stripe", "losses_collector": "stripe" } },
  "configuration": {
    "customer": {},
    "merchant":  { "capabilities": { "card_payments": { "requested": true } } },
    "recipient": { "capabilities": { "stripe_balance": { "stripe_transfers": { "requested": true } } } }
  }
}
```

### Reading status

V2 is **richer** than V1 here, which is the one pleasant surprise.

| Fuime predicate | V1 source | V2 source |
|---|---|---|
| `ready_for_payments?` | `charges_enabled` | `configuration.merchant.capabilities.card_payments.status == "active"` |
| `ready_for_payouts?` | `payouts_enabled` | `configuration.recipient.capabilities.stripe_balance.payouts.status == "active"` |
| `requirements_outstanding?` | `requirements.currently_due` | `requirements.summary.minimum_deadline.status` in `currently_due`, `past_due` |
| *(no V1 equivalent)* | — | `requirements.entries[]`, each with `description`, `awaiting_action_from`, and `impact.restricts_capabilities[]` |

`requirements.entries[]` is a genuine upgrade: V1 gave dotted strings like
`individual.ssn_last_4` that `Fuime::RequirementCollectionService#describe_requirement`
had to translate by hand. V2 states who is being waited on and which capability is
blocked, so that translation table can shrink.

### Gotchas that cost time

- **`Stripe-Version` header is required** on raw HTTP calls. The SDK sets it; curl does not,
  and the error ("You did not provide an API version") does not mention V2.
- **`include` needs explicit indexes**: `include[0]=…&include[1]=…`. `include[]=` is rejected.
  Valid values: `configuration.customer`, `configuration.merchant`,
  `configuration.recipient`, `defaults`, `future_requirements`, `identity`, `requirements`.
- **`fees_collector` enum**: `application`, `application_custom`, `application_express`, `stripe`.
- **`dashboard` cannot be set** unless the account is configured as a merchant, or as a
  recipient with `stripe_balance.stripe_transfers`.
- Sub-objects are **omitted unless included**, and their absence is indistinguishable from
  "not ready" if you forget.

## ⚠️ The finding that needs a product decision

**`card_issuing` does not exist as a V2 capability.** Requesting it under either
`configuration.merchant` or `configuration.recipient` returns "Unknown field".

Everything built for cards on 2026-08-04 assumed the V1 shape, where `card_issuing` was a
requestable capability alongside `card_payments`. In V2 there is no such request, so:

- the `:cards_enabled` profile **cannot be expressed** as it currently stands;
- `losses.payments = application`, which V1 required for Issuing, maps to
  `losses_collector: "application"` — but with no way to request Issuing, taking on that
  loss liability buys nothing;
- `requirements_collector` being read-only means Fuime **cannot elect** to collect
  identity details itself, which is the entire premise of
  `Fuime::RequirementCollectionService` and the `/payments/verify` flow.

None of that is broken today, because cards are behind a default-off flag and no venture
has the profile. But it means cards are not a port — they are a re-design against however
Issuing is requested on V2 accounts, and that question should go to Stripe alongside the
three already outstanding in `LEGAL_RESEARCH.md`.

## What is done, and what is not

**Done and verified:**

- `stripe` 11.7.0 → 19.4.0. All 19 module-level V1 paths this app uses still exist; 93 HCB
  Stripe specs pass; the ledger engine is unaffected (its 5 failures are the pre-existing
  `ach_transfer` factory bug in `known-failures.md`).
- V2 account creation and V2 account links both confirmed working on Fuime's account.

**Not done. Each of these still speaks V1:**

1. `Fuime::ConnectOnboardingService` — `Stripe::Account.create` with `controller`.
2. `StripeConnectedAccount#sync_from_stripe!` and its predicates — mirrors `charges_enabled`
   and `payouts_enabled`, which V2 does not return. The existing jsonb columns
   (`capabilities`, `requirements`, `controller`) can absorb the V2 shapes without a
   migration, since there are no rows to convert.
3. `Fuime::ConnectWebhookHandler` — handles V1 `account.updated`, which **V2 accounts never
   emit**. They emit thin events (`v2.core.account[requirements].updated`), parsed with
   `client.parse_event_notification` (not `parse_thin_event`, which does not exist in Ruby).
   Until this is rewritten, status only refreshes when a guardian returns from onboarding.
4. `Fuime::PaymentSetupsController` — mints an embedded Account Session; V2 onboarding is
   an Account Link redirect.
5. `Fuime::RequirementCollectionService` — see the decision above.

The money paths (`PaymentLinkService`, `PayoutService`, the recorders) call V1 APIs with
`stripe_account:`, which is still correct for a V2 account and needs no change. That should
be confirmed against a real onboarded account rather than assumed.

**Recommended order:** 1 and 2 together (they are one change), then 3, then a real
end-to-end test-mode run, then decide on cards.
