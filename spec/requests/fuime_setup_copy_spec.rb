# frozen_string_literal: true

require "rails_helper"

# Fuime: what the setup wizard is and is not allowed to say.
#
# Eight screens and one email are the first thing a family reads about a
# financial product, and two rules govern them.
#
# L5 — while no partner bank exists, the vocabulary of banking is forbidden
# (Cal. Fin. Code § 562; 205 ILCS 5/46; FDIC Part 328 Subpart B). The standing
# "not a bank" disclosure is the ONE place those words may appear, so every
# example below strips it before testing the rest of the page. Stripping rather
# than exempting the words: an exemption would let "your deposits" slip through
# anywhere on the page.
#
# L8 — the site and the app must describe the product that exists. Under
# merchant-of-record that means: a person at Fuime reviews every venture before
# it can sell (so nothing may promise selling "now"), and the guardian gates
# payouts (so nothing may say they gate selling or activation).
# The disclosure's own load-bearing clauses, as status_disclosure_spec defines
# them. Duplicated rather than required: that file is a spec, not a library,
# and a constant shared between two spec files is a load-order problem waiting
# to happen.
NOT_A_BANK_SENTENCE = "not a bank"
NO_FDIC_SENTENCE = "does not offer FDIC-insured products"

# Everything a wizard page may never say. `bank`/`deposit`/`insured`/`FDIC` are
# absent from this list ONLY because the disclosure is stripped first — see
# `body_without_disclosure`.
FORBIDDEN = [
  /\bbanking\b/i, /\bneobank/i, /\bchecking account/i, /\bsavings account/i,
  /\bFDIC\b/i, /\binsured\b/i, /your money is safe/i, /guaranteed/i,
  # L8: false under merchant-of-record.
  /start selling now/i, /sell(ing)? (right )?away/i,
  # No ETA has been committed to (ONBOARDING_PLAN §6 #4).
  /usually within/i, /within a day/i,
  # No price is ever suggested, anywhere.
  /most people charge/i, /typical(ly)? charge/i, /we recommend charging/i,
  # No date of birth is collected (decided 2026-08-20).
  /date of birth/i
].freeze

RSpec.describe "setup wizard copy", type: :request do
  # The disclosure is the one licensed use of the forbidden vocabulary. Remove
  # its paragraph, then judge what is left.
  def body_without_disclosure(body)
    doc = Nokogiri::HTML5.parse(body)
    doc.css("p").each { |node| node.remove if node.text.include?(NOT_A_BANK_SENTENCE) }
    doc.text
  end

  def expect_clean(body, on:)
    expect(page_text(body)).to include(NOT_A_BANK_SENTENCE), "#{on} is missing the standing disclosure"
    expect(page_text(body)).to include(NO_FDIC_SENTENCE), "#{on} is missing the FDIC sentence"

    text = body_without_disclosure(body)
    FORBIDDEN.each do |pattern|
      expect(text).not_to match(pattern), "#{on} says something matching #{pattern.inspect}"
    end
  end

  describe "the teen's five screens", :merchant_of_record do
    let!(:teen) { login_as!("copy-teen@example.com") }

    it "keeps every screen clean and carries the disclosure on all of them" do
      get teen_setup_step_path(step: "you")
      expect_clean(response.body, on: "/setup/you")
      # The one promise this screen makes about the parent has to be the true one.
      expect(page_text).to include("before you get paid")

      post teen_setup_save_path(step: "you"),
           params: { user: { full_name: "Copy Teen", age_attestation_confirmed: "1" } }

      get teen_setup_step_path(step: "business")
      expect_clean(response.body, on: "/setup/business")

      post teen_setup_save_path(step: "business"),
           params: { setup: { starting_point: "have_idea", service_type: "tutoring" } }

      get teen_setup_step_path(step: "name")
      expect_clean(response.body, on: "/setup/name")

      post teen_setup_save_path(step: "name"),
           params: { setup: { name: "Copy Co", description: "I tutor algebra." } }

      get teen_setup_step_path(step: "family")
      expect_clean(response.body, on: "/setup/family")
      # L8: what the parent actually gates, said out loud.
      expect(page_text).to include("paid out")

      post teen_setup_save_path(step: "family"),
           params: { setup: { address_country: "US", cosigner_email: "copy-parent@example.com" } }

      get teen_setup_step_path(step: "done")
      expect_clean(response.body, on: "/setup/done")
      # The gate that is real, named as a person's decision.
      # The real gate before selling, named as a human decision — the sentence
      # that has to be on this screen instead of "you can start selling".
      expect(page_text).to match(/by a person/i)
    end
  end

  describe "the parent's three screens" do
    it "keeps every screen clean and carries the disclosure on all of them" do
      login_as!("copy-parent-flow@example.com", return_to: "/setup/parent")

      get parent_setup_step_path(step: "teen")
      expect_clean(response.body, on: "/setup/parent/teen")
      expect(page_text).to include("Social Security number")

      post parent_setup_save_path(step: "teen"), params: {
        setup: { teen_first_name: "Maya", teen_email: "copy-kid@example.com", teen_13_plus: "1" }
      }

      get parent_setup_step_path(step: "sign")
      expect_clean(response.body, on: "/setup/parent/sign")
      expect(page_text).to include("not an identity check")

      post parent_setup_save_path(step: "sign"),
           params: { agree: "1", setup: { parent_full_name: "Copy Parent" } }

      get parent_setup_step_path(step: "done")
      expect_clean(response.body, on: "/setup/parent/done")
    end
  end

  describe "the parent signup page" do
    it "is clean and promises no paperwork it will ask for" do
      get auth_users_path(signup: true, return_to: "/setup/parent")

      text = body_without_disclosure(response.body)
      FORBIDDEN.each { |pattern| expect(text).not_to match(pattern) }
      expect(page_text).to include("Social Security number")
    end
  end

  describe "the teen's join email" do
    it "says only what is true and none of what is forbidden" do
      parent = create(:user, birthday: 40.years.ago.to_date, full_name: "Pat Copy", verified: true)
      teen = create(:user, :unknown_age, full_name: nil, preferred_name: "Maya",
                                         email: "copy-join@example.com")
      guardianship = create(:guardianship, guardian: parent, minor: teen)
      guardianship.update!(status: :active, initiated_by: :guardian)

      mail = Fuime::FamilyMailer.teen_join(guardianship:)
      body = mail.html_part.decoded + mail.text_part.decoded

      FORBIDDEN.each { |pattern| expect(body).not_to match(pattern) }
      expect(body).to include("financial platform for young founders")
      expect(body).to include("a person at Fuime approves it")
    end
  end
end
