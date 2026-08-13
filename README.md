<div align="center">
  <h1>Fuime</h1>
  <p><strong>The financial home for teen-run businesses.</strong></p>
</div>
<br>

Fuime gives teens (13-17) everything they need to run a real business: a payment account their parent owns and signs for, clean books, tax tracking, and a path to their own LLC at 18.

## What is Fuime?

Teens under 18 can't open business accounts or sign contracts. Fuime solves this by providing:

- **A real payment account** — opened and owned by a parent or guardian, who is the legal signer
- **Clean books** — every transaction tracked and organized
- **Tax tracking** — know when you cross the $400 IRS self-employment threshold
- **Graduation path** — export to your own LLC when you turn 18

## How the money works

This is the part worth being precise about, because it constrains most of the code.

Each venture gets **its own Stripe connected account, owned by the guardian** — not a
sub-balance of a Fuime account. Customers pay that account directly; Fuime takes its cut
as a Connect `application_fee_amount` on the charge, and payouts go to the family's own
bank. **Fuime is never in the flow of funds and holds no customer money.** A pooled model
where Fuime received payments and credited ventures internally would be unlicensed money
transmission, so it exists only as a test-mode simulator
(`Fuime::PaymentWebhookHandler`, which refuses live events outright).

The guardian never opens stripe.com. Connected accounts are created with no Stripe
Dashboard, and onboarding, account management, payouts and tax documents are all mounted
inside Fuime as Stripe embedded components — see
[docs/fuime/EMBEDDED_CONNECT.md](/docs/fuime/EMBEDDED_CONNECT.md).

Everything runs against **Stripe test mode by default, including in production**.

Fuime is a financial technology company, not a bank. Fuime does not hold deposits and does
not offer FDIC-insured products.

## Built on HCB

Fuime is a fork of [HCB](https://github.com/hackclub/hcb) by [Hack Club](https://hackclub.com), the open-source fiscal sponsorship platform that has processed millions of dollars for teen nonprofits since 2018. We've repurposed it from nonprofit fiscal sponsorship to teen business banking.

**HCB's battle-tested infrastructure powers Fuime:**
- The same ledger engine that tracks millions in nonprofit funds
- The same receipt management and transparency features

What does **not** carry over is HCB's custody model. HCB works because a 501(c)(3) legally
owns every dollar it holds, which is what lets it pool funds and issue cards against one
platform balance. A for-profit cannot copy that, so Fuime replaced the pooled account with
guardian-owned Stripe connected accounts. Card issuing is off by default for the same
reason and is gated behind a per-venture flag.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/agathonapp/fuime.git
cd fuime

# Using Docker (recommended)
./docker_dev_setup.sh

# Or follow dev-docs/development.md for other options
```

## Documentation

- [Development Setup](/dev-docs/development.md)
- [Fuime Operating Guide](/CLAUDE.md)
- [Hackathon Spec](/FUIME_HACKATHON_SPEC.md)

## License

Fuime is open source under the [AGPL-3.0 license](LICENSE), the same license as HCB.

---

<div align="center">
  <p>
    <strong>Fuime is a fork of <a href="https://github.com/hackclub/hcb">HCB</a> by <a href="https://hackclub.com">Hack Club</a>.</strong>
    <br>
    Thank you to the Hack Club team for open-sourcing HCB.
  </p>
</div>
