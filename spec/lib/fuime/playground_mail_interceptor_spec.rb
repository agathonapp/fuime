# frozen_string_literal: true

require "rails_helper"

# Fuime: a demo driven on the production deploy must not be able to email a
# stranger because somebody typed a plausible address on stage.
RSpec.describe Fuime::PlaygroundMailInterceptor do
  def message_to(*recipients)
    Mail.new(to: recipients, from: "no-reply@fuime.com", subject: "Test")
  end

  it "drops a message addressed only to personas" do
    message = message_to(Fuime::Playground::NEW_KID_EMAIL)

    described_class.delivering_email(message)

    expect(message.perform_deliveries).to be(false)
  end

  it "drops demo-sandbox addresses too" do
    message = message_to(Fuime::DemoSandbox.email("teen.solo"))

    described_class.delivering_email(message)

    expect(message.perform_deliveries).to be(false)
  end

  it "delivers to a real address" do
    message = message_to("someone@example.com")

    described_class.delivering_email(message)

    expect(message.perform_deliveries).to be(true)
  end

  # Silently swallowing a message that happens to copy a real person is worse
  # than sending one persona a note it will never read.
  it "delivers a mixed recipient list" do
    message = message_to(Fuime::Playground::NEW_KID_EMAIL, "real@example.com")

    described_class.delivering_email(message)

    expect(message.perform_deliveries).to be(true)
  end
end
