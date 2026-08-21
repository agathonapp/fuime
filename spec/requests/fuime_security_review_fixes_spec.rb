# frozen_string_literal: true

require "rails_helper"

# Fuime: the security review of 2026-08-20, as executable assertions.
#
# One file rather than a patch to each existing spec, deliberately: every example
# here is a hole that was open in production-shaped code, and keeping them together
# means the next person can read what was wrong in one sitting. Each `describe`
# names its finding id from the review.
#
# The rule these follow: assert the HOLE is closed, on the real object, rather than
# asserting the guard exists. A spec that checks `sanitize_memo_text` strips
# brackets passes whether or not anything calls it — which is exactly how the
# memo-injection fix of 2026-08-16 came to be incomplete.
RSpec.describe "Security review fixes (2026-08-20)", type: :request do
  # The real login dance, copied from fuime_payout_batches_admin_spec.
  #
  # Deliberately NOT `SessionSupport#create_session`: in a request spec that name
  # is already taken by ActionDispatch::Integration::Runner, which calls it to
  # build the integration session — so including SessionSupport here shadows
  # Rails' own method and every `get` in the file dies with
  # "missing keyword: :verified" from inside `method_missing`.
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end
  # ── F-01 ────────────────────────────────────────────────────────────────────
  #
  # `is_public` meant two things at once: "my storefront is public" (its label in
  # the Fuime UI, and what the storefront and checkout gate on) and "my books are
  # public" (what EventPolicy granted on). Every venture is created with it true.
  describe "F-01: a public storefront does not publish the ledger" do
    let(:event) { create(:event, is_public: true) }

    # Every predicate that was aliased to, or copied, `show?`.
    #
    # A `let` rather than a constant: a constant defined inside a describe block
    # leaks into the enclosing namespace for the whole suite, so two specs that
    # each name their own LEDGER_QUERIES would silently share whichever loaded
    # last (Lint/ConstantDefinitionInBlock).
    let(:ledger_queries) do
      %i[
        show? transactions? transactions_list? team? balance_transactions?
        money_movement? users_chart? stats? balance_by_date? statements?
        async_balance? transaction_heatmap?
      ]
    end

    it "keeps the books private from a stranger even with the storefront on" do
      policy = EventPolicy.new(nil, event)

      ledger_queries.each do |query|
        message = "expected #{query} to be private for a signed-out visitor, " \
                  "but a public storefront still granted it"
        expect(policy.public_send(query)).to be(false), message
      end
    end

    it "still lets the team read everything" do
      member = create(:user, birthday: 30.years.ago.to_date)
      create(:organizer_position, event:, user: member, role: :member)

      policy = EventPolicy.new(member, event)
      ledger_queries.each do |query|
        expect(policy.public_send(query)).to be(true), "expected #{query} to stay readable by a member"
      end
    end

    # The feature is disabled, not deleted (CLAUDE.md Rule 2) — a venture that
    # genuinely wants to publish its books can still say so.
    it "publishes the ledger when the venture opts in explicitly" do
      event.update!(publishes_ledger: true)

      expect(EventPolicy.new(nil, event).transactions?).to be true
      expect(EventPolicy.new(nil, event).team?).to be true
    end

    it "defaults the opt-in to off" do
      expect(create(:event).publishes_ledger).to be false
    end

    # Taking the storefront down withdraws the venture from public view; a stale
    # opt-in must not keep the books up behind it.
    # Built rather than updated into: Event has an `after_update_commit` on
    # `is_public_previously_changed?` that reaches for `User.system_user`, which no
    # test seeds. The subject here is the policy, not that callback.
    it "requires both flags, so turning the storefront off also closes the books" do
      withdrawn = create(:event, is_public: false, publishes_ledger: true)

      expect(EventPolicy.new(nil, withdrawn).transactions?).to be false
    end

    it "does not serve a venture's revenue on the unauthenticated stats endpoint" do
      storefront_only = create(:event, is_public: true, publishes_ledger: false)
      get "/project_stats", params: { slug: storefront_only.slug }
      expect(response).to have_http_status(:not_found)

      opted_in = create(:event, is_public: true, publishes_ledger: true)
      get "/project_stats", params: { slug: opted_in.slug }
      expect(response).to have_http_status(:ok)
    end
  end

  # ── F-02 ────────────────────────────────────────────────────────────────────
  #
  # Age is the input every protective control derives from, and `:birthday` was a
  # permitted attribute on the ordinary settings form.
  describe "F-02: a date of birth is write-once" do
    let(:minor) { create(:user, birthday: 15.years.ago.to_date) }

    around do |example|
      Current.set(session: nil) { example.run }
    end

    it "lets a user set one for the first time" do
      stub = create(:user, :unknown_age)
      Current.set(session: build_stubbed_session(stub)) do
        expect(stub.update(birthday: 20.years.ago.to_date)).to be true
      end
    end

    it "refuses to let a minor re-age themselves into adulthood" do
      Current.set(session: build_stubbed_session(minor)) do
        expect(minor.update(birthday: 36.years.ago.to_date)).to be false
        expect(minor.errors[:birthday].join).to include("can't be changed here")
      end

      expect(minor.reload.known_adult?).to be false
    end

    it "still allows an admin to correct one" do
      admin = create(:user, :make_admin)

      Current.set(session: build_stubbed_session(admin)) do
        expect(minor.update(birthday: 16.years.ago.to_date)).to be true
      end
    end

    it "refuses a half-authenticated session outright" do
      unverified = User::Session.new(user: minor, expiration_at: 1.day.from_now, verified: false)

      Current.set(session: unverified) do
        expect(minor.update(birthday: 36.years.ago.to_date)).to be false
      end
    end

    # Console, jobs, seeds. Reported rather than blocked — see
    # Errors::PrivilegedBirthdayChange.
    it "allows a change with no signed-in actor, and reports it" do
      expect(Rails.error).to receive(:report).with(
        an_instance_of(Errors::PrivilegedBirthdayChange), hash_including(handled: true)
      )

      expect(minor.update(birthday: 16.years.ago.to_date)).to be true
    end

    # `verified: true` is load-bearing: User::Session#user returns nil until 2FA
    # completes, so an unverified session leaves `Current.user` nil and the guard
    # takes its no-actor branch. (It now refuses that case explicitly — see the
    # example below.)
    def build_stubbed_session(user)
      User::Session.new(user:, expiration_at: 1.day.from_now, verified: true)
    end
  end

  # ── F-05 ────────────────────────────────────────────────────────────────────
  #
  # `accepts_payments?` asked about vetting, category and age — and about none of
  # the three states in which somebody had already said this venture is not
  # trading. `financially_frozen?` was the worst, because PayableAssessment
  # already refused to PAY a frozen venture: money in, none out.
  describe "F-05: a venture nobody wants trading cannot take payments", :merchant_of_record do
    # Sellable for real, not stubbed: this block's subject IS #accepts_payments?,
    # so stubbing it (as the other public-page specs reasonably do) would test
    # nothing. Under merchant-of-record that needs vetting approved (the factory
    # default), an eligible category, and no under-16 operator — so this venture
    # has an adult operator and sells a service.
    let(:event) do
      create(:event, is_public: true, business_category: "services").tap do |e|
        create(:organizer_position, event: e, user: create(:user, birthday: 30.years.ago.to_date))
        expect(e.accepts_payments?).to be(true), "fixture should be sellable before each case"
      end
    end

    it "refuses when payments are frozen" do
      event.update!(financially_frozen: true)

      expect(event.accepts_payments?).to be false
      expect(event.selling_blockers.join).to match(/frozen/i)
    end

    it "refuses when an admin has hidden the venture" do
      event.update!(hidden_at: Time.current)

      expect(event.accepts_payments?).to be false
      expect(event.selling_blockers.join).to match(/hidden/i)
    end

    it "refuses a demo venture, so a real card cannot be charged against fake data" do
      event.update!(demo_mode: true)

      expect(event.accepts_payments?).to be false
      expect(event.selling_blockers.join).to match(/demo/i)
    end

    it "does not serve a hidden venture's storefront" do
      event.update!(hidden_at: Time.current)

      get "/b/#{event.slug}"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ── F-09 ────────────────────────────────────────────────────────────────────
  #
  # The bracketed key is the classification scheme. `.sanitize_memo_text` was
  # called at two input boundaries and never at the sink, so `Event#name` — which
  # validates presence and nothing else — reached the classifier through
  # `memo_for`'s "Payment to #{venture.name}" fallback.
  describe "F-09: a memo cannot forge a ledger key" do
    it "strips brackets from the prose half of a settled memo" do
      memo = Fuime::VentureLedger.settled_memo("fuime_pi_abc", "Mow [fuime_payout_x")

      expect(memo).to eq("Mow fuime_payout_x [fuime_pi_abc]")
    end

    it "leaves the real key intact so the classifier still works" do
      memo = Fuime::VentureLedger.settled_memo("fuime_fee_abc", "Fuime platform fee")

      expect(Fuime::VentureLedger.memo_carries_key?(memo)).to be true
    end

    # The one that matters: a venture NAME reaching the classifier. Asserted on
    # PayablesLedger's real query rather than on the sanitiser, because the
    # sanitiser was already correct — nothing called it here.
    it "does not let a venture's own name classify its sales as already paid out" do
      event = create(:event, name: "Acme [fuime_payout_")
      ledger = Fuime::VentureLedger.new(event:)

      ledger.post_settled!(
        key: Fuime::VentureLedger.payment_key("pi_forged"),
        amount_cents: 2_500,
        memo: "Payment to #{event.name}",
        date: Date.current
      )

      payables = Fuime::PayablesLedger.new(event:)
      expect(payables.gross_sales_cents).to eq(2_500)
      expect(payables.paid_out_cents).to eq(0)
    end

    it "strips brackets from a pending memo on the way in" do
      event = create(:event, name: "Acme [fuime_fee_x")

      raw = Fuime::VentureLedger.new(event:).post!(
        key: "fuime_pi_pending", amount_cents: 500,
        memo: "Payment to #{event.name}", date: Date.current
      )
      cpt = CanonicalPendingTransaction.find_by(raw_pending_donation_transaction_id: raw.id)

      expect(cpt.memo).not_to include("[")
    end
  end

  # ── F-03 ────────────────────────────────────────────────────────────────────
  #
  # Signals, not a block: every one of these is true of some real family, which is
  # why they are surfaced to the admin who already approves every payout batch
  # rather than used to refuse anything.
  describe "F-03: a self-signed guardianship is visible to a reviewer" do
    let(:minor) { create(:user, email: "ada@example.com", birthday: 16.years.ago.to_date) }

    it "flags a guardian who shares the minor's browser and email alias" do
      guardian = create(:user, email: "ada+mum@example.com", birthday: 40.years.ago.to_date)
      guardianship = create(:guardianship, :active, minor:, guardian:)

      create(:user_session, user: minor, fingerprint: "same-browser")
      create(:user_session, user: guardian, fingerprint: "same-browser")

      signals = guardianship.self_signed_signals
      expect(signals).to include(a_string_matching(/same browser/i))
      expect(signals).to include(a_string_matching(/alias/i))
      expect(guardianship.self_signed_suspected?).to be true
    end

    it "does not flag an ordinary family on separate devices" do
      guardian = create(:user, email: "john@elsewhere.com", birthday: 40.years.ago.to_date)
      guardianship = create(:guardianship, :active, minor:, guardian:,
                                           invite_sent_at: 2.days.ago,
                                           agreement_signed_at: 1.day.ago)

      create(:user_session, user: minor, fingerprint: "teen-laptop")
      create(:user_session, user: guardian, fingerprint: "parent-phone")
      create(:user_session, user: guardian, fingerprint: "parent-phone")

      expect(guardianship.self_signed_suspected?).to be false
    end

    it "says nothing about a guardianship nobody has accepted" do
      pending_guardianship = create(:guardianship, minor:,
                                                   guardian: create(:user, birthday: 40.years.ago.to_date))

      expect(pending_guardianship.self_signed_signals).to be_empty
    end
  end

  # ── F-08 ────────────────────────────────────────────────────────────────────
  #
  # The session is Rails' default COOKIE store, so a plaintext key in the flash was
  # a live credential written to the browser's cookie jar.
  describe "F-08: a minted API key never travels in a cookie" do
    let(:event) { create(:event) }
    let(:operator) { create(:user, birthday: 30.years.ago.to_date, verified: true) }

    before do
      create(:organizer_position, event:, user: operator, role: :manager)
      login_as!(operator)
    end

    it "shows the key in the response that created it, and puts no secret in the flash" do
      post "/#{event.slug}/developer", params: { name: "Replit bot" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Fuime::ApiKey::PREFIX)
      expect(flash.to_hash.values.join).not_to include(Fuime::ApiKey::PREFIX)
    end
  end

  # ── F-13 ────────────────────────────────────────────────────────────────────
  describe "F-13: the public commerce pages are indexable and nothing else is" do
    let(:event) { create(:event, is_public: true) }

    it "allows the directory to be indexed" do
      get "/directory"
      expect(response.headers["X-Robots-Tag"]).not_to eq("none")
    end

    it "still forbids indexing a venture's dashboard" do
      operator = create(:user, birthday: 30.years.ago.to_date, verified: true)
      create(:organizer_position, event:, user: operator, role: :member)
      login_as!(operator)

      get "/#{event.slug}"
      expect(response.headers["X-Robots-Tag"]).to eq("none")
    end
  end
end
