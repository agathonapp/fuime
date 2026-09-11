<div align="center">
  <h1>Fuime</h1>
  <p><strong>The financial home for teen-run businesses.</strong></p>
</div>
<br>

Fuime gives teens (13-17) invoicing, books, and a storefront that takes payment: a parent
co-signs as the legal payee, the founder runs the venture day to day, and
Ninth Street Labs, LLC (Fuime) is the seller of record.

## What is Fuime?

Teens under 18 can't open business accounts or sign contracts. Fuime solves this by providing:

- **Invoicing and a storefront that takes payment** — Ninth Street Labs, LLC is the seller of record; a parent or guardian is the legal payee
- **Clean books** — every payment, fee, and expense on the line it belongs to
- **Tax tracking** — income, expenses, and net, with tax-prep milestones flagged
- **Graduation path** — export to your own LLC when you turn 18

## How the money works

This is the part worth being precise about, because it constrains most of the code.

**Ninth Street Labs, LLC, doing business as Fuime, is the seller of record.** When a
client pays, they buy from Ninth Street Labs, LLC. Fuime keeps its fee and owes the rest
to the venture as a payable, paid out on a stated schedule after the guardian approves
the payout destination. What the app shows is a payable, not a bank balance and not a
parent-owned Stripe account.

Fuime is a financial technology company, not a bank. Fuime does not hold deposits and does
not offer FDIC-insured products. Payments are processed by Stripe.

## Built on HCB

Fuime is a fork of [HCB](https://github.com/hackclub/hcb) by [Hack Club](https://hackclub.com), the open-source fiscal sponsorship platform that has processed millions of dollars for teen nonprofits since 2018. We've repurposed it from nonprofit fiscal sponsorship to a financial platform for teen-run businesses.

**HCB's battle-tested infrastructure powers Fuime:**
- The same ledger engine that tracks millions in nonprofit funds
- The same receipt management and transparency features

What does **not** carry over is HCB's custody model. HCB works because a 501(c)(3) legally
owns every dollar it holds, which is what lets it pool funds and issue cards against one
platform balance. A for-profit cannot copy that, so production Fuime is merchant-of-record: Ninth Street
Labs, LLC is the seller, and operators are paid as vendors. Card issuing is off by
default and is gated behind a per-venture flag.

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
