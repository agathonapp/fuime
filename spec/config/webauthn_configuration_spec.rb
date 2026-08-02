# frozen_string_literal: true

require "rails_helper"

# Fuime: these guard config/initializers/webauthn.rb.
#
# Security keys were broken in production for a subtler reason than a wrong
# origin: webauthn-ruby only infers the RP ID when exactly one origin is
# allowed, and we listed two. The inferred RP ID was nil, so every registration
# and sign-in failed the RP ID check. Nothing in the suite noticed, because the
# test environment has a single origin — the one case where inference works.
RSpec.describe "WebAuthn configuration" do
  subject(:configuration) { WebAuthn.configuration }

  it "sets an RP ID explicitly, so the number of allowed origins can't break verification" do
    expect(configuration.rp_id).to be_present
  end

  it "uses a bare domain as the RP ID — no scheme, no port" do
    expect(configuration.rp_id).not_to include("://")
    expect(configuration.rp_id).not_to include(":")
    expect(configuration.rp_id).to eq(URI.parse(configuration.allowed_origins.first).host)
  end

  it "allows exactly one origin, since a credential is bound to one RP ID" do
    expect(configuration.allowed_origins.size).to eq(1)
  end

  it "identifies Fuime, not Hack Club, in the browser's passkey prompt" do
    expect(configuration.rp_name).to eq("Fuime")
  end

  # The failure mode this whole file exists for. If the RP ID is ever left to
  # inference again, adding a second origin silently kills every security key.
  it "verifies a credential even when a second origin is allowed" do
    user = create(:user)
    original_origins = configuration.allowed_origins

    configuration.allowed_origins = original_origins + ["https://fuime-web.onrender.com"]

    client = WebAuthn::FakeClient.new(original_origins.first)
    options = WebAuthn::Credential.options_for_create(
      user: { id: WebAuthn.generate_user_id, name: user.email, display_name: user.name }
    )
    credential = WebAuthn::Credential.from_create(client.create(challenge: options.challenge))

    expect(credential.verify(options.challenge)).to eq(true)
  ensure
    configuration.allowed_origins = original_origins
  end
end
