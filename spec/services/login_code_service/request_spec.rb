# frozen_string_literal: true

require "rails_helper"

describe LoginCodeService::Request do
  let(:ip_address) { "127.0.0.1" }
  let(:user_agent) { "fake firefox" }

  # ── Fuime: the newest code is the only code ──────────────────────────────
  #
  # `LoginCode.active` was every unused code from the last fifteen minutes, so
  # each request ADDED a working key instead of replacing one. Login initiation
  # is throttled at 5 per 20s per IP, which makes roughly 225 codes live at once
  # against one account — and until this branch nothing throttled GUESSING at
  # `POST /logins/:id/complete` either. Six digits against 225 live keys and a
  # few thousand attempts is not a lock, and these accounts hold a venture's
  # ledger and, for a guardian, the payout destination.
  describe "superseding older codes" do
    let(:user) { create(:user) }

    before { allow(LoginCodeMailer).to receive_message_chain(:send_code, :deliver_now) }

    def request!
      described_class.new(email: user.email, ip_address:, user_agent:).run
    end

    it "leaves exactly one code usable, however many were requested" do
      3.times { request! }

      expect(user.login_codes.active.count).to eq(1)
      expect(user.login_codes.count).to eq(3)
    end

    it "keeps the newest one, which is the email the person is reading" do
      request!
      newest = nil
      expect { newest = request! }.to(change { user.login_codes.active.first&.id })

      expect(user.login_codes.active.sole.id).to eq(user.login_codes.order(:id).last.id)
    end

    it "does not disturb another user's live code" do
      other = create(:user)
      described_class.new(email: other.email, ip_address:, user_agent:).run

      request!

      expect(other.login_codes.active.count).to eq(1)
    end
  end

  context "when a user with a given email does not exist" do
    it "creates that user with login code and emails" do
      new_email = "test@example.com"
      expect(User.find_by(email: new_email)).to be_nil

      expect(LoginCodeMailer).to receive_message_chain(:send_code, :deliver_now)
      response = nil
      expect do
        response = described_class.new(email: new_email,
                                       ip_address:,
                                       user_agent:).run
      end.to change { User.count }.by(1)

      user = User.find_by(email: new_email)
      expect(user.login_codes.count).to eq(1)
      login_code = user.login_codes.first
      expect(login_code.ip_address).to eq(ip_address)
      expect(login_code.user_agent).to eq(user_agent)

      expect(response).to eq({
                               id: user.id,
                               email: user.email,
                               status: "login code sent",
                               method: :email,
                               login_code:
                             })
    end
  end


  context "when a user with a given email does exist" do
    it "creates that user with login code and emails" do
      user = create(:user)

      expect(LoginCodeMailer).to receive_message_chain(:send_code, :deliver_now)
      response = nil
      expect do
        response = described_class.new(email: user.email,
                                       ip_address:,
                                       user_agent:).run
      end.to change { User.count }.by(0)

      expect(user.login_codes.count).to eq(1)
      login_code = user.login_codes.first
      expect(login_code.ip_address).to eq(ip_address)
      expect(login_code.user_agent).to eq(user_agent)

      expect(response).to eq({
                               id: user.id,
                               email: user.email,
                               status: "login code sent",
                               method: :email,
                               login_code:
                             })
    end
  end

  context "errors" do
    context "when user has an error" do
      it "does not save the user, does not create a login code and returns an error" do
        invalid_email = "bad@bad"
        expect(LoginCodeMailer).not_to receive(:send_code)

        response = nil
        expect do
          response = described_class.new(email: invalid_email,
                                         ip_address:,
                                         user_agent:).run
        end.to change { User.count }.by(0)

        expect(LoginCode.count).to eq(0)
        expect(response[:error].attribute_names).to eq([:email])
      end
    end

    context "when the SMTP server is unreachable" do
      it "returns a readable error instead of raising" do
        user = create(:user)

        allow(LoginCodeMailer).to receive(:send_code)
          .and_raise(Errno::ECONNREFUSED.new("connect(2) for nil port 25"))

        response = nil
        expect do
          response = described_class.new(email: user.email,
                                         ip_address:,
                                         user_agent:).run
        end.not_to raise_error

        expect(response[:method]).to eq(:email)
        expect(response[:error]).to match(/couldn't send your login code/i)
      end
    end
  end
end
