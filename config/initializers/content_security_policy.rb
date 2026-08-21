# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Fuime: a Content Security Policy, in REPORT-ONLY mode.
#
# ── Why this file was empty, and why that stopped being acceptable ───────────
#
# Upstream shipped Rails' commented-out template. Fuime renders operator-authored
# text on unauthenticated pages (storefronts, payment pages, the directory) and
# takes card details through Stripe's embedded components, so a missed escape here
# is a stolen session on a page a stranger reached without signing in. A CSP is
# what turns that into a broken script instead.
#
# ── Why REPORT-ONLY, and what has to happen before it enforces ──────────────
#
# `script_src` deliberately omits `:unsafe_inline`, and there are 19 inline
# `<script>` blocks in app/views. Enforcing this policy today would break them —
# including on the checkout path, which is the one page that must never break. So
# this reports and does not block.
#
# Report-only is step one of two, not the destination:
#
#   1. THIS COMMIT. Violations appear in the browser console. Every inline script
#      the app relies on shows up as a report, which is the inventory nobody
#      currently has.
#   2. Give those scripts nonces (uncomment the nonce generator below, which makes
#      `javascript_tag` emit one automatically), confirm the console is quiet on
#      the storefront, checkout, payment page and payouts flows, then set
#      `content_security_policy_report_only = false`.
#
# Until step 2 lands this blocks nothing. That is stated plainly because a
# report-only CSP is easy to mistake for a control, and clickjacking/MIME
# protection here comes from Rails' default headers (`X-Frame-Options: SAMEORIGIN`,
# `X-Content-Type-Options: nosniff`), not from this file.
#
# ── The allowlist ────────────────────────────────────────────────────────────
#
# Hosts are the ones actually referenced from app/views and app/javascript, found
# by grep rather than guessed, so the reports are signal instead of noise. Trim
# this list as the CDN dependencies go away; every entry is a host that can
# execute script in a page showing somebody's card form.
Rails.application.configure do
  config.content_security_policy do |policy|
    # `:https` on default-src would allow any HTTPS host to satisfy an
    # unspecified directive. Start from `'self'` and name every third party
    # on the directive that actually needs it.
    policy.default_src :self

    # Stripe.js (`@stripe/stripe-js` → js.stripe.com) and Connect embedded
    # (`@stripe/connect-js` injects https://connect-js.stripe.com/v1.0/connect.js).
    # The CDNs are inherited from upstream and are the entries most worth
    # removing — each is a third party with script execution on a payment page.
    policy.script_src :self,
                      "https://js.stripe.com",
                      "https://*.js.stripe.com",
                      "https://connect-js.stripe.com",
                      "https://cdn.plaid.com",
                      "https://cdn.docuseal.com",
                      "https://cdn.jsdelivr.net",
                      "https://cdnjs.cloudflare.com",
                      "https://unpkg.com"

    # Google Fonts serves its stylesheet from one host and its font files from
    # another, so both are needed and they are not interchangeable.
    policy.style_src  :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src   :self, :data, "https://fonts.gstatic.com"

    # Receipts, profile pictures and merchant logos come from Active Storage, S3
    # and a long tail of upstream CDNs. `:https` rather than an allowlist: an
    # image cannot execute, so the value of narrowing this is low and the cost of
    # getting it wrong is a venture's receipts silently not rendering.
    policy.img_src    :self, :data, :blob, :https

    # Stripe's embedded components and hosted checkout render in iframes.
    # `*.js.stripe.com` is Stripe.js's documented frame host (3DS / Elements).
    policy.frame_src  :self, "https://js.stripe.com", "https://*.js.stripe.com",
                      "https://connect-js.stripe.com", "https://hooks.stripe.com",
                      "https://checkout.stripe.com", "https://cdn.plaid.com",
                      "https://www.youtube.com"

    policy.connect_src :self, "https://api.stripe.com", "https://js.stripe.com",
                      "https://connect-js.stripe.com", "https://*.appsignal-endpoint.net"

    # Nothing in Fuime needs a plugin or a <base> rewrite, and both are pure
    # attack surface.
    policy.object_src :none
    policy.base_uri   :self

    # Cheap and worth having even in report-only: it tells us if anything is
    # framing a Fuime page.
    policy.frame_ancestors :self
  end

  # Step 2 of the plan above. Uncommenting these makes `javascript_tag` and
  # `stylesheet_link_tag` emit a nonce, which is what lets the inline scripts
  # survive enforcement.
  #
  # config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  # config.content_security_policy_nonce_directives = %w[script-src]

  # Flip to false only after the console is quiet on the money paths.
  config.content_security_policy_report_only = true
end
