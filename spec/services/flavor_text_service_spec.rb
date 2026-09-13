# frozen_string_literal: true

require "rails_helper"

# Fuime: the rotating tagline on the signed-in home page is user-facing copy,
# and L5 applies to it exactly as it applies to a mailer.
#
# ── What this file exists for ──────────────────────────────────────────────
#
# Three independent reviewers found the same thing on the same page. The list
# inherited from HCB carried about twenty live taglines using the forbidden
# vocabulary — "The bank that smiles back!", "*technically not a bank*",
# "Koalaty banking", "no hack, only bank", "The only bank brave enough to say…",
# "I was gonna tell a Bank joke", "If money talks, why do we need bank tellers?"
# — rendered beside the heading of the most-visited signed-in page in the
# product, to teenagers and to the parents who are the legal account holders.
#
# L5 forbids exactly those words while no partner bank exists (Cal. Fin. Code
# § 562; 205 ILCS 5/46; FDIC Part 328 Subpart B; DFPI v. Chime). The existing L5
# sweep covered mailers and helpers, and this service is neither, so nothing
# caught it.
#
# Three more entries rendered links to `hack.af/hcb-stickers` with the signed-in
# user's **name, email and venture name prefilled in the query string** — a
# minor's personal data handed to Hack Club's form on page load, which is
# Prime Directive 4 and L7 at once. The file's own header comment says Hack Club
# links were stripped for that very reason; these survived because they sit
# inside conditional splats rather than being plain strings.
#
# The lists are jokes and will be edited again. This spec is the thing that
# makes editing them safe.
RSpec.describe FlavorTextService do
  # L5's forbidden vocabulary. `interest` is deliberately absent — "0% interest"
  # is a pun about being interesting, not a deposit product claim.
  def forbidden_vocabulary
    /\b(banks?|banking|banker|bankers|tellers?|neobank|deposits?|savings|checking|insured|FDIC)\b/i
  end

  # Everything the service can produce, across every branch and many seeds.
  # `sample(random:)` inside entries means one call shows one variant, so this
  # sweeps enough seeds to reach them.
  def every_flavor_text(user: nil)
    texts = []
    40.times do
      service = described_class.new(user:, deterministic: false)
      %i[flavor_texts holiday_flavor_texts spooky_flavor_texts frc_flavor_texts
         birthday_flavor_texts development_flavor_texts].each do |list|
        texts.concat(service.send(list)) if service.respond_to?(list, true)
      end
    end
    texts.map(&:to_s)
  end

  it "never calls Fuime a bank, or anything else L5 forbids" do
    offenders = every_flavor_text.select { |t| t.match?(forbidden_vocabulary) }

    expect(offenders.uniq).to be_empty,
                              "L5 forbidden vocabulary in a user-facing tagline:\n  #{offenders.uniq.join("\n  ")}"
  end

  it "never sends a user to Hack Club" do
    offenders = every_flavor_text.select { |t| t.match?(/hack\.af|hackclub|Hack Club|Hack Foundation/i) }

    expect(offenders.uniq).to be_empty,
                              "Hack Club reference in a user-facing tagline:\n  #{offenders.uniq.join("\n  ")}"
  end

  # The PII half, asserted with a real user so the interpolations actually run.
  it "never puts a user's name or email into an outbound link" do
    user = create(:user, email: "leak-canary@example.com")
    allow(user).to receive(:name).and_return("Leak Canary")

    offenders = every_flavor_text(user:).select do |t|
      t.include?(user.email) || t.include?("Leak Canary") || t.include?(CGI.escape(user.email))
    end

    expect(offenders.uniq).to be_empty,
                              "a tagline leaks user data:\n  #{offenders.uniq.join("\n  ")}"
  end

  # Belt and braces: no link may leave for a host we have not thought about.
  # The survivors are jokes with no user data in them (YouTube, a barbecue
  # restaurant, Google's Santa tracker).
  it "only links to hosts that were reviewed" do
    # github.com is Fuime's own source repository (constants.github_url). AGPL
    # positively wants that link; what it must not say is "hack on hcb", which
    # is what it said.
    allowed = %w[www.youtube.com santatracker.google.com www.dinosaurbbq.org github.com]

    hosts = every_flavor_text.flat_map { |t| t.scan(/https?:\/\/([a-z0-9.-]+)/i) }.flatten.uniq

    expect(hosts - allowed).to be_empty, "unreviewed outbound host in a tagline: #{(hosts - allowed).join(", ")}"
  end

  it "still produces a tagline" do
    expect(described_class.new.generate).to be_present
  end
end
