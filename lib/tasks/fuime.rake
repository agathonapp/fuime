# frozen_string_literal: true

namespace :fuime do
  # Approving a transfer requires a Governance::Admin::Transfer::Limit row for
  # the approving admin — without one, GovernanceService::Admin::Transfer::
  # Approval refuses with "does not have an admin transfer limit configured".
  # db/seeds.rb grants one to the seeded user; nothing else in the app does, and
  # there is no UI for it, so an admin made by `fuime:make_admin` hits a wall
  # with no way out of it from the browser.
  #
  # A day's worth of approvals, not a blank cheque: the limit is a governance
  # control (24h rolling window, see Limit::WINDOW_DURATION), and defaulting it
  # to something enormous would quietly retire the control instead of
  # configuring it. Raise it deliberately with fuime:set_transfer_limit.
  def ensure_transfer_limit!(user, amount_cents: 10_000_00)
    limit = Governance::Admin::Transfer::Limit.find_or_initialize_by(user:)
    existed = limit.persisted?

    # `user_is_admin` runs `on: :create`, so the user must already be an admin
    # by the time this is called.
    limit.amount_cents = amount_cents unless existed
    limit.save!

    puts "  Transfer limit: #{ActionController::Base.helpers.number_to_currency(limit.amount_cents / 100.0)}" \
         "#{existed ? ' (already configured, left alone)' : ' (created)'}"
    limit
  end

  desc "Make a user an admin by email"
  task :make_admin, [:email] => :environment do |_t, args|
    email = args[:email]

    if email.blank?
      puts "Usage: rake fuime:make_admin[email@example.com]"
      exit 1
    end

    user = User.find_by(email: email)

    if user.nil?
      puts "User not found with email: #{email}"
      puts "Creating new admin user..."

      # Create a new user with admin access
      user = User.new(
        email: email,
        full_name: "Fuime Admin",
        access_level: :superadmin,
        verified: true
      )

      if user.save(validate: false)
        puts "Created new superadmin user: #{email}"
      else
        puts "Failed to create user: #{user.errors.full_messages.join(', ')}"
        exit 1
      end
    else
      user.update!(access_level: :superadmin, verified: true)
      puts "Made #{email} a superadmin!"
    end

    puts "User details:"
    puts "  ID: #{user.id}"
    puts "  Email: #{user.email}"
    puts "  Access Level: #{user.access_level}"
    ensure_transfer_limit!(user)
  end

  desc "Mark a phone number verified so a card can be issued (test mode only)"
  task :verify_phone, [:email, :phone_number] => :environment do |_t, args|
    if args[:email].blank?
      puts "Usage: rake fuime:verify_phone[email@example.com]"
      puts "       rake fuime:verify_phone[email@example.com,+12025550123]"
      puts "       (the number is optional if the user already has one on file)"
      exit 1
    end

    # This forges the result of an SMS verification, and a verified number is
    # what gates card issuing (StripeCardholderService::Create refuses without
    # one). Fine against test-mode Stripe, where a card spends nothing; a real
    # anti-fraud control anywhere else.
    #
    # Gated on StripeService.live? rather than Rails.env, because this fork
    # deliberately runs test-mode Stripe *in production* — RAILS_ENV would
    # refuse on the deployed demo, which is the one place this is needed.
    if StripeService.live?
      puts "Refusing: STRIPE_MODE=live. Verify the number for real."
      exit 1
    end

    user = User.find_by(email: args[:email])
    if user.nil?
      puts "User not found with email: #{args[:email]}"
      exit 1
    end

    # Saved separately: `on_phone_number_update` clears phone_number_verified
    # whenever the number changes, so setting both at once would undo itself.
    if args[:phone_number].present?
      user.phone_number = args[:phone_number]
      unless user.save
        # Phonelib rejects the reserved 555-01xx fictional range, which is the
        # first thing anyone reaches for. Say so instead of raising a backtrace.
        puts "Could not set that number: #{user.errors.full_messages.join('; ')}"
        exit 1
      end
    end

    if user.phone_number.blank?
      puts "#{user.email} has no phone number on file — pass one:"
      puts "  rake fuime:verify_phone[#{user.email},+12025550123]"
      exit 1
    end

    user.phone_number_verified = true
    unless user.save
      puts "Could not verify: #{user.errors.full_messages.join('; ')}"
      exit 1
    end

    puts "#{user.email}: #{user.phone_number} marked verified (Stripe mode: #{StripeService.mode})"
    puts "  Cards can now be issued to this user on non-Playground organizations."
  end

  desc "Set an admin's daily transfer approval limit, in dollars"
  task :set_transfer_limit, [:email, :dollars] => :environment do |_t, args|
    if args[:email].blank? || args[:dollars].blank?
      puts "Usage: rake fuime:set_transfer_limit[email@example.com,25000]"
      puts "       (dollars, not cents — 25000 means $25,000.00 per rolling 24h)"
      exit 1
    end

    user = User.find_by(email: args[:email])
    if user.nil?
      puts "User not found with email: #{args[:email]}"
      exit 1
    end

    unless user.admin?(override_pretend: true)
      puts "#{user.email} is not an admin — transfer limits only apply to admins."
      puts "Run rake fuime:make_admin[#{user.email}] first."
      exit 1
    end

    # BigDecimal, not Float, so "0.1" is exactly 10 cents.
    cents = (BigDecimal(args[:dollars].to_s) * 100).to_i

    limit = Governance::Admin::Transfer::Limit.find_or_initialize_by(user:)
    before = limit.persisted? ? limit.amount_cents : nil
    limit.amount_cents = cents
    limit.save!

    puts "#{user.email}: transfer limit " \
         "#{before ? "#{ActionController::Base.helpers.number_to_currency(before / 100.0)} → " : "set to "}" \
         "#{ActionController::Base.helpers.number_to_currency(cents / 100.0)} per rolling 24h"
    puts "  Used in the current window: " \
         "#{ActionController::Base.helpers.number_to_currency(limit.used_amount_cents / 100.0)}"
  end

  desc "List all admin users"
  task list_admins: :environment do
    admins = User.where(access_level: [:admin, :superadmin, :auditor])

    if admins.empty?
      puts "No admin users found."
    else
      puts "Admin users:"
      admins.each do |user|
        puts "  #{user.email} (#{user.access_level})"
      end
    end
  end
end
