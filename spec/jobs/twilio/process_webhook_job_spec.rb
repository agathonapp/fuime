# frozen_string_literal: true

require "rails_helper"

RSpec.describe Twilio::ProcessWebhookJob do
  subject(:job) { described_class.new }

  let(:account_sid) { "ACaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:message_sid) { "MMbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  let(:media_sid) { "MEcccccccccccccccccccccccccccccccc" }
  let(:twilio_media_url) do
    "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages/#{message_sid}/Media/#{media_sid}"
  end

  def attachments_for(url)
    job.instance_variable_set(
      :@params,
      {
        "NumMedia"          => "1",
        "MediaUrl0"         => url,
        "MediaContentType0" => "image/jpeg"
      }
    )
    job.send(:fetch_attachments)
  end

  describe "media download" do
    it "does not request an untrusted media host" do
      expect(attachments_for("https://untrusted.example.test/media")).to eq([])
      expect(a_request(:any, "https://untrusted.example.test/media")).not_to have_been_made
    end

    it "does not follow a redirect to an untrusted host" do
      stub_request(:get, twilio_media_url)
        .to_return(status: 307, headers: { "Location" => "https://untrusted.example.test/copied" })

      expect(attachments_for(twilio_media_url)).to eq([])
      expect(a_request(:any, "https://untrusted.example.test/copied")).not_to have_been_made
    end

    it "downloads from an allowlisted Twilio media host" do
      stub_request(:get, twilio_media_url)
        .to_return(status: 200, body: "receipt-bytes", headers: { "Content-Type" => "image/jpeg" })

      downloaded = attachments_for(twilio_media_url)

      expect(downloaded.size).to eq(1)
      expect(downloaded.first[:content_type]).to eq("image/jpeg")
      expect(downloaded.first[:io].read).to eq("receipt-bytes")
    end

    it "follows a single Twilio redirect to a signed S3 URL" do
      s3_url = "https://s3.amazonaws.com/twilio-media/object?X-Amz-Signature=test"
      stub_request(:get, twilio_media_url)
        .to_return(status: 307, headers: { "Location" => s3_url })
      stub_request(:get, s3_url)
        .to_return(status: 200, body: "s3-bytes")

      downloaded = attachments_for(twilio_media_url)

      expect(downloaded.size).to eq(1)
      expect(downloaded.first[:io].read).to eq("s3-bytes")
    end
  end
end
