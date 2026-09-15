# Admin console map — every page, what backs it, and what to do with it

**2026-09-15.** Read-only audit of `fuime/m3-copy-sweep` at `2a25d5e49`, with
three other agents editing `config/routes.rb`, `app/models/admin/nav.rb` and
`app/views/admin/**` concurrently — so **line numbers here will drift**. Every
route quoted below is quoted verbatim; match on the text, not the number. No
product code was changed by this audit. The only files it wrote are this one and
one row in `README.md`.

**The reader this is written for:** the founder, alone, maybe with one cofounder.
`/admin` is not staffed. It is not used by school staff, not by outside
operators, and there is no ops desk. That single fact decides most of §7: a queue
earns its place only if it makes *that one person* notice something they would
otherwise miss.

**Trust this for:** "which admin pages are real, which are inherited scenery,
and which line do I delete from `config/routes.rb`."

**Do not trust this for:** whether a module *should* come back (that is
`LEGAL_RESEARCH.md` and `MOR_MIGRATION_PLAN.md`), or for the money model itself.
Fuime is **merchant of record**. Stripe Connect is off the table. That supersedes
`EMBEDDED_CONNECT.md` wherever the two disagree, and it supersedes
`ADMIN_OPS_QUEUES.md` §2 completely — see §7 below.

**Method.** `rails routes` run in Docker against a private test database, then
cross-referenced against `app/models/admin/nav.rb#sections`,
`app/helpers/static_pages_helper.rb#admin_queues` / `#admin_directories`, and
`app/javascript/components/command_bar/actions.js`. Every "permanently empty"
claim below is backed by a grep for the code that writes the model.

---

## 0. One-screen answer

There are **four** admin surfaces, not two, and they disagree with each other:

| Surface | File | What it shows |
|---|---|---|
| The left nav | `app/models/admin/nav.rb#sections` | 4 sections, 24 items. `spending` and `payroll` are defined but excluded. |
| The `/admin_tools` desk | `app/helpers/static_pages_helper.rb` | 10 queues + 16 directory links. |
| **The ⌘K command bar** | `app/javascript/components/command_bar/actions.js` | **39 admin destinations, untouched since upstream.** This is the leak. |
| Typing a URL | `config/routes.rb` | ~120 admin GETs. Everything above, plus the rest. |

The command bar is the surface nobody trimmed. It still offers *Donations*,
*Sponsors*, *Google Workspaces*, *Account numbers*, *Column statements*, *Check
deposits*, *Wise transfers*, *W9s*, *Employees*, *Bank accounts* — and two
literal Hack Club strings, `Applications (HCB)` and `HCB fees`
(`actions.js:718`, `actions.js:619`). It navigates by hardcoded URL string, so
removing a route turns those entries into 404s rather than crashes; they should
go with the routes.

Counting distinct human-visitable pages: **1 unreachable (a live bug), 42 live,
9 orphaned, 48 permanently empty.** The permanently-empty set is not "empty
today" — it is *unfillable*: every one is backed by a model whose only writers
are a Column, Increase, Plaid or Lob path Fuime does not have, or a module
`Fuime::DisabledModules` refuses.

---

## 1. UNREACHABLE — the live bug

One, and it is a clean one.

### `/admin/payroll` → 500

```ruby
get "payroll", to: "admin#payroll"        # config/routes.rb, in the admin collection block
```

There is **no `payroll` action** in `app/controllers/admin_controller.rb` (the
file has 100 public actions; `payroll` is not among them) and **no
`app/views/admin/payroll.html.erb`**. Rails raises
`AbstractController::ActionNotFound`. It has been reachable and broken since the
fork.

Nothing references `payroll_admin_index_path` — not the nav (the FUIME-DISABLED
`payroll` section points at `admin_payroll_positions_path` instead, `nav.rb:377`),
not `static_pages_helper.rb`, not the command bar, not a view. **Zero
references.** This is the single safest line in the file to delete.

Everything else in the nav resolves. I checked every badge lambda in
`Admin::Nav` against its model — `Fuime::Subscription.needs_attention`,
`Fuime::PayoutBatch.awaiting_approval` / `.awaiting_payment`,
`Guardianship.stale_pending`, `Fuime::Cohort.live`,
`Event.operator_vetting_unvetted`, `Admin::LedgerAudit.pending`,
`RawCsvTransaction.unhashed`, `BankFee.in_transit_or_pending`,
`Event::Application.under_review` — and every one exists. The nav renders on
every admin page, so a missing scope there would take the whole console down;
it does not.

---

## 2. The classification

Buckets, as commissioned:

- **LIVE** — real Fuime data flows here today.
- **ORPHANED** — reachable by URL, absent from the nav. An admin has to know the address.
- **EMPTY** — permanently empty. Nothing in this fork can create its records.
- **BUG** — in nav or routed, but broken.

"Nav" column: `N` = in `Admin::Nav#sections`, `T` = carded on `/admin_tools`,
`K` = in the ⌘K command bar, `—` = URL only.

### Ledger

| Page | Backed by | Nav | Bucket | Evidence |
|---|---|---|---|---|
| `/admin/ledger` | `CanonicalTransaction` | N T K | LIVE | Fed by `Fuime::PaymentWebhookHandler` → `CanonicalPendingTransaction` → settle. |
| `/admin/pending_ledger` | `CanonicalPendingTransaction` | N T K | LIVE | `payment_webhook_handler.rb:315`, `venture_ledger.rb:379`. |
| `/admin/:id/transaction` | `CanonicalTransaction` | — | LIVE | The mapping page. Its Wise/Wire columns are already commented out (`admin/transaction.html.erb:93-98`). |
| `/admin/hcb_codes` ("Fuime Codes") | `HcbCode` | N T K | LIVE | |
| `/admin/ledger_audits` `/:id` `/tasks` | `Admin::LedgerAudit` | N T K | LIVE | `Admin::LedgerAudit::GenerateJob`, weekly, `schedule.yml`. |
| `/admin/unknown_merchants` | Rails cache over `RawStripeTransaction` | N K | LIVE | Only meaningful with Issuing traffic; Issuing is test-mode-only. |
| `/admin/raw_transactions` | `RawCsvTransaction` | N T K | LIVE (empty in practice) | Only writers: `TransactionEngine::RawCsvTransactionService::Import` (reads CSVs off a bank statement Fuime does not have) and `admin#raw_transaction_create`, a hand-typed row. |
| `/admin/raw_transaction_new` + `raw_transaction_create` | same | — | ORPHANED | Linked only from `admin/raw_transactions.html.erb`. |
| `/admin/ledger_items` | `Ledger::Item` | — | ORPHANED | The rewritten ledger, killed by `Fuime::Features.new_ledger?` (off). Rows do exist — `admin#set_event` writes `Ledger::Mapping`. No nav entry, no card. |
| `/admin/raw_intrafi_transactions` + `_import` | `RawIntrafiTransaction` | K | ORPHANED + HCB-only | Intrafi is HCB's sweep network via Column. Nav entry already commented out (`nav.rb:203-208`). Only writer is a paste-a-CSV form on the page itself (`admin_controller.rb:275`). |
| `/admin/merchant_memo_check` | `RawStripeTransaction` | — | ORPHANED | Zero references anywhere. Issuing-memo debugging tool. |
| `/admin/nav`, `/admin_task_size`, `/admin/event_search`, `/admin/user_search` | — | — | LIVE (plumbing) | Turbo-frame and combobox endpoints, not pages. Keep. |

### Incoming money

| Page | Backed by | Nav | Bucket | Evidence |
|---|---|---|---|---|
| `/admin/subscriptions` + grant/revoke/cancel | `Fuime::Subscription` | N | LIVE | `Fuime::SubscriptionWebhookHandler`. This is ADMIN_OPS_QUEUES §4, built. |
| `/admin/payout_batches` + `/:id` + 4 writes | `Fuime::PayoutBatch` | N T | LIVE | `Fuime::GeneratePayoutBatchJob`, Wednesdays 14:00 UTC. |
| `/admin/invoices`, `/admin/:id/invoice_process`, `invoice_mark_paid` | `Invoice` | N T K | **EMPTY** | `"invoices"` is in `DISABLED_CONTROLLER_PREFIXES` — and for a money-*correctness* reason, not a product one: an invoice payment writes a non-`fuime_pi_` memo, so `Fuime::PayablesLedger` never books the payable. See the comment at `disabled_modules.rb:79-99`. **The nav and `/admin_tools` still advertise Invoices.** That is the single most misleading row in the console. |
| `/admin/donations` | `Donation` | K | EMPTY | `"donations"` in `DISABLED_CONTROLLER_PREFIXES`. Nav entry already commented (`nav.rb:236-243`). |
| `/admin/recurring_donations` | `RecurringDonation` | K | EMPTY | Same. |
| `/admin/sponsors` | `Sponsor` | K | EMPTY | Sponsors exist only to be invoiced; invoices are off. |
| `/admin/check_deposits` `/:id` `submit` `reject` | `CheckDeposit` | K | EMPTY | `"check_deposits"` in `SPONSOR_BANKING_CONTROLLER_PREFIXES`; `FEATURE_SPONSOR_BANKING` is unset. Settlement is a Column path. |

### Organizations

| Page | Backed by | Nav | Bucket | Evidence |
|---|---|---|---|---|
| `/admin/applications` | `Event::Application` | N T K | LIVE | |
| `/admin/cohorts` `/:id` + create/archive | `Fuime::Cohort` | N T | LIVE | |
| `/admin/operator_vetting` + decide/category | `Event#operator_vetting_status` | N T | LIVE | |
| `/admin/guardianships` | `Guardianship` | N T | LIVE | ADMIN_OPS_QUEUES §3, built. |
| `/admin/events` ("Businesses") | `Event` | N T K | LIVE | |
| `/admin/event_new` + `event_create` | `Event` | — | ORPHANED | Linked from `admin/events.html.erb:34`. Fine as-is. |
| `/admin/balances` | `Event` | N T K | LIVE | |
| `/admin/:id/event_process`, `event_balance`, `event_raised`, `event_toggle_approved`, `event_reject` | `Event` | — | LIVE | Reached from the events list. |
| `/organizer_position_deletion_requests` | `OrganizerPositionDeletionRequest` | N T | LIVE | |
| `/admin/google_workspaces` + `verify_all` + 5 member routes | `GSuite` | K | EMPTY | `"g_suite"` in `DISABLED_CONTROLLER_PREFIXES`. Only writer is `GSuiteService::Create`, refused. Nav already commented (`nav.rb:352-359`). Six routes and a 180-line view for a Hack Club perk. |
| `/admin/account_numbers` | `Column::AccountNumber` | K | EMPTY | **Zero writers anywhere in `app/` or `lib/`.** Column issues these; Fuime has no Column relationship. |

### Misc

| Page | Backed by | Nav | Bucket | Evidence |
|---|---|---|---|---|
| `/admin/waitlist` + invite/invite_next | Redis roster | N | LIVE | |
| `/admin/demo` + 5 writes | seeded `User`s | N T | LIVE | Hidden when Stripe is live (`Fuime::DemoSandbox.enabled?`). |
| `/admin/playground` + 4 writes | `Fuime::Playground` | T | LIVE | |
| `/blazer`, `/flipper`, `/documents` | — | N T K | LIVE | |
| `/admin/users`, `/users/:id/admin` | `User` | N T K | LIVE | But see the note on `admin_details_*` below. |
| `/admin/emails`, `/admin/email`, `/admin/email_html` | `Ahoy::Message` | N K | LIVE | |
| `/admin/referral_programs` + 2 writes | `Referral::Program` | N K | LIVE | Created from the page itself. |
| `/admin/event_groups` + memberships + statement | `Event::Group` | N K | LIVE | Created from the page itself. |
| `/admin/active_teenagers_leaderboard` | `User.active_teenager` | N K | LIVE | |
| `/admin/new_teenagers_leaderboard` | — | N K | LIVE | Nav badge is hardcoded `0` (`nav.rb:522`). |
| `/admin/stripe_cards` | `StripeCard` | N K | LIVE (flagged) | `Fuime::Features.card_issuing_permitted?` is true only while `STRIPE_MODE=test`. |
| `/admin/bank_fees` ("Fuime Fees") | `BankFee` | N | **EMPTY** | Chain: `BankFeeService::Create` raises unless `event.fee_balance_v2_cents` is non-zero; `FeeEngine::Create` sets `reason = :revenue_waived` for every Fuime-keyed memo (`fee_engine/create.rb:82`), so the balance is always zero. **Fuime's actual 5% never appears here.** The page already carries a warning banner. |
| `/admin/fee_revenues` | `FeeRevenue` | N K | EMPTY | Only writer is `BankFeeService::Weekly` (`weekly.rb:14`), which iterates `BankFee`s that cannot exist. Books to Hack Club's HQ event, id 636. |
| `/admin/contracts` | `Contract` | N T K | EMPTY | Only writer is `OrganizerPositionInvite#send_contract`, which opens with `return nil unless event.plan.contract_available?` — and `contract_available?` is `contract_docuseal_template_id.present?`, which is nil for every Fuime plan (`event/plan.rb:113-126`: "no Fuime agreement exists yet"). |
| `/admin/bank_accounts` | `BankAccount` (Plaid) | K | EMPTY | HCB's *bank feed*, not Fuime's payout destination — that is `Fuime::PlaidLinkService`, a different path. Nav already commented (`nav.rb:443-449`). Also an L5 word in the label. |
| `/admin/column_statements` + summary report | `Column::Statement` | K | EMPTY | **Zero writers.** `Column::StatementJob` is still on `schedule.yml` and calls a Column API Fuime has no key for. Nav already commented (`nav.rb:462-468`). |
| `/admin/stripe_card_personalization_designs` + `_new` + `_create` | `StripeCard::PersonalizationDesign` | K | ORPHANED | Physical-card artwork. Nav commented (`nav.rb:481-488`). Cards are the flagged virtual feature; physical is not on any roadmap. |
| `/admin/hq_receipts` | `User` via `Event.omitted` | — | ORPHANED + HCB-only | Title is literally `RECEIPTS FOR HQ EMPLOYEES`. "HQ" is Hack Club HQ. **Zero references.** |
| `/audit` | `Audits1984` console | — | ORPHANED | Not in nav, not carded. |
| `/bookkeeping` | `Event` | T | LIVE | |
| `/negative_events` | `Event` | T | LIVE | |
| `/my_ip` | — | — | ORPHANED (harmless) | JSON utility. |
| `/admin_search` → `/admin/users` | — | T | LIVE | Redirect only. |

### The spending desk — `Admin::Nav#spending`, excluded from `sections`

Not in the nav; **all of it reachable by URL**, and all of it in the ⌘K bar.

| Page | Backed by | Bucket | Evidence |
|---|---|---|---|
| `/admin/ach` + `ach_start_approval` + `ach_approve` / `ach_send_realtime` / `ach_reject` | `AchTransfer` | EMPTY | `"ach_transfers"` in `SPONSOR_BANKING_CONTROLLER_PREFIXES`. Origination and settlement are both Column (`column/webhooks_controller.rb:79`). The approval view links to `dashboard.column.com` (`ach_start_approval.html.erb:15-17`). |
| `/admin/checks` | `Check` (Lob) | EMPTY | **Zero writers anywhere.** This is the dead pre-Increase check model; it is not even the one `/admin/increase_checks` shows. |
| `/admin/increase_checks` + `increase_check_process` | `IncreaseCheck` | EMPTY | `"increase_checks"` blocked. Writers are `increase_checks_controller`, `LegalEntity::PayoutMethod::Check` and `PayrollService::Nightly` — all refused or payroll-only. |
| `/admin/disbursements`, `disbursement_new`, `disbursement_process` / `_approve` / `_reject` | `Disbursement` | EMPTY | `"disbursements"` blocked. |
| `/admin/wires` + `wire_process` + `/set_wire/:id` | `Wire` | EMPTY | `"wires"` blocked. `wire_process.html.erb:15-17` deep-links to Column. |
| `/admin/wise_transfers` + `wise_transfer_process` + `/set_wise_transfer/:id` | `WiseTransfer` | EMPTY | `"wise_transfers"` blocked. |
| `/admin/paypal_transfers` + `paypal_transfer_process` + `/set_paypal_transfer/:id` | `PaypalTransfer` | EMPTY | ⚠️ `paypal_transfers` is **not** in any `DisabledModules` list, so `PaypalTransfersController#create` is open to a non-admin. Whether that is deliberate is worth a separate look; either way the admin queue is inherited scenery. |
| `/admin/reimbursements` | `Reimbursement::Report` | EMPTY (as of 2026-09-15) | Reimbursements were deliberately *not* disabled until today. A concurrent change adds them to `SPONSOR_BANKING_CONTROLLER_PREFIXES` with the correct reasoning — `Reimbursement::PayoutHolding#payout_transfer` resolves to one of the five rails above, so a report could be filed, approved, and never paid. |
| `/admin/payments` | `Payment` | EMPTY | Payroll/vendor payments. `Payroll::InvoicesController` is the only non-manual writer. |

### The payroll desk — `Admin::Nav#payroll`, excluded from `sections`

| Page | Backed by | Bucket | Evidence |
|---|---|---|---|
| `/admin/payroll` | — | **BUG** | §1. |
| `/admin/payroll_positions` + `reject` | `Payroll::Position` | EMPTY | HCB contractor payroll via Column. ⚠️ `reject_admin_payroll_position_path` is called from a **live founder-facing view**, `app/views/payroll/positions/show.html.erb:59,63`. See §4 Tier 3. |
| `/admin/legal_entities` | `LegalEntity` | EMPTY | Zero writers. |
| `/admin/tax_forms` | `Tax::Form` | EMPTY | Only writer is `LegalEntity#...tax_forms.create!` (`legal_entity.rb:101`) and `Tax::FormsController`, both TaxBandits/payroll. |
| `/admin/w9s` + `new` + `create` | `W9` | ORPHANED | An admin *can* hand-upload one (`admin/w9s_controller.rb:20`), so not strictly unfillable — but a W-9 is a contractor tax form and Fuime pays nobody as a contractor. |
| `/admin/employees` | `Employee` | EMPTY | Emburse-era. ⚠️ `employees_admin_index_path` is called from `employees_controller.rb:32,39,46`. See §4 Tier 2. |
| `/admin/employee_payments` | `Employee::Payment` | EMPTY | Zero writers outside `Employee::PaymentsController`. **Zero `_path` references.** |

### One more thing: the user admin page

`/users/:id/admin` is live and useful, but it carries ten `admin_details_*` tabs
(`config/routes.rb`, the `resources :users` member block), six of which are for
models in the EMPTY set: `admin_details_ach_transfers`,
`admin_details_check_deposits`, `admin_details_disbursements`,
`admin_details_emburse_cards`, `admin_details_increase_checks`,
`admin_details_lob_checks`, `admin_details_invoices`,
`admin_details_reimbursement_reports`. They are lazy turbo-frames, so they cost
a request each and always render nothing. Out of scope for the route sweep —
noted so it is not rediscovered.

---

## 3. HCB-only vocabulary an operator actually sees

This is the list of places where the console speaks Hack Club to a Fuime
operator. Variable names and internal class names are excluded (CLAUDE.md
Rule 6); this is copy on screen.

**Literal "HCB" / "Hack Club":**

| File:line | Text |
|---|---|
| `app/javascript/components/command_bar/actions.js:718` | `name: 'Applications (HCB)'` |
| `app/javascript/components/command_bar/actions.js:619` | `name: 'HCB fees'` |
| `app/views/admin/hq_receipts.html.erb:1` | `title "RECEIPTS FOR HQ EMPLOYEES"` — Hack Club HQ |
| `app/views/admin/fee_revenues.html.erb:7,28-29` | "That is Hack Club's own org, not Ninth Street Labs" / "books to Hack Club's HQ event (id 636)" — deliberate warning copy, correct to keep |
| `app/views/admin/bank_fees.html.erb:21,62` | "Legacy HCB mechanism" — deliberate warning copy |
| `app/views/admin/unknown_merchants.html.erb:3` | links to `github.com/hackclub/yellow_pages` |
| `app/models/canonical_transaction.rb:85` | `not_stripe_top_up` matches `'%Hack Club Bank Stripe Top%'` — not on screen, but it is why the "Unmapped ledger" badge is defined the way it is |

**Column (a bank Fuime has no relationship with), on screen with a deep link:**

| File:line | Text |
|---|---|
| `app/views/admin/ach_start_approval.html.erb:15-17` | `Open Column (…)` → `dashboard.column.com` |
| `app/views/admin/ach_start_approval.html.erb:191` | "Realtime transfers incur a $1 fee from Column, that will be covered by Fuime." |
| `app/views/admin/wire_process.html.erb:15-17` | `Open Column (…)` → `dashboard.column.com` |
| `app/views/admin/column_statements/index.html.erb:1` | `title "Column Statements"` |
| `app/views/admin/column_statements/index.html.erb:31` | "Bank Account Summary" |
| `app/javascript/components/command_bar/actions.js:635` | `name: 'Column statements'`, with `/icons/column.svg` |

**Increase / Intrafi / Lob:**

| File:line | Text |
|---|---|
| `app/views/admin/raw_intrafi_transactions.html.erb:1` | `title "Intrafi Transactions"` |
| `app/views/admin/increase_checks.html.erb:1` | `title "Checks"` — the page is `IncreaseCheck`; `increase_check_process` appears in the URL bar |
| `app/views/admin/checks.html.erb:1` | `title "Checks"` — a *second* page with the same title, for the dead Lob model |

**Donations / grants / fiscal sponsorship:**

| File:line | Text |
|---|---|
| `app/views/admin/donations.html.erb:1,32` | `title "Donations"`, "donations" |
| `app/views/admin/recurring_donations.html.erb:1` | `title "Recurring Donations"` |
| `app/views/admin/sponsors.html.erb:1` | `title "Sponsors"` |
| `app/views/admin/transaction.html.erb:152-157` | "Potential DonationPayouts to Map to" (guarded on a variable the controller no longer sets — dead but present) |
| `app/views/admin/users.html.erb:38,84-85` | a "Card Grants" column; `card_grants` is in `DISABLED_CONTROLLER_PREFIXES` |
| `app/javascript/components/command_bar/actions.js:472,480,496` | `Donations`, `Recurring donations`, `Sponsors` |

**G Suite:**

| File:line | Text |
|---|---|
| `app/views/admin/google_workspaces.html.erb:1,34` | `title "Google Workspaces"` |
| `app/views/admin/google_workspace_process.html.erb:1,17,152-180` | ~20 occurrences of "Google Workspace" across the revocation UI |
| `app/javascript/components/command_bar/actions.js:545` | `Google Workspaces` |

**L5 forbidden vocabulary ("bank"), in operator copy:**

| File:line | Text |
|---|---|
| `app/javascript/components/command_bar/actions.js:611` | `name: 'Bank accounts'`, `glyph="bank"` |
| `app/views/admin/bank_accounts.html.erb:1` | `title "Bank Accounts"` |
| `app/views/admin/column_statements/index.html.erb:31` | "Bank Account Summary" |

L5 governs *user-facing* copy and `/admin` is founder-only, so these are not a
regulatory exposure. They are listed because the same words in the same person's
head is how they end up in a tweet. The nav already renamed `BankFee` →
"Fuime Fees" for exactly this reason (`nav.rb:451`).

**Airtable / Slack:** clean. The only remaining mentions are FUIME-DISABLED
comments explaining what was removed (`event.rb:1581`, `events_controller.rb:630`,
`actions.js:713-716`).

---

## 4. Route removals — the exact list

Grouped so they apply in one pass. Every line is quoted verbatim from
`config/routes.rb` as of `2a25d5e49`; another agent is editing the file, so
**match on the text**. Line numbers are as-of-audit and will move.

Each group names the `_path` / `_url` helpers it retires and every file that
still calls one. That is the failure mode to avoid: a removed route whose helper
is still called raises `NoMethodError` at render time, which turns a cleanup
into a 500.

### Tier 1 — remove now. Nothing references these helpers.

Zero risk. Verified by grepping `app/`, `lib/` and `config/` for each helper.

```ruby
# In `resources :admin do collection do` — around lines 617, 691, 694, 698:
      get "payroll", to: "admin#payroll"
      get "hq_receipts", to: "admin#hq_receipts"
      get "employee_payments", to: "admin#employee_payments"
      get "merchant_memo_check", to: "admin#merchant_memo_check"
      get "account_numbers", to: "admin#account_numbers"

# Top-level, just after the `namespace :admin` block — around lines 782-784:
  post "set_paypal_transfer/:id", to: "admin#set_paypal_transfer", as: :set_paypal_transfer
  post "set_wire/:id", to: "admin#set_wire", as: :set_wire
  post "set_wise_transfer/:id", to: "admin#set_wise_transfer", as: :set_wise_transfer
```

Helper audit:

| Helper retired | Still referenced by |
|---|---|
| `payroll_admin_index_path` | **nothing** |
| `hq_receipts_admin_index_path` | **nothing** |
| `employee_payments_admin_index_path` | **nothing** (the ⌘K entry at `actions.js:570` is a hardcoded string → becomes a 404, not a crash) |
| `merchant_memo_check_admin_index_path` | **nothing** |
| `account_numbers_admin_index_path` | only `nav.rb:362`, inside an already-commented-out block |
| `set_paypal_transfer_path` | **nothing** |
| `set_wire_path` | only `admin/transaction.html.erb:98`, inside an ERB **comment** |
| `set_wise_transfer_path` | only `admin/transaction.html.erb:81`, inside `<% if @suggested_wise_mapping %>` — and `admin_controller.rb:47-57` has the assignment commented out, so that block can never render |

`/admin/:id/transaction` keeps working. Verified: its only live form targets are
`set_event_path` and `event_search_admin_index_path`.

### Tier 2 — remove, but each has one named companion edit

Every model below is unfillable, so none of these routes can be reached by a real
record today. But each retires a helper that a live `.rb` or `.erb` still names.
Delete the route **and** the companion, in the same pass.

**2a. The spending desk.**

```ruby
# collection block:
      get "ach", to: "admin#ach"
      get "checks", to: "admin#checks"
      get "increase_checks", to: "admin#increase_checks"
      get "reimbursements", to: "admin#reimbursements"
      get "paypal_transfers", to: "admin#paypal_transfers"
      get "wires", to: "admin#wires"
      get "wise_transfers", to: "admin#wise_transfers"
      get "disbursements", to: "admin#disbursements"
      get "disbursement_new", to: "admin#disbursement_new"

# member block:
      get "ach_start_approval", to: "admin#ach_start_approval"
      post "ach_approve", to: "admin#ach_approve"
      post "ach_send_realtime", to: "admin#ach_send_realtime"
      post "ach_reject", to: "admin#ach_reject"
      get "disbursement_process", to: "admin#disbursement_process"
      post "disbursement_approve", to: "admin#disbursement_approve"
      post "disbursement_reject", to: "admin#disbursement_reject"
      get "increase_check_process", to: "admin#increase_check_process"
      get "paypal_transfer_process", to: "admin#paypal_transfer_process"
      get "wire_process", to: "admin#wire_process"
      get "wise_transfer_process", to: "admin#wise_transfer_process"

# namespace :admin block:
    resources :payments, only: [:index]
    resources :check_deposits, only: [:index, :show] do
      post "submit", on: :member
      post "reject", on: :member
    end
```

Companions — every live file that names a retired helper:

| Helper | Live callers to fix |
|---|---|
| `ach_start_approval_admin_url/_path` | `app/mailers/admin_mailer.rb:37`; `app/controllers/ach_transfers_controller.rb:85`; `app/controllers/admin_controller.rb:609,611,613,622` (the last four go with the actions) |
| `increase_check_process_admin_url/_path` | `app/mailers/admin_mailer.rb:48`; `app/controllers/increase_checks_controller.rb:51,54,56,66`; **`app/views/hcb_codes/transaction_types/_increase_check.html.erb:126`** |
| `disbursement_process_admin_url/_path` | `app/mailers/admin_mailer.rb:70`; `app/controllers/admin_controller.rb:650,653,663,666`; **`app/views/hcb_codes/transaction_types/_disbursement.html.erb:145`** |
| `disbursements_admin_index_path` | `app/controllers/disbursements_controller.rb:157,238`; `app/views/disbursements/show.html.erb:6` |
| `wire_process_admin_path` | `app/controllers/wires_controller.rb:49,52,64,66,90,93` (+4 more) |
| `wise_transfer_process_admin_path` | `app/controllers/wise_transfers_controller.rb:50,52,65,67,83,93` (+5 more) |
| `paypal_transfer_process_admin_path` | `app/controllers/paypal_transfers_controller.rb:42,45,55,63`; **`app/views/hcb_codes/transaction_types/_paypal_transfer.html.erb:53`** |
| `admin_check_deposit_url` | `app/mailers/admin_mailer.rb:78` |
| `admin_payments_path` | only `nav.rb:171` (dead `spending` method) and `admin/payments/index.html.erb:3` (the view being retired) |
| `ach_admin_index_path`, `checks_admin_index_path`, `increase_checks_admin_index_path`, `wires_admin_index_path`, `wise_transfers_admin_index_path`, `paypal_transfers_admin_index_path`, `reimbursements_admin_index_path`, `disbursement_new_admin_index_path`, `ach_approve_admin_path`, `ach_send_realtime_admin_path`, `ach_reject_admin_path`, `disbursement_approve_admin_path`, `disbursement_reject_admin_path`, `submit_admin_check_deposit_path`, `reject_admin_check_deposit_path` | only the `app/views/admin/**` pages being retired, plus `nav.rb`'s dead `spending` method — **self-consistent, no action needed** |

The three bolded rows are the real risk: `app/views/hcb_codes/transaction_types/`
partials render inside the **live** transaction drawer. They cannot render
today (no `IncreaseCheck`, `Disbursement` or `PaypalTransfer` can exist), but the
drawer is a page a founder opens every day, and the blast radius of being wrong
is the ledger. Change those three `button_to`s before removing the routes.

**2b. G Suite.**

```ruby
# collection block:
      get "google_workspaces", to: "admin#google_workspaces"
      post "google_workspaces_verify_all", to: "admin#google_workspaces_verify_all"

# member block:
      get "google_workspace_process", to: "admin#google_workspace_process"
      post "google_workspace_approve", to: "admin#google_workspace_approve"
      post "google_workspace_verify", to: "admin#google_workspace_verify"
      post "google_workspace_update", to: "admin#google_workspace_update"
      post "google_workspace_toggle_revocation_immunity", to: "admin#google_workspace_toggle_revocation_immunity"
```

| Helper | Live callers to fix |
|---|---|
| `google_workspaces_admin_index_path` | `app/controllers/g_suites_controller.rb:53,56` |
| `google_workspace_process_admin_path` | `app/controllers/g_suite/revocations_controller.rb:18`; `app/controllers/admin_controller.rb:1526,1534,1555,1557,1569` (go with the actions) |

**2c. Nonprofit money-in.**

```ruby
# collection block:
      get "donations", to: "admin#donations"
      get "recurring_donations", to: "admin#recurring_donations"
      get "sponsors", to: "admin#sponsors"
```

No live callers. `donations_admin_index_path` / `recurring_donations_admin_index_path`
/ `sponsors_admin_index_path` appear only in their own retired views and in
already-commented `nav.rb` lines (240, 246, 277). Effectively Tier 1; grouped
here only because the three belong together.

**2d. Column, Plaid, Intrafi.**

```ruby
# collection block:
      get "raw_intrafi_transactions", to: "admin#raw_intrafi_transactions"
      post "raw_intrafi_transactions_import", to: "admin#raw_intrafi_transactions_import"
      get "bank_accounts", to: "admin#bank_accounts"

# namespace :admin block:
    resources :column_statements, only: :index do
      get "bank_account_summary_report"
    end
```

| Helper | Live callers to fix |
|---|---|
| `bank_accounts_admin_index_path` | **`app/controllers/bank_accounts_controller.rb:44,52`** — `#index` is *only* a redirect to this path, and `#update` redirects back to it. `resources :bank_accounts` (≈ line 950) stays mounted, so removing the admin route without touching this controller leaves two reachable actions that raise. Either retire `resources :bank_accounts` too, or point those two redirects at `root_path`. |
| `raw_intrafi_transactions_admin_index_path` | `app/controllers/admin_controller.rb:288,294` (go with the action) |
| `admin_column_statements_path` | `app/controllers/admin/column_statements_controller.rb:19` (goes with the resource) |

**2e. Payroll (except the one Tier 3 line).**

```ruby
# namespace :admin block:
    resources :legal_entities, only: [:index]
    resources :tax_forms, only: [:index]
    resources :w9s, only: [:index, :new, :create]
```

| Helper | Live callers |
|---|---|
| `admin_legal_entities_path` | only `nav.rb:383` (dead `payroll` method) + its own view |
| `admin_tax_forms_path` | only `nav.rb:389` (dead) + its own view |
| `admin_w9s_path`, `new_admin_w9_path` | only their own views |

Also in this group, with the caveat below:

```ruby
      get "employees", to: "admin#employees"
```

`employees_admin_index_path` is called from
`app/controllers/employees_controller.rb:32,39,46`. `EmployeesController` is
**not** in any `DisabledModules` list and `resources :employees` is still mounted
(≈ line 1073), so those redirects are live code. Fix them (they can fall back to
`event_employees_path`, which line 39 already does for non-admins) or leave
`/admin/employees` alone.

### Tier 3 — do NOT remove

```ruby
    resources :payroll_positions, only: [:index] do
      post "reject", on: :member
    end
```

`reject_admin_payroll_position_path` is called from
**`app/views/payroll/positions/show.html.erb:59,63`** — a founder-facing page, on
routes that are still mounted (`resources :payroll_positions` inside the event
scope, ≈ line 1477). Removing the admin resource 500s that page for anyone who
reaches it. Retire the founder-facing payroll surface first, or leave this pair
in place; it is two routes and one index view.

```ruby
      get "email", to: "admin#email"
      get "email_html", to: "admin#email_html"
```

These look orphaned to a `_path` grep because they are reached via
`url_for(controller: "admin", action: "email")` — `app/views/admin/emails.html.erb:58`
and `app/views/admin/email.html.erb:13`. `/admin/emails` is live and useful.
**A helper grep will not find these. Keep both.**

```ruby
      get "invoices", to: "admin#invoices"
      get "invoice_process", ... / post "invoice_mark_paid", ...
```

Invoices are permanently empty and should eventually go — but `Invoice` is
different from the rest of the EMPTY set in one way that matters: rows *could*
exist from before the module was disabled, and an invoice is money someone was
asked to pay. Remove it in a second pass, after checking
`Invoice.count == 0` in production. Removing the nav and `/admin_tools` entries
(§6) fixes the misleading part immediately and costs nothing.

### Summary

**32 routes are safe to remove in one pass** (Tier 1's 8 plus Tier 2's 24, given
the companion edits). That retires ~20 pages and leaves the console at roughly
40 destinations, all of which do something.

---

## 5. `nav.rb` recommendations — exact

The nav is in better shape than the routes; it has been trimmed twice. Four
changes, in priority order.

**1. Remove the Invoices item.** `nav.rb:250-255`:

```ruby
          make_item(
            name: "Invoices",
            path: invoices_admin_index_path,
            count: ->{ Invoice.count },
            count_type: :records
          ),
```

Comment it out in the house style, with the reason from
`disabled_modules.rb:79-99`: invoices are off for money-correctness, and a nav
entry for the one money-in path that mis-books the payable is worse than no entry.
Companion: the `{ name: "Invoices", path: invoices_admin_index_path }` row in
`static_pages_helper.rb#admin_directories` under "Money".

**2. Retitle or retire "Fuime Fees".** `nav.rb:450-455`. The label is the
problem: it is `BankFee`, HCB's fiscal-sponsorship fee sweep, and it can never
hold a row (§2). Calling it "Fuime Fees" tells the reader this is where Fuime's
5% lives. It is not. Either rename it "Legacy HCB fees" to match the warning
banner already on the page, or drop the item and let the page stay URL-reachable.
Same argument for "Fee Revenues" at `nav.rb:456-461`.

**3. Delete the two dead section methods.** `Admin::Nav#spending`
(`nav.rb:129-177`) and `#payroll` (`nav.rb:371-395`) are excluded from `sections`
and therefore never called, but they are the only remaining references to
`ach_admin_index_path`, `increase_checks_admin_index_path`,
`disbursements_admin_index_path`, `wires_admin_index_path`,
`wise_transfers_admin_index_path`, `admin_payments_path`,
`admin_payroll_positions_path`, `admin_legal_entities_path` and
`admin_tax_forms_path`. Once §4 removes those routes, these methods become
landmines: they look like live code and would raise the moment anyone put them
back in `sections`. Replace both with the existing FUIME-DISABLED comment block
and no method body. (Rule 2 is satisfied — the record of what was removed lives
in that comment and in `UPSTREAM_DIVERGENCE.md`.)

**4. Leave everything else.** The remaining 22 items all resolve, all have valid
badge scopes, and all point at pages with real data. `spec/models/admin/nav_spec.rb`
is the canary for any change here.

**Not recommended:** adding a "Fuime Ops" section. See §7.

### And the surface nobody has touched

`app/javascript/components/command_bar/actions.js:359-720` is the fourth admin
surface and the one still speaking fluent HCB. It needs the same trim: delete the
entries for every route removed in §4, and fix `Applications (HCB)` (line 718)
and `HCB fees` (line 619) regardless. Because it navigates by hardcoded string,
a removed route degrades to a 404 rather than an exception — which is why this
has gone unnoticed, and why it will keep going unnoticed until someone deletes
the entries.

---

## 6. `/admin_tools` recommendations

Two rows, both small.

- Drop **Invoices** from `admin_directories["Money"]` — the companion to §5 item 1.
- **Raw transactions** is promoted as a *queue* with a live badge
  (`static_pages_helper.rb:63`, `RawCsvTransaction.unhashed.count`). It is a bank
  statement CSV importer for a bank Fuime does not have; the only way a row
  appears is if the founder types one in by hand. A badge in the "Needs you"
  strip is a claim that work is owed. Move it to `admin_directories`, or drop it.

The recent removal of the **Bank fees** queue card
(`static_pages_helper.rb:54-62`) is exactly right and is the model for both.

---

## 7. The ops queues, reassessed

`ADMIN_OPS_QUEUES.md` was written against a Connect platform with an ops desk.
Neither premise holds. Here is what survives.

### §1 — Payout requests: there is a real gap, and it is small

**Does `/admin/payout_batches` already cover it? Partly. One case is genuinely
invisible.**

`/admin/payout_batches` lists `Fuime::PayoutBatch` and `/admin/payout_batches/:id`
renders `@batch.payout_requests` — so a **batch line** that fails is visible, on
the page for its run (`admin_controller.rb:1153-1158`).

What is not visible is a **person-initiated** `PayoutRequest`. `PayoutRequest`
has two populations, separated by `payout_batch_id`:

```ruby
scope :person_initiated, -> { where(payout_batch_id: nil) }
scope :scheduled,        -> { where.not(payout_batch_id: nil) }
```

A `person_initiated` request has no batch, so it appears on **no admin page at
all**. Its only surface is the venture's own `/:event_slug/payouts`. If it
reaches `failed`, the founder learns about it when the family emails.

How does one reach `failed`? Two ways, and this is where the MoR reality bites:

1. `Fuime::ConnectPayoutRecorder#record_return` (`connect_payout_recorder.rb:140`)
   — reached only from `Fuime::ConnectWebhookHandler`, i.e. `/webhooks/stripe/connect`,
   i.e. a connected account. **Under MoR there are no connected accounts**
   (`Fuime::ProvisionConnectAccountJob` returns early when
   `merchant_of_record?`, `provision_connect_account_job.rb:46`; the whole
   `Fuime::PaymentSetupsController` is behind `retired_under_merchant_of_record`,
   line 75). So this path is dead.
2. `Fuime::PayoutService#approve_stripe_payout!` → `create_stripe_payout!`
   (`payout_service.rb:284-308`). And `#ensure_payouts_possible!` (line 268)
   explicitly refuses this under MoR: *"Under MoR a leftover connected account
   (from the unguarded provision job) must not become a live `Stripe::Payout`."*

**So today, under MoR, nothing can move a `PayoutRequest` into `failed`.**
The gap the spec describes is real in the code and unreachable in production.

That leaves one case that *is* reachable and *is* invisible: an **approved
`personal_transfer`** — `awaiting_settlement` — that nobody ever settles.
`PayoutRequest.awaiting_settlement` exists as a scope and is surfaced on the
school org, but for a family payout there is no page that answers "who has been
approved and not paid." That is money owed to a teenager, sitting in a state
with no watcher.

**Recommendation.** Do not build ADMIN_OPS_QUEUES §1 as specced. Build the
smaller thing: add a `PayoutRequest.person_initiated` block to the **existing**
`/admin/payout_batches` page — a short table above the runs, showing
`awaiting_settlement` and anything in `failed`, with a badge. It reuses the page
a founder already opens every Wednesday, which for an audience of one is the
whole point: a queue nobody visits is not a control. **Rough size: half a day** —
one scope, one partial, one badge, two request specs. A standalone page,
"mark paid" button, Stripe deep links and the rest of §1 is a week and would be
maintained by nobody.

### §2 — Connected accounts: obsolete

**Yes. Delete the section.**

`StripeConnectedAccount` is vestigial under MoR. Both creation paths are guarded
off (`ConnectOnboardingService#find_or_create_account!` is called only from
`provision_connect_account_job.rb:65` and `payment_setups_controller.rb:317`,
and both are refused when `merchant_of_record?`). No MoR money-in path reads it:
`Fuime::PaymentLinkService#create_mor_checkout_session` (`payment_link_service.rb:165`)
charges on the platform account.

A queue whose badge counts "ventures that cannot take money because Stripe
disabled their connected account" would, under MoR, count zero forever — while
implying that a venture's ability to sell depends on something it no longer
depends on. Under MoR a venture's ability to sell depends on
`Event#accepts_payments?` and operator vetting, and `/admin/operator_vetting`
already exists and is already in the nav.

The rows that *do* exist (created before the flag flipped) should be treated the
same as every other EMPTY page in §2 above: reachable by URL if anyone needs to
look, absent from every list.

### What this means for `ADMIN_OPS_QUEUES.md`

Its §3 and §4 shipped and are good. Its §1 needs the rewrite above. Its §2 should
be struck. Its framing sentence — *"ops' job shifts from 'move the money' to
'notice when Stripe/the family is stuck'"* — is still the right instinct, but
the noticing has to happen on a page the founder already opens, because there is
no one else to open it.
