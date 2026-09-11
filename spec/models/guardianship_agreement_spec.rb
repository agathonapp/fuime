# frozen_string_literal: true

require "rails_helper"

# Fuime: a guardian must always be able to re-read the exact text they signed,
# so agreement versions resolve to their own on-disk partial. The version string
# comes out of the database and is interpolated into a path, so the allowlist
# that guards it is tested as a security control, not a nicety.
RSpec.describe Guardianship, type: :model do
  describe ".agreement_partial_for" do
    it "resolves the current version to its partial" do
      expect(described_class.agreement_partial_for(described_class::CURRENT_AGREEMENT_VERSION))
        .to eq("guardianships/agreements/2026_09_10_v3")
    end

    it "translates dashes in the version to underscores in the filename" do
      expect(described_class.agreement_partial_for("2026-08-06-v2"))
        .to eq("guardianships/agreements/2026_08_06_v2")
    end

    # Bumping the version must never strand the guardians who signed the old
    # one. This is the assertion that makes a bump additive: it fails the moment
    # someone deletes a superseded partial or renames it in place.
    it "still resolves every superseded version whose text is on disk" do
      {
        "2026-08-01-v1" => "guardianships/agreements/2026_08_01_v1",
        "2026-08-06-v2" => "guardianships/agreements/2026_08_06_v2",
      }.each do |version, partial|
        expect(described_class.agreement_partial_for(version))
          .to eq(partial), "expected superseded #{version} to still resolve"
      end
    end

    it "is nil for a version with no partial on disk" do
      expect(described_class.agreement_partial_for("1999-01-01-v9")).to be_nil
    end

    it "is nil for a blank version" do
      expect(described_class.agreement_partial_for(nil)).to be_nil
      expect(described_class.agreement_partial_for("")).to be_nil
    end

    # The allowlist must reject anything that could escape the agreements
    # directory, even though these strings should never reach the database.
    it "rejects path traversal and other unsafe version strings" do
      [
        "../../../../etc/passwd",
        "..%2f..%2fsecrets",
        "2026-08-01-v1/../../../config/database",
        "foo bar",
        "Foo-V1", # uppercase is outside the allowlist
        "2026;rm -rf /",
      ].each do |unsafe|
        expect(described_class.agreement_partial_for(unsafe)).to be_nil,
                                                                 "expected #{unsafe.inspect} to be rejected"
      end
    end
  end

  # A versioned agreement partial is a historical document: it must state the
  # version it IS, not the version that happens to be current. v1 interpolated
  # Guardianship::CURRENT_AGREEMENT_VERSION in its footer, so bumping to v2 would
  # have made every past v1 record display v1's terms under v2's number — the
  # signature record and the text it points at silently disagreeing.
  #
  # Asserted against the files rather than by rendering, because the property
  # should hold for every version that will ever be added, including ones written
  # after this spec.
  describe "the versioned agreement partials" do
    let(:partials) do
      Rails.root.glob("app/views/guardianships/agreements/_*.html.erb")
    end

    it "has at least one on disk" do
      expect(partials).not_to be_empty
    end

    it "never interpolates the current-version constant" do
      offenders = partials.select do |path|
        # Strip ERB comments first: the partials discuss the constant by name in
        # their own header comments, which is documentation rather than output.
        path.read.gsub(/<%#.*?%>/m, "").include?("CURRENT_AGREEMENT_VERSION")
      end

      expect(offenders.map { |p| p.basename.to_s }).to be_empty
    end

    it "states its own version, taken from its filename" do
      partials.each do |path|
        version = path.basename(".html.erb").to_s.delete_prefix("_").tr("_", "-")

        expect(path.read).to include(version),
                             "expected #{path.basename} to state the version #{version.inspect} it is"
      end
    end
  end

  # The current agreement is the one document a parent signs, so it carries the
  # L5 standing disclosure (LEGAL_RESEARCH.md §7): sentences 1–3 verbatim, and
  # sentence 4 adapted to the signer ("owned by you, a parent or legal guardian")
  # with §7's "opened" dropped, because under merchant-of-record the minor may
  # open the venture before any guardian has accepted. v2 said "software
  # platform, not a bank" and described a per-venture Stripe account in the
  # guardian's name — the Connect posture — which production (merchant-of-record)
  # does not have. These pin the current text so a future bump cannot quietly
  # reintroduce either.
  #
  # Asserted on the file with ERB comments stripped: the partial's own header
  # quotes the superseded wording when it explains what changed, and that is
  # documentation, not something a guardian reads. Whitespace is collapsed so
  # that reflowing a paragraph — which moves line breaks between words but
  # changes nothing a guardian reads — cannot fail a wording assertion.
  describe "the current agreement's wording" do
    let(:current_text) do
      slug = described_class::CURRENT_AGREEMENT_VERSION.tr("-", "_")
      Rails.root.join("app/views/guardianships/agreements/_#{slug}.html.erb")
           .read
           .gsub(/<%#.*?%>/m, "")
           .squish
    end

    it "carries the L5 standing disclosure" do
      expect(current_text).to include("Fuime is a financial technology company, not a bank.")
      expect(current_text).to include("does not offer FDIC-insured products")
      expect(current_text).to match(/owned by you, a parent or legal\s+guardian/)
    end

    it "no longer calls Fuime a software platform" do
      expect(current_text).not_to include("software platform")
    end

    # The three v2 sentences that were false under merchant-of-record.
    it "does not describe a per-venture Stripe account or claim Fuime never holds the money" do
      expect(current_text).not_to include("opened in your name with Stripe")
      expect(current_text).not_to include("does not hold that money at any point")
      expect(current_text).not_to match(/paid out to a bank account you own/)
    end

    # L5's forbidden vocabulary, allowed only inside the mandated denials.
    it "uses no bank vocabulary outside the standing disclosure" do
      scrubbed = current_text
                 .gsub("Fuime is a financial technology company, not a bank.", "")
                 .gsub(/Fuime does not hold\s+deposits and does not offer FDIC-insured products\./, "")

      expect(scrubbed).not_to match(/\b(bank|banking|neobank|checking|savings|deposits?|insured|FDIC)\b/i)
      expect(scrubbed).not_to match(/your money is\s+(safe|guaranteed)/i)
    end

    # Section 5 must describe how production actually pays. Payouts are a
    # scheduled Fuime::PayoutBatch that a Fuime admin approves; the guardian
    # decides PayoutRequests the teen files (EventPolicy#decide_payout?), and on
    # an institutionally sponsored venture the school stands in for the guardian
    # (Event#payout_setup_blockers). The first draft of v3 said every payout "comes
    # to you to approve or decline" and that "only you" could set the destination
    # — neither true — and §3 promised "balances", the word the merchant-of-record
    # copy rules forbid on guardian-facing pages (spec/views/fuime/payables_copy_spec.rb).
    it "describes payouts as scheduled, guardian-decided, and school-substituted" do
      expect(current_text).to match(/The minor cannot move money out of the\s+business on their own\./)
      expect(current_text).to match(/on a regular schedule/)
      expect(current_text).to match(/any payout that needs a decision is\s+yours to make, not the minor's\./)
      expect(current_text).to match(/Only a parent or legal guardian on the account \(or Fuime, at a\s+guardian's request\) can add or change that destination/)
      expect(current_text).to match(/inside a school programme Fuime has\s+approved, the school is\s+the responsible party for payouts\./)

      expect(current_text).not_to match(/comes to you to\s+approve or decline/)
      expect(current_text).not_to match(/Only you can add or change/)
    end

    it "does not promise the guardian a view of balances" do
      expect(current_text).not_to match(/\bbalances?\b/i)
      expect(current_text).to match(/every sale, what the business has earned and been paid/)
    end

    # The guardian gate has two holes the code leaves open on purpose:
    # Event#payout_setup_blockers skips it for a venture inside a school programme
    # (Event#institutionally_sponsored?), and User#needs_guardian? is false after
    # an admin waiver (User#waive_guardian_requirement!, whose own UI calls it "an
    # admin override, not a parent signature"). A signed promise that "no money is
    # paid out without a parent or legal guardian" is one an admin button can
    # break, so the agreement names both exceptions — once, in section 5 — and
    # sections 2 and 4 point there instead of restating the rule as absolute.
    it "states the guardian gate's exceptions once, in section 5, and refers to them elsewhere" do
      expect(current_text).to match(/without a parent or legal guardian on the account, with two\s+exceptions\./)
      expect(current_text).to match(/inside a school programme Fuime has\s+approved, the school is\s+the responsible party for payouts\./)
      expect(current_text).to match(/by\s+a recorded decision of a named Fuime administrator, override the requirement\s+for a parent or legal guardian/)
      expect(current_text).to match(/records who made\s+that decision and when, and can restore the requirement\./)

      # Section 2 and section 4 each defer to section 5 rather than restating the
      # rule without its exceptions.
      expect(current_text.scan(/except as section 5\s+describes/).size).to eq(2)
      expect(current_text).not_to match(/nothing is paid out/)
      expect(current_text).not_to match(/without a parent or legal guardian on the account\./)
    end

    # The gate runs when the weekly run is generated (Fuime::PayableAssessment,
    # Wednesday for a Friday payout per config/schedule.yml); approve! and
    # mark_paid! on Fuime::PayoutBatchService never re-check it. A guardian who
    # revokes on Thursday does not stop Friday's payment of a line generated on
    # Wednesday, so "takes effect immediately: no money can be paid out" was a
    # promise the code breaks every week for about two days.
    it "does not promise that revocation stops a payout already in a scheduled run" do
      expect(current_text).to match(/Revoking takes effect as soon as you do it\./)
      expect(current_text).to match(/Fuime will not schedule any new payout of the minor's business until\s+a parent or legal guardian is on the account again/)
      expect(current_text).to match(/payout that was already scheduled or released when you revoked may still be\s+sent\./)

      expect(current_text).not_to include("takes effect immediately")
      expect(current_text).not_to match(/no money can\s+be paid out/)
    end

    # The Terms page still carries beta-era copy that a separate item is fixing,
    # so this document may point at the Terms as governing sales but may not
    # vouch for what they currently "describe".
    it "points at the Terms without vouching for their contents" do
      expect(current_text).to match(/govern sales made through\s+Fuime, including refunds and disputes\./)
      expect(current_text).not_to include("describe who the seller of")
    end

    # The text a guardian signed has to reproduce from the version alone, so the
    # partial may not consult a feature flag that could differ on the day it is
    # re-read from the day it was signed.
    it "does not branch on a runtime feature flag" do
      expect(current_text).not_to include("Features.")
      expect(current_text).not_to include("merchant_of_record")
    end

    # The file assertions above cannot catch a broken ERB tag, and the wording a
    # guardian actually sees is the rendered output, not the source.
    it "renders with the disclosure in the output" do
      html = ApplicationController.render(
        partial: described_class.agreement_partial_for(described_class::CURRENT_AGREEMENT_VERSION),
        locals: { minor: Struct.new(:name, :email).new("Sample Teen", nil), guardian: nil }
      )

      expect(html).to include("Fuime is a financial technology company, not a bank.")
      expect(html).to include("Agreement version #{described_class::CURRENT_AGREEMENT_VERSION}")
      expect(html).to include("Sample Teen")
      expect(html).not_to include("software platform")
    end
  end

  # The revoked_by_id column and its foreign key shipped without a matching
  # association, so every `guardianship.revoked_by` in a view raised NoMethodError.
  describe "#revoked_by" do
    it "reads back the user who withdrew consent" do
      guardianship = create(:guardianship, :active)
      admin = create(:user, :make_admin, birthday: 35.years.ago.to_date)

      guardianship.revoke!(revoked_by: admin)

      expect(guardianship.reload.revoked_by).to eq(admin)
    end

    it "is nil when the revocation is not attributable to a user" do
      guardianship = create(:guardianship, :active)

      guardianship.revoke!

      expect(guardianship.reload.revoked_by).to be_nil
    end
  end

  describe "#agreement_partial" do
    it "renders the version that was actually signed, not today's terms" do
      guardianship = create(:guardianship, :active, agreement_version: "2026-08-01-v1")

      expect(guardianship.agreement_partial).to eq("guardianships/agreements/2026_08_01_v1")
    end

    it "falls back to the current version when unsigned" do
      guardianship = create(:guardianship)

      expect(guardianship.agreement_partial)
        .to eq(described_class.agreement_partial_for(described_class::CURRENT_AGREEMENT_VERSION))
    end

    it "is nil when the signed version's text is no longer on disk" do
      guardianship = create(:guardianship, :active)
      guardianship.update_column(:agreement_version, "2020-01-01-v0")

      expect(guardianship.reload.agreement_partial).to be_nil
    end
  end
end
