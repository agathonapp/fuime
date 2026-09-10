# frozen_string_literal: true

# G10 — prove a merchant-of-record Checkout sale lands on the venture ledger.
#
# Production money-in is MoR (`FEATURE_MERCHANT_OF_RECORD=true` in render.yaml),
# not Connect. The charge is on Fuime's platform account; the webhook is
# POST /fuime/webhooks/stripe; the recorder is Fuime::PaymentWebhookHandler.
#
# Full walkthrough: docs/fuime/MOR_WEBHOOK_PASS.md
#
#   rake fuime:mor_webhook_pass:listen     # print the stripe listen command
#   rake fuime:mor_webhook_pass:charge     # platform PI → handler → pending lines
#   rake fuime:mor_webhook_pass:backfill   # recover succeeded PIs with no ledger row
#   rake fuime:mor_webhook_pass:settle     # pending → CanonicalTransaction
#
# Test mode is enforced twice: development-only, and Stripe::Balance.livemode
# must be false.

namespace :fuime do
  namespace :mor_webhook_pass do
    SLUG = ENV.fetch("SLUG", "mor-webhook-pass")

    def mor_abort_unless_test!
      abort "development only — this talks to Stripe" unless Rails.env.development?
      bal = Stripe::Balance.retrieve({}, { api_key: StripeService.secret_key })
      abort "!! livemode=true — refusing to continue" if bal.livemode
    end

    def mor_opts = { api_key: StripeService.secret_key }

    def mor_venture
      Event.find_by!(slug: SLUG)
    end

    def mor_step(name)
      puts "\n── #{name} " + ("─" * [1, 60 - name.length].max)
      yield
    rescue Stripe::StripeError => e
      puts "  ✗ Stripe rejected it: #{e.class}"
      puts "    #{e.message}"
      puts "    param: #{e.param}" if e.respond_to?(:param) && e.param
      abort "  Fix the parameter shape, then re-run this task."
    end

    desc "Print the stripe listen command for the MoR platform endpoint"
    task listen: :environment do
      puts <<~TXT
        # 1. stripe login against Fuime's TEST account (not Hack Club Shop).
        #    `stripe config --list` must show the same acct_ as StripeService.
        stripe login

        # 2. Forward PLATFORM events to the Fuime controller. The path is
        #    /fuime/webhooks/stripe — not /webhooks/stripe (that 404s).
        stripe listen \\
          --forward-to localhost:3000/fuime/webhooks/stripe \\
          --events payment_intent.succeeded,checkout.session.completed,checkout.session.async_payment_succeeded,charge.refunded,charge.dispute.created

        # 3. Either leave FUIME_STRIPE_WEBHOOK_SECRET blank (development accepts
        #    unsigned events while STRIPE_MODE is test) OR paste the whsec_ the
        #    CLI prints. A local unsigned success does not prove production.

        # 4. Pay a storefront /pay/<slug>/<offer> with 4242 4242 4242 4242.
        #    Expect two pending lines (gross + fee) on the venture page, and a
        #    "more from recent sales" note on the balance. Then:
        #      SLUG=<slug> rake fuime:mor_webhook_pass:settle

        See docs/fuime/MOR_WEBHOOK_PASS.md
      TXT
    end

    desc "1. Local records: teen, venture (MoR — no connected account)"
    task setup: :environment do
      mor_abort_unless_test!
      mor_step("setup") do
        teen = User.find_by(email: "mor-pass-teen@fuime.test") ||
               User.create!(email: "mor-pass-teen@fuime.test", full_name: "MoR Pass Teen",
                            birthday: 15.years.ago.to_date, verified: true)

        venture = Event.find_by(slug: SLUG) ||
                  Event.create!(name: "MoR Webhook Pass", slug: SLUG,
                                can_front_balance: false, is_public: true)

        unless venture.organizer_positions.exists?(user: teen)
          OrganizerPositionInvite.create!(event: venture, user: teen, sender: teen, role: :manager)
                                 .accept(show_onboarding: false)
        end

        puts "  ✓ #{venture.name} (#{venture.slug}) — teen #{teen.email}"
        puts "    FEATURE_MERCHANT_OF_RECORD=#{ENV['FEATURE_MERCHANT_OF_RECORD'].inspect}"
        puts "    (handler records test-mode events even when the flag is off)"
      end
    end

    desc "2. Platform PaymentIntent → PaymentWebhookHandler → pending ledger lines"
    task charge: :environment do
      mor_abort_unless_test!
      intent = nil
      mor_step("platform charge (MoR / test card)") do
        fee = mor_venture.fuime_fee_cents_on(25_00)
        intent = Stripe::PaymentIntent.create(
          {
            amount: 25_00, currency: "usd",
            payment_method: "pm_card_visa", confirm: true,
            automatic_payment_methods: { enabled: true, allow_redirects: "never" },
            description: "MoR webhook pass — first sale",
            metadata: {
              fuime_event_id: mor_venture.id,
              fuime_event_name: mor_venture.name,
              fuime_fee_cents: fee
            }
          },
          mor_opts
        )
        puts "  ✓ #{intent.id} #{intent.status} — $#{intent.amount / 100.0} on the PLATFORM account"
        abort "  payment did not succeed" unless intent.status == "succeeded"
      end

      mor_step("record into the ledger (PaymentWebhookHandler)") do
        stripe_event = Stripe::Event.list({ type: "payment_intent.succeeded", limit: 20 }, mor_opts)
                                    .data
                                    .find { |ev| ev.data.object.id == intent.id }
        abort "  no payment_intent.succeeded event yet — re-run in a few seconds" if stripe_event.nil?

        Fuime::PaymentWebhookHandler.new(event: stripe_event).handle

        payment = Fuime::VentureLedger.find_row(Fuime::VentureLedger.payment_key(intent.id))
        fee_row = Fuime::VentureLedger.find_row(Fuime::VentureLedger.fee_key(intent.id))
        abort "  handler ran but no payment line reached the venture" if payment.nil?

        mapped = Fuime::VentureLedger.event_for_row(payment)
        abort "  payment row exists but is not mapped to #{mor_venture.slug}" unless mapped&.id == mor_venture.id
        puts "  ✓ pending payment #{payment.donation_transaction_id}: $#{payment.amount_cents / 100.0}"
        puts "    fee line: #{fee_row ? "$#{fee_row.amount_cents / 100.0}" : "(none — fee-waived plan)"}"
        puts "    mapped to event_id=#{mapped.id}"
        puts "    replay is safe — run this task again after `stripe events resend #{stripe_event.id}`"

        before = RawPendingDonationTransaction.where(
          donation_transaction_id: Fuime::VentureLedger.payment_key(intent.id)
        ).count
        Fuime::PaymentWebhookHandler.new(event: stripe_event).handle
        after = RawPendingDonationTransaction.where(
          donation_transaction_id: Fuime::VentureLedger.payment_key(intent.id)
        ).count
        abort "  idempotency failed — replay created a second payment row" unless before == after && after == 1
        puts "  ✓ replay kept payment rows at #{after}"
      end
    end

    desc "3. Recover succeeded platform PIs that have no ledger row"
    task backfill: :environment do
      mor_abort_unless_test!
      mor_step("MissedMorPaymentSweep") do
        hours = ENV.fetch("HOURS", "24").to_i
        result = Fuime::MissedMorPaymentSweep.sweep!(since: hours.hours.ago)
        puts "  ✓ posted=#{result[:posted]} skipped=#{result[:skipped]} (last #{hours}h)"
      end
    end

    desc "4. Settle available pendings into CanonicalTransaction"
    task settle: :environment do
      mor_abort_unless_test!
      mor_step("settlement sweep (ConnectSettlementSweep, platform balance)") do
        before = mor_venture.balance_v2_cents
        pending = Fuime::PayablesLedger.new(event: mor_venture).pending_sales_cents
        count = Fuime::ConnectSettlementSweep.new(event: mor_venture).sweep!
        puts "  ✓ settled #{count} pending line(s)"
        puts "    pending sales were $#{pending / 100.0}"
        puts "    venture balance: $#{before / 100.0} -> $#{mor_venture.reload.balance_v2_cents / 100.0}"
      end
    end
  end
end
