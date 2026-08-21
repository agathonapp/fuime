# frozen_string_literal: true

require "rails_helper"

# Fuime: /learn — the starter templates and the money lessons.
#
# Three things are being protected here, and only the first is about the page
# rendering at all.
#
#   1. It is reachable without an account. The whole reason it exists is that the
#      templates were previously locked behind the sign-up flow, at the exact
#      moment somebody is asked "what is your business" — the worst possible
#      moment to be reading them for the first time.
#   2. **Nothing on it suggests a price.** Same §8.3 D2 constraint as
#      Fuime::ServiceCatalog and Fuime::OffersController, asserted here against
#      the RENDERED pages, because that is the form a reader actually meets and
#      the constant-level spec cannot see prose written in a partial.
#   3. It never renders anybody's venture data. It is an indexable page that
#      takes a venture slug in the query string, which is precisely the shape of
#      thing that leaks — see the privacy block at the bottom.
RSpec.describe "Learn", type: :request do
  include ActionView::Helpers::NumberHelper

  # The real login dance, copied from fuime_security_review_fixes_spec.
  #
  # Deliberately NOT the SessionSupport factory shortcut: in a request spec that
  # module's method name is already taken by
  # ActionDispatch::Integration::Runner, so including it shadows Rails' own
  # method and every `get` in the file dies with "missing keyword: :verified".
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  # The two shapes a suggested rate takes. Numbers themselves are allowed —
  # the fee arithmetic is real and the threshold in the tax lesson is a fact —
  # so this looks for a rate being RECOMMENDED, not for the presence of a digit.
  # A method rather than a constant: a constant defined inside a describe block
  # leaks into the enclosing namespace, and this one has a generic enough name to
  # collide with somebody else's.
  def suggested_rate_patterns
    [
      /\b(charge|price|rate)s?\s+(about|around|roughly|typically|usually|approximately)\b/i,
      /\b(typical|average|going|suggested|recommended)\s+(rate|price|charge)\b/i,
      /\bmost people charge\b/i,
      /\bwe recommend charging\b/i
    ]
  end

  def expect_no_suggested_rate(body, where)
    suggested_rate_patterns.each do |pattern|
      expect(body).not_to match(pattern), "#{where} suggests a rate"
    end
  end

  describe "reading it without an account" do
    it "serves the index" do
      get learn_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Start from a template")
      expect(response.body).to include(Fuime::Playbook.lessons.first.title)
    end

    it "serves every starter template" do
      Fuime::ServiceCatalog.sellable.each do |service|
        get learn_template_path(slug: service.key)

        expect(response).to have_http_status(:ok), "#{service.key} did not render"
        expect(CGI.unescapeHTML(response.body)).to include(service.name)
      end
    end

    it "serves every lesson" do
      Fuime::Playbook.lessons.each do |lesson|
        get learn_lesson_path(slug: lesson.key)

        expect(response).to have_http_status(:ok), "#{lesson.key} did not render"
        expect(CGI.unescapeHTML(response.body)).to include(lesson.title)
      end
    end

    # A lesson listed on the index that 500s when opened is the failure mode the
    # shared key in Fuime::Playbook::Lesson exists to prevent; this is the
    # end-to-end version of that guarantee.
    it "links to nothing it cannot serve" do
      get learn_path
      body = response.body

      Fuime::Playbook.lessons.each do |lesson|
        expect(body).to include(learn_lesson_path(slug: lesson.key))
      end
      Fuime::ServiceCatalog.sellable.each do |service|
        expect(body).to include(learn_template_path(slug: service.key))
      end
    end

    it "sends an unknown slug back to the index rather than erroring" do
      get learn_lesson_path(slug: "how-to-get-rich")
      expect(response).to redirect_to(learn_path)

      get learn_template_path(slug: "crypto-arbitrage")
      expect(response).to redirect_to(learn_path)
    end

    # Written content only, no minor's data — see INDEXABLE_CONTROLLER_PATHS.
    it "is indexable" do
      get learn_path

      expect(response.headers["X-Robots-Tag"]).not_to eq("none")
    end
  end

  describe "no page suggests what to charge" do
    it "holds on the index" do
      get learn_path
      expect_no_suggested_rate(CGI.unescapeHTML(response.body), "the index")
    end

    it "holds on every template" do
      Fuime::ServiceCatalog.sellable.each do |service|
        get learn_template_path(slug: service.key)
        expect_no_suggested_rate(CGI.unescapeHTML(response.body), "template #{service.key}")
      end
    end

    it "holds on every lesson" do
      Fuime::Playbook.lessons.each do |lesson|
        get learn_lesson_path(slug: lesson.key)
        expect_no_suggested_rate(CGI.unescapeHTML(response.body), "lesson #{lesson.key}")
      end
    end

    # The positive half. "No suggested price" is trivially satisfied by a page
    # that says nothing about pricing at all, which would leave a sixteen-year-old
    # with no idea the number is theirs to pick.
    it "tells the reader the number is theirs" do
      get learn_lesson_path(slug: "pricing")

      expect(CGI.unescapeHTML(response.body)).to match(/nobody can tell you what to charge/i)
    end

    # Two lessons branch on the structural flag, because the two models pay
    # differently and a page that described the wrong one would be worse than no
    # page. The suite clears the flag per example (spec/support/structural_flags),
    # so without this tag the merchant-of-record halves — the ones production
    # actually runs — are never rendered by any spec at all.
    it "holds on every lesson under merchant-of-record too", :merchant_of_record do
      Fuime::Playbook.lessons.each do |lesson|
        get learn_lesson_path(slug: lesson.key)

        expect(response).to have_http_status(:ok), "#{lesson.key} did not render under MoR"
        expect_no_suggested_rate(CGI.unescapeHTML(response.body), "lesson #{lesson.key} (MoR)")
      end
    end

    it "explains the fee floor only where one exists", :merchant_of_record do
      get learn_lesson_path(slug: "what-fuime-takes")

      body = CGI.unescapeHTML(response.body)
      expect(body).to include(number_to_currency(Event::Plan::MINIMUM_FEE_CENTS / 100.0))
      expect(body).to match(/Fuime LLC/)
    end
  end

  # Founder's instruction, 2026-08-20: these pages are read by children and must
  # not read like a machine wrote them. The em dash is the specific tell that was
  # called out, so it is asserted rather than left to whoever edits next. Use a
  # full stop, a comma, or a pair of brackets.
  describe "the house style" do
    def every_learn_page
      pages = [learn_path] +
              Fuime::Playbook.lessons.map { |l| learn_lesson_path(slug: l.key) } +
              Fuime::ServiceCatalog.sellable.map { |s| learn_template_path(slug: s.key) }

      pages.each do |path|
        get path
        # `<main>` only: the surrounding layout and footer are not this page's
        # copy and are not this spec's business.
        yield path, CGI.unescapeHTML(response.body[/<main.*?<\/main>/m].to_s)
      end
    end

    it "uses no em dashes anywhere a reader can see one" do
      every_learn_page do |path, body|
        expect(body).not_to include("\u2014"), "#{path} contains an em dash"
      end
    end

    it "uses no en dashes between words either" do
      every_learn_page do |path, body|
        expect(body).not_to match(/\w\s\u2013\s\w/), "#{path} contains an en dash used as punctuation"
      end
    end
  end

  describe "the ?venture= parameter" do
    let(:teen) { create(:user, birthday: 16.years.ago.to_date, verified: true) }
    let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
    let(:stranger) { create(:user, birthday: 30.years.ago.to_date, verified: true) }
    let(:event) { create(:event) }
    let(:service) { Fuime::ServiceCatalog.find("lawn_and_garden") }

    before do
      create(:organizer_position, event:, user: teen)
      create(:guardianship, :active, guardian:, minor: teen)
    end

    it "turns each thing-to-list into a link that pre-fills the operator's own form" do
      login_as!(teen)

      get learn_template_path(slug: service.key, venture: event.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add to my storefront")
      expect(CGI.unescapeHTML(response.body)).to include(CGI.escape(service.offer_ideas.first[:name]))
    end

    # The link writes into the pricing form, and a guardian deliberately does not
    # set their kid's rates — the same split Fuime::OffersController enforces.
    it "offers nothing to write for somebody who may not price the work" do
      login_as!(guardian)

      get learn_template_path(slug: service.key, venture: event.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Add to my storefront")
    end

    it "ignores a venture the reader has nothing to do with" do
      login_as!(stranger)

      get learn_template_path(slug: service.key, venture: event.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Add to my storefront")
    end

    it "ignores a slug that is not a venture at all" do
      login_as!(teen)

      get learn_template_path(slug: service.key, venture: "not-a-real-venture")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Add to my storefront")
    end

    # The one that matters on an indexable page: a signed-out reader handing it
    # somebody else's slug must learn nothing about that venture.
    it "never renders a venture's name to a signed-out reader" do
      event.update!(name: "Aoife's Extremely Specific Lawn Care")

      get learn_template_path(slug: service.key, venture: event.slug)

      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).not_to include("Aoife's Extremely Specific Lawn Care")
      expect(response.body).not_to include("Add to my storefront")
    end
  end

  describe "the pre-filled offer form" do
    let(:teen) { create(:user, birthday: 16.years.ago.to_date, verified: true) }
    let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
    let(:event) { create(:event) }

    before do
      create(:organizer_position, event:, user: teen)
      create(:guardianship, :active, guardian:, minor: teen)
      login_as!(teen)
    end

    it "carries the words through from the template" do
      get fuime_offers_path(event_slug: event.slug, name: "Front and back lawn mow", unit_label: "per visit")

      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).to include("Front and back lawn mow")
      expect(CGI.unescapeHTML(response.body)).to include("per visit")
    end

    # The point of the allowlist. A price in the query string would be a Fuime
    # suggested rate that needed no code change to introduce — just a link.
    it "refuses to carry a price through, however it is spelled" do
      get fuime_offers_path(event_slug: event.slug, name: "Lawn mow", price: "35", price_cents: "3500")

      expect(response).to have_http_status(:ok)
      # The words arrived, so the pre-fill definitely ran on this request…
      expect(CGI.unescapeHTML(response.body)).to include("Lawn mow")
      # …and the price box is still empty.
      expect(response.body).not_to match(/value="35(\.0+)?"/)
      expect(response.body).not_to match(/value="3500"/)
    end

    it "creates nothing on its own" do
      expect {
        get fuime_offers_path(event_slug: event.slug, name: "Lawn mow", unit_label: "per visit")
      }.not_to change(Fuime::Offer, :count)
    end
  end

end
