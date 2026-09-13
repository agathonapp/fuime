# frozen_string_literal: true

require "rails_helper"

# Fuime: every absolute URL this app generated in production began `http://`.
#
# `config/environments/production.rb` set `host` on both
# `action_mailer.default_url_options` and `routes.default_url_options`, and
# `protocol` on neither, so `*_url` defaulted to http. Three distinct costs:
#
#   * a pay link returned by `Fuime::Api::V1::PaymentLinksController` is what an
#     operator pastes into a bio, a flyer or a QR code — so the link a stranger
#     follows to type a card number visibly starts http;
#   * every mailer link (the login code, the guardian invite, the draft
#     reminder) makes a plaintext hop before the redirect;
#   * a mail client or link scanner that declines to upgrade just fails.
#
# ── Why this reads the file ─────────────────────────────────────────────────
#
# The production environment cannot be booted inside the test suite, so the
# behaviour itself is not reachable from here. Reading the source is what the
# repo already does when a template's *absence* is the thing worth pinning —
# see `spec/requests/fuime_application_submit_truth_spec.rb`, which greps
# `review.html.erb` for the out-of-office callout. It is a weaker test than
# exercising the config and it is honest about being one: it catches the
# deletion, which is the realistic regression.
RSpec.describe "production URL options" do
  let(:source) { File.read(Rails.root.join("config/environments/production.rb")) }

  it "sets https for mailer templates" do
    expect(source).to match(/config\.action_mailer\.default_url_options\s*=\s*\{[^}]*protocol:\s*["']https["']/)
  end

  # Read by `*_url` helpers called outside a request — jobs, services, and the
  # API serializer that hands an operator their pay link.
  it "sets https for route helpers called outside a request" do
    expect(source).to match(/routes\.default_url_options\[:protocol\]\s*=\s*["']https["']/)
  end
end
