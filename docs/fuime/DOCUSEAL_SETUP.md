# DocuSeal setup — the Fuime agreement

`Event::Plan#contract_docuseal_template_id` reads `FUIME_DOCUSEAL_TEMPLATE_ID` from the
environment. Until that is set, `contract_available?` is false, `send_contract` returns
nil, and the whole signing step is skipped — applications get approved with no agreement
and no way to activate the org from the UI.

This document is the exact spec for the DocuSeal template. **The role and field names
below are matched as literal strings by the code.** A typo does not raise at template
creation time; it fails later, at send time or at webhook time, which is much harder to
debug. Copy them exactly.

---

## 1. Create the DocuSeal account

Fuime needs its **own** DocuSeal account. Do not reuse Hack Club's — their templates are
501(c)(3) fiscal sponsorship agreements naming EIN 81-2908499, and we cannot edit them.

1. Sign up at https://docuseal.com.
2. Settings → API → copy the **X-Auth-Token**.
3. The API base the code calls is `https://api.docuseal.co/` (see `Contract#docuseal_client`).

## 2. Build the template

Create a new template. Its content is the legal agreement itself — see section 6 for what
Fuime's agreement actually needs to say, which is a lawyer conversation, not a code one.

### Roles (exact strings)

Add exactly these three submitter roles, in this order. They come from
`Contract::Party#docuseal_role`:

| Role in DocuSeal   | Fuime `role` | Who signs                          |
| ------------------ | ------------ | ---------------------------------- |
| `Contract Signee`  | `signee`     | The teen founder                   |
| `Cosigner`         | `cosigner`   | Their parent / legal guardian      |
| `Fuime`            | `hcb`        | Fuime operations (countersignature)|

> The internal role is still `hcb` in the database — that is upstream's name and renaming
> it is out of scope per CLAUDE.md Rule 6. Only the DocuSeal-facing string is "Fuime".

### Fields (exact names)

From `Contract::FiscalSponsorship#payload`. Assign each field to the role listed.

**Contract Signee:**

| Field name     | Prefilled from                | Readonly |
| -------------- | ----------------------------- | -------- |
| `Contact Name` | signee's `full_name`          | no       |
| `Telephone`    | signee's `phone_number`       | no       |
| `Email`        | signee's email                | no       |
| `Organization` | application name              | **yes**  |
| `The Project`  | application description       | no       |

**Cosigner:** no prefilled fields — just a signature. The parent gets their own signature
block on the document.

**Fuime:**

| Field name  | Prefilled from        | Readonly |
| ----------- | --------------------- | -------- |
| `Fuime ID`  | application public id | **yes**  |
| `Signature` | nothing               | no       |

Every role also needs a signature field so DocuSeal can mark the submission complete.

> Note on the countersignature: upstream prefilled Fuime's `Signature` with
> `zach_signature.png`, a scanned image of Hack Club's founder fetched from
> hcb.hackclub.com. That is removed — whoever countersigns for Fuime signs for themselves.

## 3. Set the environment variables

In `.env.development` (and Doppler for any deployed environment):

```sh
FUIME_DOCUSEAL_TEMPLATE_ID=123456   # the numeric template id from the DocuSeal URL
DOCUSEAL=your_x_auth_token_here
DOCUSEAL__WEBHOOK_SECRET=pick_a_long_random_string
```

`Credentials.fetch(:DOCUSEAL)` reads plain `ENV`, and nesting uses a double underscore
(`Credentials::NESTING_DELIMITER`), so `DOCUSEAL__WEBHOOK_SECRET` is the webhook secret.

## 4. Point the webhook at the app

DocuSeal → Settings → Webhooks. URL: `https://<your-host>/docuseal/webhook`, and set the
secret to the same value as `DOCUSEAL__WEBHOOK_SECRET`. DocuSeal sends it as the
`X-Docuseal-Secret` header; `DocusealController#verify_signature` compares them and 401s
on mismatch.

Subscribe to `form.completed` and `form.declined` — those are the only two events handled.

For local development DocuSeal cannot reach `localhost`, so either tunnel
(`ngrok http 3000`) and use the tunnel URL, or skip the webhook and rely on the manual
sync: `Contract::Party#sync_with_docuseal` is called on page load from
`Event::ApplicationsController#show`, which catches up any missed webhook.

## 5. Verify the flow

With the env vars set and the server restarted:

1. `Event::Plan::Standard.new.contract_available?` → must be `true`.
2. Submit a teen-led application. `mark_submitted!` now calls `send_contract`, which
   creates a `Contract::FiscalSponsorship` and POSTs to DocuSeal. The application stays
   in `submitted` rather than auto-advancing to `under_review`.
3. Teen signs → parent signs → `on_party_signed` notifies the Fuime party.
4. Admin approves → now redirects to the countersign page instead of the submission page.
5. Fuime countersigns → contract `signed` → the **Activate** button appears on the
   submission page → activating creates the `Event`.

If step 2 raises `contract missing required roles`, the template's role names don't match
section 2. If parties get created but never receive a signing link, check for
`Contract Party (n) role and/or slug missing in DocuSeal` in the logs — same cause.

## 6. What the agreement must actually say

This is the part that is not a code change. Fuime's agreement is **not** a fiscal
sponsorship agreement — the class is still named `Contract::FiscalSponsorship` for
upstream-diff reasons (Rule 6), but the document it serves should describe Fuime's real
relationship with its users:

- Who holds the money, and in what capacity. In Phase 0 this is a pooled test-mode Stripe
  account and no real custody exists.
- The guardian's role as legal signer for a minor, and what they are consenting to.
- Fees (the 4% platform fee, if it survives to launch).
- Termination, and what happens to a balance on termination.

Do not ship a real agreement to real teenagers without a lawyer reading it. Until then,
a clearly-marked test template is fine for exercising the flow in development.
