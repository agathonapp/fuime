# frozen_string_literal: true

require "rails_helper"

# Fuime: the activation email is the first thing a founder reads after "Waiting
# on Fuime", so its next steps have to be the ones that lead to a sale, and the
# guardian line has to be true under merchant-of-record — sell now, paid out
# after a parent signs. ONBOARDING_PLAN.md §1 #11 is the friction this removes.
#
# HTML-only, matching the rest of Event::ApplicationMailer, so the body is read
# straight off the message rather than off a part.
RSpec.describe Event::ApplicationMailer, type: :mailer do
  describe "#activated" do
    # 16 so the founder clears the operator floor; :minor so the guardian
    # examples are about a teenager and not about an adult with no birthday.
    let(:founder) { create(:user, :minor, birthday: 16.years.ago.to_date, full_name: "Maya Founder") }
    let(:event) { create(:event, :unvetted, name: "Maya Design Studio", slug: "maya-design") }
    let(:application) { create(:event_application, user: founder, event:, name: "Maya Design Studio") }

    subject(:mail) { described_class.with(application:).activated }

    let(:body) { mail.body.to_s }

    it "still goes to the founder with the welcome subject" do
      expect(mail.to).to eq([founder.email])
      expect(mail.subject).to eq("[Maya Design Studio] Welcome to Fuime!")
    end

    it "leads with selling, then the storefront, and moves the team invite to the bottom" do
      offers = fuime_offers_url(event_slug: "maya-design")
      storefront = fuime_storefront_url(slug: "maya-design")
      team = event_team_url(event)

      expect(body).to include(offers)
      expect(body).to include(storefront)
      expect(body).to include(team)
      expect(body).to include("Add what you sell")
      expect(body).to include("Share your storefront")

      expect(body.index(offers)).to be < body.index(storefront)
      expect(body.index(storefront)).to be < body.index(team)
    end

    it "says Fuime is still reviewing an unvetted venture, and promises the email that now exists" do
      expect(body).to include("Fuime is reviewing Maya Design Studio by hand")
      expect(body).to include("We'll email you")
    end

    it "drops the review line once the venture is approved" do
      event.update!(operator_vetting_status: :approved)

      expect(body).not_to include("Fuime is reviewing")
    end

    # A rejected or suspended venture is not waiting on Fuime, so it must not be
    # told to expect an approval.
    it "drops the review line for a rejected venture" do
      event.update!(operator_vetting_status: :rejected)

      expect(body).not_to include("Fuime is reviewing")
    end

    it "keeps the onboarding-call paragraph and the support address" do
      expect(body).to include("schedule an onboarding call")
      expect(body).to include("support@fuime.com")
    end

    # ── The guardian line ────────────────────────────────────────────────────
    #
    # Gated on User#needs_guardian? — the predicate Event#payout_setup_blockers
    # reads — and not on a pending invite, because a founder with no guardianship
    # row or a revoked one is exactly as unpaid as one whose parent has not
    # clicked yet. Which row exists only changes the verb: resend or invite.
    context "when the founder's guardian invite is still pending", :merchant_of_record do
      before { create(:guardianship, minor: founder) }

      # At activation the venture is still unvetted (activate_event! never touches
      # operator_vetting_status), so it cannot sell yet and the email must not say
      # it can — the paragraph below it says Fuime is still reviewing.
      it "says they don't need a guardian to start selling, not that they can sell now, and links the Guardian page" do
        expect(event.accepts_payments?).to be(false)

        expect(body).to include("Your parent or guardian hasn't signed yet")
        expect(body).to include("You don't need a guardian to start selling, but nothing is paid out until one accepts")
        expect(body).not_to include("You can sell now")
        expect(body).to include("Resend the invite from your Guardian page")
        expect(body).to include(guardianships_url)
      end

      context "and the venture can already sell" do
        # Approved (the factory default), in an eligible category, founder over
        # the operator floor — every selling gate open, so the stronger sentence
        # is true. 17 rather than 16 so the example is not sitting on the floor.
        let(:founder) { create(:user, :minor, birthday: 17.years.ago.to_date, full_name: "Maya Founder") }
        let(:event) { create(:event, name: "Maya Design Studio", slug: "maya-design", business_category: "services") }

        it "says they can sell now but nothing is paid out until a guardian accepts" do
          expect(event.reload.accepts_payments?).to be(true)

          expect(body).to include("You can sell now under Fuime, but nothing is paid out until a guardian accepts")
          expect(body).not_to include("don't need a guardian")
        end
      end
    end

    context "when no guardian was ever invited", :merchant_of_record do
      it "tells them to invite one and links the invite page" do
        expect(body).to include("No parent or guardian on your account yet")
        expect(body).to include("nothing is paid out until one accepts")
        expect(body).to include("Invite a parent or guardian")
        expect(body).to include(new_guardianship_url)
        expect(body).not_to include("hasn't signed yet")
        expect(body).not_to include("You can sell now")
      end
    end

    context "when the only guardianship was revoked", :merchant_of_record do
      before { create(:guardianship, :revoked, minor: founder) }

      it "treats it like no guardian and asks them to invite one" do
        expect(body).to include("No parent or guardian on your account yet")
        expect(body).to include("Invite a parent or guardian")
        expect(body).to include(new_guardianship_url)
        expect(body).not_to include("Resend the invite")
      end
    end

    # Under Connect the guardian owns the payment account, so a venture without
    # one cannot sell at all; the email says only the weaker thing that is true
    # in both models. This state is rare there (activation_blockers refuses a
    # guardianless minor) but the sentence must be honest when it renders.
    it "makes no selling claim under Connect, only that payouts wait on a guardian" do
      expect(body).to include("Nothing is paid out until a guardian accepts")
      expect(body).not_to include("You can sell now")
      expect(body).not_to include("don't need a guardian")
    end

    it "says nothing about a guardian once one has accepted" do
      create(:guardianship, :active, minor: founder)

      expect(body).not_to include("hasn't signed yet")
      expect(body).not_to include("No parent or guardian on your account yet")
    end

    it "says nothing about a guardian to an adult founder" do
      founder.update!(birthday: 40.years.ago.to_date)

      expect(body).not_to include("parent or guardian")
      expect(body).not_to include("paid out")
    end

    # The linked roles page and every role selector say Owners / Team members /
    # Parents (RolesHelper); the email must not hand a founder the enum's words.
    it "names roles in the same words as the roles page it links to" do
      expect(body).to include("as owners, team members, or a parent seat")
      expect(body).not_to include("managers, members, or readers")
      expect(body).to include(roles_url)
    end

    # L5: none of the words a company without a partner bank may not use.
    it "stays inside the permitted vocabulary" do
      expect(body).not_to match(/\b(bank|banking|checking|savings|deposits?|insured|FDIC)\b/i)
    end
  end
end
