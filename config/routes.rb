# frozen_string_literal: true

require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  get "up" => "rails/health#show", as: :rails_health_check
  get "/my_ip", to: "admin#my_ip"

  constraints AdminConstraint do
    mount Sidekiq::Web => "/sidekiq"
    mount MaintenanceTasks::Engine, at: "/maintenance_tasks"
    mount Flipper::UI.app(Flipper), at: "flipper", as: "flipper"
    mount PgHero::Engine, at: "pghero"
  end
  constraints AuditorConstraint do
    mount Audits1984::Engine => "/console"
    mount Blazer::Engine, at: "blazer"
    mount SchemaEndpoint.instance => "/schema"
  end
  get "/sidekiq", to: redirect("users/auth") # fallback if adminconstraint fails, meaning user is not signed in
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  concern :commentable do
    resources :comments, shallow: true, except: [:show, :index] do
      resources :reactions, only: [:update], controller: "comment/reactions", action: "react"
    end
  end

  # API documentation
  namespace :docs do
    resources :api, only: [] do
      collection do
        # This crazy nesting is to get Rails to generate meaningful route helpers
        get "v3(/*path)", to: "api#v3"
        get "/", to: redirect("/docs/api/v3")
      end
    end
  end

  # V3 API
  mount Api::V3 => "/"

  root to: "static_pages#index"
  get "stats", to: "stats#stats"
  get "stats_custom_duration", to: "stats#stats_custom_duration"
  get "stats/admin_receipt_stats", to: "stats#admin_receipt_stats"
  get "project_stats", to: "stats#project_stats"
  get "bookkeeping", to: "admin#bookkeeping"
  get "stripe_charge_lookup", to: "static_pages#stripe_charge_lookup"
  get "money-printer", to: "money_printer#index", as: :money_printer

  resources :raffles, only: [:new, :create]

  # Fuime: Guardian invite/accept flow
  #
  # NOTE: :show and :accept are token-addressed — the :id segment carries an
  # invite token, not a record id, because a guardian follows these links from
  # an email before they have an account. :revoke and :resend_invite are
  # id-addressed and authenticated; they are management actions, not invites.
  # GET /guardian is the guardian's own overview of the ventures they signed for
  # — the surface that makes agreement §3 ("You can see everything") real. It is
  # :index on this resource rather than a separate route because :show is
  # token-addressed, so the two never collide.
  resources :guardianships, only: [:index, :new, :create, :show], path: "guardian" do
    member do
      post :accept
      post :revoke
      post :resend_invite
      get :record
    end
  end

  # Fuime: Stripe webhooks.
  #
  # Two endpoints, not one, because Stripe scopes webhook endpoints separately for
  # the platform's own account and for connected accounts, and each has its own
  # signing secret. `stripe` takes payment events; `connect` takes the onboarding
  # lifecycle (`account.updated`).
  namespace :fuime do
    post "webhooks/stripe", to: "webhooks#stripe"
    post "webhooks/stripe/connect", to: "webhooks#connect"
  end

  # Fuime: Tax Tracker
  get "/:event_slug/taxes", to: "fuime/taxes#show", as: :fuime_taxes
  get "/:event_slug/taxes/download", to: "fuime/taxes#download_packet", as: :fuime_taxes_download

  # Fuime: guardian-owned Stripe payment setup for a venture.
  #
  # Note on `return`/`refresh`: these are NOT Stripe's `return_url`/`refresh_url`
  # parameters — those belong to Account Links, and this flow uses embedded
  # components, which have no redirect contract. They are Fuime's own paths, and
  # the embedded component's `setOnExit` callback navigates to `return`.
  # `refresh` exists because an Account Session client secret expires while the
  # page is open; it mints a new one rather than showing the guardian an error.
  get "/:event_slug/payments", to: "fuime/payment_setups#show", as: :fuime_payment_setup
  get "/:event_slug/payments/setup", to: "fuime/payment_setups#new", as: :new_fuime_payment_setup
  get "/:event_slug/payments/return", to: "fuime/payment_setups#return", as: :fuime_payment_setup_return
  get "/:event_slug/payments/refresh", to: "fuime/payment_setups#refresh", as: :fuime_payment_setup_refresh

  # Fuime: the embedded replacement for the Stripe Dashboard.
  #
  # Accounts are created with `stripe_dashboard.type = none`, so a guardian has
  # nowhere else to change a bank account, clear a document Stripe has flagged, or
  # download a 1099. `/manage` mounts Stripe's own components for all of that
  # inside Fuime; `/session` is the JSON endpoint their `fetchClientSecret`
  # callback calls, which is why it is a separate path rather than a value
  # rendered into the page — an Account Session expires while a management page
  # sits open, and refetching is the difference between a self-healing page and a
  # stale-secret error.
  get "/:event_slug/payments/manage", to: "fuime/payment_setups#manage", as: :fuime_payment_setup_manage
  get "/:event_slug/payments/session", to: "fuime/payment_setups#manage_session", as: :fuime_payment_setup_session

  # Fuime: the guardian supplying their own identity details, for `:cards_enabled`
  # ventures where `requirement_collection = application` makes that Fuime's job.
  # Payments-only ventures never reach here — Stripe collects from them directly via the
  # embedded component at /payments/setup above, and the controller redirects away.
  get "/:event_slug/payments/verify", to: "fuime/requirement_collections#show", as: :fuime_requirement_collection
  post "/:event_slug/payments/verify", to: "fuime/requirement_collections#create", as: :fuime_requirement_collection_submit

  # Fuime: moving money out. The teen asks (#create), the responsible adult decides
  # (#approve / #reject) — see Fuime::PayoutsController for why those are separate
  # authorizations rather than one "can manage payouts".
  #
  # #settle exists only for the school path, where approving a transfer and having
  # actually paid it are separate events performed by different people. On a family
  # venture Stripe's own webhook is what says the money landed and there is nothing
  # for a human to confirm.
  #
  # All four are POSTs on a member route rather than a PATCH on the request, because
  # each is a distinct decision being recorded, not an edit to a field.
  # FUIME: what the venture sells. See Fuime::Offer — the object that makes a
  # storefront a store rather than a tip jar.
  get "/:event_slug/offers", to: "fuime/offers#index", as: :fuime_offers
  post "/:event_slug/offers", to: "fuime/offers#create", as: :fuime_offers_create
  patch "/:event_slug/offers/:id", to: "fuime/offers#update", as: :fuime_offer
  post "/:event_slug/offers/:id/publish", to: "fuime/offers#publish", as: :fuime_offer_publish
  post "/:event_slug/offers/:id/unpublish", to: "fuime/offers#unpublish", as: :fuime_offer_unpublish
  post "/:event_slug/offers/:id/archive", to: "fuime/offers#archive", as: :fuime_offer_archive
  post "/:event_slug/offers/:id/restore", to: "fuime/offers#restore", as: :fuime_offer_restore

  get "/:event_slug/payouts", to: "fuime/payouts#index", as: :fuime_payouts
  post "/:event_slug/payouts", to: "fuime/payouts#create", as: :fuime_payouts_create
  post "/:event_slug/payouts/:id/approve", to: "fuime/payouts#approve", as: :fuime_payout_approve
  post "/:event_slug/payouts/:id/reject", to: "fuime/payouts#reject", as: :fuime_payout_reject
  post "/:event_slug/payouts/:id/settle", to: "fuime/payouts#settle", as: :fuime_payout_settle

  # Fuime: a school funding a student's venture ("$100 per A"). Money IN from the
  # school, as against the payout routes above which move it out.
  #
  # No request verb, deliberately — the school initiates and spends its own balance,
  # so unlike a payout there is nobody for it to ask. See
  # Fuime::SchoolAwardsController.
  # Fuime: the school's treasury page — putting its own money into its own Stripe
  # balance so there is something to award. Manager-only and not student-facing;
  # awards can only reattribute money that is already here. See
  # Fuime::SchoolFundingsController.
  get "/:event_slug/funding", to: "fuime/school_fundings#index", as: :fuime_school_fundings
  post "/:event_slug/funding", to: "fuime/school_fundings#create", as: :fuime_school_fundings_create

  get "/:event_slug/awards", to: "fuime/school_awards#index", as: :fuime_school_awards
  post "/:event_slug/awards", to: "fuime/school_awards#create", as: :fuime_school_awards_create
  post "/:event_slug/awards/:id/void", to: "fuime/school_awards#void", as: :fuime_school_award_void

  # Fuime: the venture's business cards. Note the verbs are split by WHO may do them,
  # not by REST tidiness — freeze is available to the teen (a lost card must be stoppable
  # immediately), unfreeze and limits are the guardian's alone. See Fuime::CardsController.
  get "/:event_slug/cards", to: "fuime/cards#index", as: :fuime_cards
  post "/:event_slug/cards", to: "fuime/cards#create", as: :fuime_cards_create
  patch "/:event_slug/cards/:id", to: "fuime/cards#update", as: :fuime_card
  post "/:event_slug/cards/:id/freeze", to: "fuime/cards#freeze", as: :fuime_card_freeze
  post "/:event_slug/cards/:id/unfreeze", to: "fuime/cards#unfreeze", as: :fuime_card_unfreeze
  delete "/:event_slug/cards/:id", to: "fuime/cards#destroy", as: :fuime_card_cancel

  # Fuime: the public directory of teen-run businesses. A listing, never a
  # dispatch — see Fuime::DirectoryController for why that distinction is
  # load-bearing rather than stylistic.
  get "/directory", to: "fuime/directory#index", as: :fuime_directory

  # Fuime: Public storefront
  get "/b/:slug", to: "fuime/storefronts#show", as: :fuime_storefront
  post "/b/:slug/pay", to: "fuime/checkouts#create", as: :fuime_storefront_pay

  resources :receipts, only: [:create, :destroy] do
    collection do
      post "link"
      get "link_modal"
    end

    member do
      post "reverse"
    end
  end

  scope :my do
    get "/", to: redirect("/"), as: :my

    get "settings", to: "users#edit", as: :my_settings

    # Fuime: the family plan. Page, upgrade checkout, and Stripe's own billing
    # portal for card changes and cancellation — Fuime never builds card forms.
    get "billing", to: "fuime/billing#show", as: :my_billing
    post "billing/subscribe", to: "fuime/billing#subscribe", as: :my_billing_subscribe
    post "billing/portal", to: "fuime/billing#portal", as: :my_billing_portal
    get "settings/address", to: "users#edit_address"
    get "settings/payouts", to: "users#edit_payout"
    resources :payout_methods, only: [:create, :update], controller: "legal_entity/payout_methods", path: "settings/payouts/methods" do
      member do
        patch :set_default
        patch :archive
      end
    end
    get "settings/previews", to: "users#edit_featurepreviews"
    get "settings/security", to: "users#edit_security"
    get "settings/notifications", to: "users#edit_notifications"
    get "settings/integrations", to: "users#edit_integrations"
    get "settings/admin", to: "users#edit_admin"
    get "payroll", to: "my#payroll", as: :my_payroll
    get "pay", to: "my#pay", as: :my_pay

    resources :payroll_positions, only: [] do
      resources :invoices, only: [:new, :create], controller: "payroll/invoices"
    end
    get "payroll_positions/:id", to: "payroll/positions#onboarding", as: :onboarding_payroll_position

    get "feed", to: "my#feed", as: :my_feed
    get "inbox", to: "my#inbox", as: :my_inbox
    get "activities", to: "my#activities", as: :my_activities
    post "toggle_admin_activities", to: "my#toggle_admin_activities", as: :toggle_admin_activities
    get "tasks", to: "my#tasks", as: :my_tasks
    get "reimbursements", to: "my#reimbursements", as: :my_reimbursements
    get "reimbursements_icon", to: "my#reimbursements_icon", as: :my_reimbursements_icon

    get "receipts", to: redirect("/my/inbox")
    post "receipts/upload", to: "static_pages#receipt", as: :my_receipts_upload
    get "missing_receipts", to: "my#missing_receipts_list", as: :my_missing_receipts_list
    get "missing_receipts_icon", to: "my#missing_receipts_icon", as: :my_missing_receipts_icon
    get "receipt_bin/suggested_pairings", to: "static_pages#suggested_pairings", as: :suggested_pairings

    post "receipt_report", to: "users#receipt_report", as: :trigger_receipt_report

    get "cards", to: "my#cards", as: :my_cards
    get "cards/shipping", to: "stripe_cards#shipping", as: :my_cards_shipping
  end

  resources :mailbox_addresses, only: [:create, :show] do
    member do
      post "activate"
    end
  end

  resources :suggested_pairings, only: [] do
    member do
      post "ignore"
      post "accept"
    end
  end

  post "receiptable/:receiptable_type/:receiptable_id/mark_no_or_lost", to: "receiptables#mark_no_or_lost", as: :receiptable_mark_no_or_lost

  # Feature-flags
  post "enable_feature", to: "features#enable_feature"
  post "disable_feature", to: "features#disable_feature"

  resources :users, only: [:show, :edit, :update], concerns: :commentable do
    collection do
      get "auth", to: "logins#new"
      get "webauthn/auth_options", to: "users#webauthn_options"
      post "toggle_pretend_is_not_admin", to: "users#toggle_pretend_is_not_admin"

      # SMS Auth
      post "start_sms_auth_verification", to: "users#start_sms_auth_verification"
      post "complete_sms_auth_verification", to: "users#complete_sms_auth_verification"
      post "toggle_sms_auth", to: "users#toggle_sms_auth"

      # Logout
      delete "logout", to: "users#logout"
      delete "logout_session", to: "users#logout_session"
      delete "revoke/:id", to: "users#revoke_oauth_application", as: "revoke_oauth_application"
      post "make_oauth_authorization_eternal/:id", to: "users#make_oauth_authorization_eternal", as: "make_authorization_eternal"

      # sometimes users refresh the login code page and get 404'd
      get "exchange_login_code", to: redirect("/users/auth", status: 301)
      get "login_code", to: redirect("/users/auth", status: 301)

      # For compatibility with the previous WebAuthn login flow
      get "webauthn", to: redirect("/users/auth")
    end
    member do
      get "address", to: "users#edit_address"
      get "payouts", to: "users#edit_payout"
      get "previews", to: "users#edit_featurepreviews"
      get "security", to: "users#edit_security"
      get "notifications", to: "users#edit_notifications"
      get "integrations", to: "users#edit_integrations"
      get "admin", to: "users#edit_admin"
      get "admin_details", to: "users#admin_details"
      get "admin_details_ach_transfers", to: "users#admin_details_ach_transfers"
      get "admin_details_check_deposits", to: "users#admin_details_check_deposits"
      get "admin_details_disbursements", to: "users#admin_details_disbursements"
      get "admin_details_emburse_cards", to: "users#admin_details_emburse_cards"
      get "admin_details_increase_checks", to: "users#admin_details_increase_checks"
      get "admin_details_invoices", to: "users#admin_details_invoices"
      get "admin_details_lob_checks", to: "users#admin_details_lob_checks"
      get "admin_details_missing_receipts", to: "users#admin_details_missing_receipts"
      get "admin_details_reimbursement_reports", to: "users#admin_details_reimbursement_reports"
      get "admin_details_stripe_cards", to: "users#admin_details_stripe_cards"
      get "admin_details_stripe_transactions", to: "users#admin_details_stripe_transactions"

      delete "logout_all", to: "users#logout_all"

      post "impersonate"
      post "unimpersonate"

      post "suppress_card_locking", to: "users#suppress_card_locking"
    end
    post "delete_profile_picture", to: "users#delete_profile_picture"
    post "generate_totp"
    post "enable_totp"
    post "disable_totp"
    post "generate_backup_codes"
    post "activate_backup_codes"
    post "disable_backup_codes"
    patch "stripe_cardholder_profile", to: "stripe_cardholders#update_profile"

    resources :webauthn_credentials, only: [:create, :destroy] do
      collection do
        get "register_options"
      end
    end
  end
  scope module: :users do
    resources "wrapped", only: :index do
      collection do
        get "data"
      end
    end

    resources "first", only: [:index, :create] do
      collection do
        get "welcome", to: "first#new"
        get "team", to: "first#team"
        post "verify_email", to: "first#verify_email"
        post "request_org_invite", to: "first#request_org_invite"
        delete "sign_out", to: "first#sign_out"
        get "macbook_qr_code"
      end
    end


    resources :email_updates, only: [] do
      collection do
        get "verify"
        get "authorize", to: "email_updates#authorize_change"
      end
    end
  end

  resources :logins, only: [:new, :create] do
    collection do
      get "login_preference", to: "logins#choose_login_preference", as: :choose_login_preference
      post "complete" # for webauthn
      post "reauthenticate"
    end
    member do
      get "/", to: "logins#choose_login_preference", as: :choose_login_preference
      post "login_preference", to: "logins#set_login_preference", as: :set_login_preference

      # Request a login code
      post "email"
      post "sms"

      # TOTP
      get "totp"
      post "totp"

      get "security_key"
      post "security_key"

      get "backup_code"
      post "backup_code"

      post "complete"
    end
  end

  resources :admin, only: [] do
    collection do
      get "nav", to: "admin#nav"
      get "bank_accounts", to: "admin#bank_accounts"
      get "hcb_codes", to: "admin#hcb_codes"
      get "bank_fees", to: "admin#bank_fees"
      get "fee_revenues", to: "admin#fee_revenues"
      get "users", to: "admin#users"
      get "raw_transactions", to: "admin#raw_transactions"
      get "raw_transaction_new", to: "admin#raw_transaction_new"
      post "raw_transaction_create", to: "admin#raw_transaction_create"
      get "raw_intrafi_transactions", to: "admin#raw_intrafi_transactions"
      post "raw_intrafi_transactions_import", to: "admin#raw_intrafi_transactions_import"
      get "ledger", to: "admin#ledger"
      get "ledger_items", to: "admin#ledger_items"
      get "event_search", to: "admin#event_search"
      get "user_search", to: "admin#user_search"
      get "stripe_cards", to: "admin#stripe_cards"
      get "pending_ledger", to: "admin#pending_ledger"
      get "ach", to: "admin#ach"
      get "reimbursements", to: "admin#reimbursements"
      get "payroll", to: "admin#payroll"
      get "stripe_card_personalization_designs", to: "admin#stripe_card_personalization_designs"
      get "stripe_card_personalization_design_new", to: "admin#stripe_card_personalization_design_new"
      post "stripe_card_personalization_design_create", to: "admin#stripe_card_personalization_design_create"
      get "checks", to: "admin#checks"
      get "increase_checks", to: "admin#increase_checks"
      get "applications", to: "admin#applications"
      # FUIME: the operator vetting queue. A human approves every operator before
      # they can sell — see Fuime::OperatorEligibility.
      get "operator_vetting", to: "admin#operator_vetting"
      post "operator_vetting/:id", to: "admin#operator_vetting_decide", as: "operator_vetting_decide"
      # FUIME: the weekly payout runs. A human reads every line before Fuime pays
      # anybody — see Fuime::PayoutBatchService.
      get "payout_batches", to: "admin#payout_batches"
      get "payout_batches/:id", to: "admin#payout_batch", as: "payout_batch"
      post "payout_batches", to: "admin#payout_batch_generate", as: "payout_batch_generate"
      post "payout_batches/:id/approve", to: "admin#payout_batch_approve", as: "payout_batch_approve"
      post "payout_batches/:id/mark_paid", to: "admin#payout_batch_mark_paid", as: "payout_batch_mark_paid"
      post "payout_batches/:id/cancel", to: "admin#payout_batch_cancel", as: "payout_batch_cancel"
      get "paypal_transfers", to: "admin#paypal_transfers"
      get "wires", to: "admin#wires"
      get "wise_transfers", to: "admin#wise_transfers"
      get "events", to: "admin#events"
      get "event_new", to: "admin#event_new"
      post "event_create", to: "admin#event_create"
      get "donations", to: "admin#donations"
      get "recurring_donations", to: "admin#recurring_donations"
      get "disbursements", to: "admin#disbursements"
      get "disbursement_new", to: "admin#disbursement_new"
      get "invoices", to: "admin#invoices"
      get "sponsors", to: "admin#sponsors"
      get "google_workspaces", to: "admin#google_workspaces"
      post "google_workspaces_verify_all", to: "admin#google_workspaces_verify_all"
      get "balances", to: "admin#balances"
      get "hq_receipts", to: "admin#hq_receipts"
      get "account_numbers", to: "admin#account_numbers"
      get "employees", to: "admin#employees"
      get "employee_payments", to: "admin#employee_payments"
      get "emails", to: "admin#emails"
      get "email", to: "admin#email"
      get "email_html", to: "admin#email_html"
      get "merchant_memo_check", to: "admin#merchant_memo_check"
      get "referral_programs", to: "admin#referral_programs"
      post "referral_program_create", to: "referral/programs#create"
      post "referral_link_create", to: "referral/links#create"
      get "unknown_merchants", to: "admin#unknown_merchants"
      post "request_balance_export", to: "admin#request_balance_export"
      get "active_teenagers_leaderboard", to: "admin#active_teenagers_leaderboard"
      get "new_teenagers_leaderboard", to: "admin#new_teenagers_leaderboard"
      get "contracts", to: "admin#contracts"
    end

    member do
      get "transaction", to: "admin#transaction"
      get "event_balance", to: "admin#event_balance"
      get "event_raised", to: "admin#event_raised"
      get "event_process", to: "admin#event_process"
      put "event_toggle_approved", to: "admin#event_toggle_approved"
      put "event_reject", to: "admin#event_reject"
      get "ach_start_approval", to: "admin#ach_start_approval"
      post "ach_approve", to: "admin#ach_approve"
      post "ach_send_realtime", to: "admin#ach_send_realtime"
      post "ach_reject", to: "admin#ach_reject"
      get "disbursement_process", to: "admin#disbursement_process"
      post "disbursement_approve", to: "admin#disbursement_approve"
      post "disbursement_reject", to: "admin#disbursement_reject"
      get "increase_check_process", to: "admin#increase_check_process"
      get "paypal_transfer_process", to: "admin#paypal_transfer_process"
      get "wire_process", to: "admin#wire_process"
      get "wise_transfer_process", to: "admin#wise_transfer_process"
      get "google_workspace_process", to: "admin#google_workspace_process"
      post "google_workspace_approve", to: "admin#google_workspace_approve"
      post "google_workspace_verify", to: "admin#google_workspace_verify"
      post "google_workspace_update", to: "admin#google_workspace_update"
      post "google_workspace_toggle_revocation_immunity", to: "admin#google_workspace_toggle_revocation_immunity"
      get "invoice_process", to: "admin#invoice_process"
      post "invoice_mark_paid", to: "admin#invoice_mark_paid"
    end
  end

  namespace :admin do
    root to: redirect("/admin/events")
    namespace :ledger_audits do
      resources :tasks, only: [:index, :show, :create] do
        post :reviewed
        post :flagged
      end
    end
    resources :ledger_audits, only: [:index, :show]
    resources :w9s, only: [:index, :new, :create]
    resources :check_deposits, only: [:index, :show] do
      post "submit", on: :member
      post "reject", on: :member
    end
    resources :payments, only: [:index]
    # FUIME: read-only view of the marketing site's waitlist (Render Key Value).
    resources :waitlist, only: [:index]
    resources :payroll_positions, only: [:index] do
      post "reject", on: :member
    end
    resources :legal_entities, only: [:index]
    resources :tax_forms, only: [:index]
    resources :column_statements, only: :index do
      get "bank_account_summary_report"
    end
    resources(:event_groups, only: [:index, :create, :destroy]) do
      collection do
        get("events/:event_id", as: :event, to: "event_groups#event")
        patch("events/:event_id", to: "event_groups#update_event")
      end
      member do
        get(:statement_of_activity)
      end
      resources(:event_group_memberships, path: "memberships", only: [:destroy])
    end
  end

  post "set_event", to: "admin#set_event_multiple_transactions", as: :set_event_multiple_transactions
  post "set_event/:id", to: "admin#set_event", as: :set_event
  post "set_paypal_transfer/:id", to: "admin#set_paypal_transfer", as: :set_paypal_transfer
  post "set_wire/:id", to: "admin#set_wire", as: :set_wire
  post "set_wise_transfer/:id", to: "admin#set_wise_transfer", as: :set_wise_transfer

  resources :organizer_position_invites, only: [:show], path: "invites" do
    post "accept"
    post "reject"
    post "cancel"
    post "resend"
    member do
      post "change_position_role"
      post "send_contract"
    end
  end

  resources :contracts, only: [] do
    member do
      post "void"
      post "reissue"
    end
  end

  namespace :contract, path: "contracts" do
    resources :parties, only: [:show] do
      member do
        post "resend"
        get "completed"
      end
    end
  end

  resources :organizer_positions, only: [:destroy], as: "organizers" do
    member do
      post "set_index"
      post "mark_visited"
      post "change_position_role"
    end

    resources :organizer_position_deletion_requests, only: [:new], as: "remove"
  end

  resources :organizer_position_deletion_requests, only: [:index, :show, :create], concerns: :commentable do
    post "close"
    post "open"
    post "assign"
    post "unassign"
  end

  resources :g_suite_accounts, only: [:index, :create, :update, :edit, :destroy], path: "g_suite_accounts" do
    put "reset_password"
    put "toggle_suspension"
    resources :g_suite_aliases, only: [:create, :destroy], shallow: true
  end

  resources :g_suites, except: [:new, :create, :edit, :update] do
    resources :g_suite_accounts, only: [:create]
    resources :revocations, only: [:create, :destroy], controller: "g_suite/revocations"
  end

  resources :sponsors

  resources :invoices, only: [:show] do
    post "manually_mark_as_paid"
    post "archive"
    post "unarchive"
    post "void"
    get "hosted"
    get "pdf"
    member do
      post "refund"
    end
  end

  resources :stripe_cardholders, only: [:new, :create, :update]

  namespace :stripe_cards do
    resource :activation, only: [:new, :create], controller: :activation

    resources :personalization_designs, only: [:show] do
      member do
        post "make_common"
        post "make_unlisted"
      end
    end
  end
  resources :stripe_cards, only: %i[edit update create index show] do
    member do
      post "freeze"
      post "defrost"
      post "cancel"
      post "enable_cash_withdrawal"
      get "ephemeral_keys"
    end
  end

  resources :emburse_cards, except: %i[new create]

  resources :checks, only: [:show]

  resources :increase_checks, only: [] do
    member do
      post "approve"
      post "reject"
      post "stop"
    end
  end

  resources :paypal_transfers, only: [] do
    member do
      post "approve"
      post "reject"
      post "mark_failed"
    end
  end

  resources :wires, only: [:edit, :update] do
    member do
      post "approve"
      post "send", to: "wires#send_wire"
      post "reject"
    end
  end

  resources :wise_transfers, only: [:edit, :update] do
    member do
      post "approve"
      post "reject"
      post "mark_sent"
      post "mark_failed"
    end

    collection do
      get "generate_quote"
    end
  end

  resources :ach_transfers, only: [:show] do
    member do
      post "cancel"
      post "toggle_speed"
    end
    collection do
      post "validate_routing_number"
    end
    get "confirmation", to: "ach_transfers#transfer_confirmation_letter"
  end

  resources :disbursements, only: [:new, :create, :show, :edit, :update], concerns: :commentable do
    collection do
      get :event_search
    end
    post "mark_fulfilled"
    post "reject"
    post "cancel"
    post "set_transaction_categories"
    get "confirmation", to: "disbursements#transfer_confirmation_letter"
  end

  get "disbursements", to: redirect("/admin/disbursements")

  resources :documents, except: [:index] do
    collection do
      get "", to: "documents#common_index", as: :common
    end
    get "download"
    post "toggle", to: "documents#toggle_archive"
  end

  resources :bank_accounts, only: [:new, :create, :update, :show, :index] do
    get "reauthenticate"
  end

  resources :hcb_codes, path: "/hcb", only: [:show, :edit, :update], concerns: :commentable do
    member do
      get "attach_receipt"
      get "memo_frame"
      get "dispute"
      post "invoice_as_personal_transaction"
      post "pin"
      post "toggle_tag/:tag_id", to: "hcb_codes#toggle_tag", as: :toggle_tag
      post "send_receipt_sms", to: "hcb_codes#send_receipt_sms", as: :send_sms_receipt

      scope module: "hcb_code" do
        get "subscriptions/transactions", to: "subscriptions#transactions"
      end
    end

    collection do
      get "receipt_status"
    end
  end

  scope module: "hcb_code" do
    namespace :tag do
      resources :suggestions, only: [] do
        post "accept"
        post "reject"
      end
    end
  end

  resources :canonical_pending_transactions, only: [:show, :edit, :update] do
    member do
      post "set_category"
    end
  end

  resources :canonical_transactions, only: [:show, :edit] do
    member do
      post "waive_fee"
      post "unwaive_fee"
      post "mark_bank_fee"
      post "set_custom_memo"
      post "set_category"
    end
  end

  resources :exports do
    collection do
      get "collect_email", to: "exports#collect_email", as: "collect_email"
      get ":event", to: "exports#transactions", as: "transactions"
      get "reimbursements/:event", to: "exports#reimbursements", as: "reimbursements"
    end
  end

  resources :transactions, only: [:index, :show, :edit, :update], path: "deprecated/transactions"

  namespace :reimbursement do
    resources :reports, only: [:show, :create, :edit, :update, :destroy] do
      post "request_reimbursement"
      post "convert_to_wise_transfer"
      post "admin_approve"
      post "admin_send_wise_transfer"
      post "reverse"
      post "approve_all_expenses"
      post "request_changes"
      post "reject"
      post "submit"
      post "update_currency"
      post "update_payout_method"
      post "draft"
      get "wise_transfer_quote"
      get "wise_transfer_breakdown"
      collection do
        post "quick_expense"
        get "/:event_name/finished", to: "reports#finished", as: "finished"
      end
    end

    get "start/:event_name", to: "reports#start", as: "start_reimbursement_report"

    resources :expenses, only: [:create, :edit, :update, :destroy] do
      post "approve"
      post "unapprove"
    end
  end
  resources :reimbursement_reports, only: [], path: "reimbursements/reports", concerns: :commentable

  resources :ledgers, only: [:show]
  scope module: :ledger, as: :ledger do
    resources :items, path: "transactions", only: [:show] do
      get "hcb"
    end
  end
  resources :ledger_items, only: [], path: "transactions", concerns: :commentable

  resources :employees do
    post "terminate"
    post "onboard"
  end

  namespace :employee do
    resources :payments do
      post "review"
      get "stub"
    end
  end

  resources :payments, only: [:show], concerns: :commentable do
    member do
      post "cancel"
    end
  end

  get "brand_guidelines", to: redirect("branding")
  get "mobile", to: "static_pages#mobile"
  get "branding", to: "static_pages#branding"
  get "security", to: "static_pages#security"
  # Fuime: these three used to redirect to hackclub.com and help.hcb.hackclub.com.
  # Pointing Fuime's own users at another organisation's privacy policy is a
  # misrepresentation, and it has to be closed before a single real signup
  # (docs/fuime/LAUNCH_SPEC.md §1.3). They are now Fuime's own documents.
  get "privacy", to: "static_pages#privacy"
  get "terms", to: "static_pages#terms"
  get "guardian-agreement", to: "static_pages#guardian_agreement", as: :guardian_agreement
  get "faq", to: "static_pages#faq"
  get "roles", to: "static_pages#roles"
  get "admin_tools", to: "static_pages#admin_tools"
  get "audit", to: "admin#audit"

  # Marketing landing pages. Public, server-rendered, largely static. Built so future
  # audience pages slot in under the same /for/* prefix and reuse the marketing layout.
  get "for/funders", to: "marketing#funders", as: :funders
  get "for/funders/faq", to: "marketing#funders_faq", as: :funders_faq
  post "for/funders/inquiry", to: "marketing#funder_inquiry", as: :funder_inquiry

  resources :emburse_card_requests, path: "emburse_card_requests", except: [:new, :create] do
    collection do
      get "export"
    end
    post "reject"
    post "cancel"
  end

  resources :emburse_transactions, only: [:index, :edit, :update, :show]

  resources :donations, only: [:show, :update] do
    collection do
      get "start/:event_name", to: "donations#start_donation", as: "start_donation"
      post "start/:event_name", to: "donations#make_donation", as: "make_donation"
      get "start/:event_name/tiers/:tier_id", to: "donation/tiers#start", as: "start_donation_tier"
      get "qr/:event_name.png", to: "donations#qr_code", as: "qr_code"
      get ":event_name/:donation", to: "donations#finish_donation", as: "finish_donation"
      get ":event_name/:donation/finished", to: "donations#finished", as: "finished_donation"
      get "export"
      get "export_donors"
    end

    member do
      post "refund", to: "donations#refund"
    end
  end

  use_doorkeeper scope: "api/v4/oauth" do
    skip_controllers :authorized_applications
  end
  use_doorkeeper_device_authorization_grant scope: "api/v4/oauth"

  namespace :api do
    namespace :v4 do
      defaults format: :json do
        resource :user, only: [] do
          get "/", to: "users#me", as: "user"
          post :revoke
          resources :events, path: "organizations", only: [:index]
          resources :stripe_cards, path: "cards", only: [:index]
          resources :card_grants, only: [:index]
          resources :organizer_position_invites, path: "invitations", only: [:index, :show] do
            member do
              post "accept"
              post "reject"
            end
          end

          get "transactions/missing_receipt", to: "transactions#missing_receipt"
          get :available_icons
          get :intercom_token, to: "intercom#token"
        end

        resources :users, only: [:show] do
          collection do
            get "/by_email/:email", to: "users#by_email", as: "by_email", constraints: { email: /[^\/]+/ }
          end
        end

        resources :events, path: "organizations", only: [:show] do
          resources :stripe_cards, path: "cards", only: [:index]
          resources :card_grants, only: [:index, :create]
          resources :organizer_position_invites, path: "invitations", only: [:index, :create, :destroy]
          resources :transactions, only: [:show, :update] do
            resources :receipts, only: [:index]
            resources :comments, only: [:index, :create] # Deprecated (will be removed in the future): use shallow route

            member do
              get "memo_suggestions"
            end
          end

          resources :disbursements, path: "transfers", only: [:create]
          # TODO: shallow route these (breaking change)
          resources :donations, path: "donations", only: [:create] do
            member do
              post "payment_intent"
            end
          end

          member do
            get "sub_organizations"
            post "sub_organizations", to: "events#create_sub_organization"

            get "transactions", to: "transactions#index"
            get :followers
            get :balance_by_date
          end
        end

        resources :organizer_positions, only: [:index] do
          member do
            post "removal_request"
          end
        end

        resources :transactions, only: [:show] do
          member do
            post "mark_no_receipt"
          end
        end

        resources :donations, only: [:index, :show]

        resources :tags, only: [:index, :show, :create, :destroy]

        resources :receipts, only: [:create, :index, :destroy]

        resources :stripe_cards, path: "cards", only: [:show, :update, :create] do
          collection do
            get "card_designs"
            post "freeze"
            post "defrost"
            post "activate"
          end

          member do
            get "transactions"
            get "ephemeral_keys"
            post "cancel"
          end
        end

        resources :card_grants, only: [:show, :update] do
          member do
            post "activate"
            post "topup"
            post "withdraw"
            post "cancel"
            get "transactions"
          end
        end

        resources :invoices, only: [:index, :show, :create]
        resources :checks, only: [:index, :create, :show]
        resources :sponsors, only: [:index, :show, :create]
        resources :check_deposits, only: [:index, :show, :create]
        resources :wires, only: [:index, :show, :create]
        resources :ach_transfers, only: [:create]

        resources :comments, only: [:index, :create]

        get "stripe_terminal_connection_token", to: "stripe_terminal#connection_token"

        match "*path" => "application#not_found", via: [:get, :post]
      end
    end
  end

  get "api/current_user", to: "api#the_current_user"
  get "api/flags", to: "api#flags"

  post "twilio/webhook", to: "twilio#webhook"
  post "stripe/webhook", to: "stripe#webhook"
  post "docuseal/webhook", to: "docuseal#webhook"
  post "webhooks/column", to: "column/webhooks#webhook"
  post "taxbandits/webhook", to: "taxbandits#webhook"

  post "discord/event_webhook", to: "discord#event_webhook"
  post "discord/interaction_webhook", to: "discord#interaction_webhook"
  get "discord/link", to: "discord#link"
  post "discord/create_link", to: "discord#create_link"
  get "discord/setup", to: "discord#setup"
  get "discord/unlink_server", to: "discord#unlink_server"
  post "discord/unlink_server", to: "discord#unlink_server_action"
  get "discord/unlink_user", to: "discord#unlink_user"
  post "discord/unlink_user", to: "discord#unlink_user_action"
  post "discord/create_server_link", to: "discord#create_server_link"

  post "extract/invoice", to: "extraction#invoice"

  get "negative_events", to: "admin#negative_events"

  get "admin_task_size", to: "admin#task_size"
  get "admin_search", to: redirect("/admin/users")
  post "admin_search", to: redirect("/admin/users")

  resources :tours, only: [] do
    member do
      post "mark_complete"
      post "set_step"
    end
  end

  resources :recurring_donations, only: [:show, :edit, :update], path: "recurring" do
    member do
      post "cancel"
    end
  end

  resources :card_grants, only: [:show, :edit, :update], path: "grants", concerns: :commentable do
    member do
      post "activate"
      get "spending"
      post "clear_purpose"
    end

    scope module: "card_grant" do
      resource :pre_authorizations, only: [:show, :update] do
        member do
          post "clear_screenshots"
          post "organizer_approve"
          post "organizer_reject"
        end
      end
    end
  end

  match "/400", to: "errors#bad_request", via: :all
  match "/404", to: "errors#not_found", via: :all
  match "/500", to: "errors#internal_server_error", via: :all
  match "/504", to: "errors#timeout", via: :all
  get "timeout", to: "errors#timeout", via: :all

  Rack::Utils::HTTP_STATUS_CODES.keys.select { |c| c >= 400 }.each do |code|
    match "/#{code}", to: "errors#error", via: :all, code:
  end

  get "/search" => "search#index"

  resources :follows, only: [:destroy], controller: "event/follows"

  resources :announcements, except: [:index, :new] do
    member do
      post "publish"
    end
  end

  namespace "announcements" do
    resources :blocks, only: [:create, :edit, :update, :show]
  end

  scope module: "organizer_position_invite" do
    resources :links, path: "invite_links", only: :show do
      member do
        post "deactivate"
      end
    end

    resources :requests, path: "invite_requests", only: [:create] do
      member do
        post "approve"
        post "deny"
      end
    end
  end

  resources :payees, only: [] do
    member do
      get "choose_legal_entity"
      post "set_legal_entity"
    end
  end

  resources :legal_entities, only: [:show] do
    collection do
      post "create_from_tax_form"
    end

    member do
      post "replace"
    end
  end

  resources :tax_forms, only: [:show, :create], controller: "tax/forms" do
    member do
      post "sync"
      post "discard"
    end
  end

  scope module: :event do
    get "apply", to: "applications#apply"

    resources :applications, only: [:index, :create, :show, :new, :update] do
      collection do
        get "start", to: "applications#create"
      end

      member do
        # Fuime: what kind of business, ahead of describing it. See
        # Fuime::ServiceCatalog.
        get "business_type"
        get "personal_info"
        get "project_info"
        get "videos"
        get "agreement"
        get "review"
        get "submission"
        get "edit"
        post "submit"
        post "archive"
        post "unarchive"
        post "admin_approve"
        post "admin_reject"
        post "admin_activate"
        post "resend_to_cosigner"
        post "mark_videos_watched"
      end
    end
  end
  resources :affiliations, only: [:create, :update, :destroy], module: :event

  get "/events" => "events#index"
  resources :events, except: [:new, :create, :edit], concerns: :commentable, path: "/" do

    # Loaded as Turbo frames on the home page
    get :team_stats
    get :recent_activity
    get :balance_transactions
    get :money_movement
    get :merchants_chart
    get :categories_chart
    get :top_categories
    get :tags_chart
    get :users_chart
    get :transaction_heatmap

    get "edit", to: redirect("/%{event_id}/settings")
    get "transactions"
    get "transactions_list"
    get "ledger"
    post "toggle_new_ledger"
    get "stats"
    get "merchants_filter"
    put "toggle_hidden"
    post "claim_point_of_contact"
    post "create_sub_organization"
    post "toggle_fee_waiver_eligible"

    post "remove_header_image"
    post "remove_background_image"
    post "remove_logo"

    get "team"
    get "google_workspace", to: "events#g_suite_overview", as: :g_suite_overview
    post "g_suite_create"
    put "g_suite_verify"
    get "emburse_cards", to: "events#emburse_card_overview", as: :emburse_cards_overview
    get "cards", to: "events#card_overview", as: :cards_overview
    get "cards/new", to: "stripe_cards#new"
    get "announcements", to: "events#announcement_overview", as: :announcement_overview
    get "announcements/new", to: "announcements#new"
    get "feed", to: "events#feed", as: :feed
    get "stripe_cards/shipping", to: "stripe_cards#shipping", as: :stripe_cards_shipping
    get "card_grants", to: "card_grants#index", as: :card_grant_overview
    get "card_grants/card_overview", to: "card_grants#card_index", as: :card_grant_card_overview
    get "card_grants/transaction_overview", to: "card_grants#transaction_index", as: :card_grant_transaction_overview
    get "card_grants/bulk_upload", to: "card_grants#bulk_upload_form", as: :card_grants_bulk_upload
    post "card_grants/bulk_upload", to: "card_grants#bulk_upload"
    get "card_grants/bulk_upload_template", to: "card_grants#bulk_upload_template", as: :card_grants_bulk_upload_template

    resources :follows, only: [:create], controller: "event/follows"

    get "transfers/new", to: "events#new_transfer"

    get "payments", to: "events#payments"

    resources :payments, only: [:new, :create]
    resources :payroll_positions, only: [:new, :create, :show, :edit, :update], controller: "payroll/positions" do
      member do
        get :contract
      end
    end
    resources :payroll_invoices, only: [], controller: "payroll/invoices" do
      member do
        post :approve
        post :reject
      end
    end
    resources :payees, only: [:index, :create, :update] do
      member do
        post :archive
      end
    end

    get "async_balance"
    get "async_sub_organization_balance"
    get "async_sub_organizations_graph"
    # Fuime: outstanding-receipt count for one org, loaded lazily on the parent's
    # roster. Async for the same reason async_balance is — HcbCode's
    # receipt_required scope carries several LEFT JOINs, and a school roster
    # renders one of these per student.
    get "async_missing_receipts"
    get "reimbursements_pending_review_icon"

    get "documentation", to: redirect("/%{event_id}/documents", status: 302)
    get "transfers"
    get "payments"
    get "statements"
    get "statement_of_activity"
    get "promotions"
    get "reimbursements"
    get "employees"
    get "contractors"
    get "sub_organizations"
    get "sub_organizations/new", to: "suborganizations#new", as: :new_sub_organization
    get "donations", to: "events#donation_overview", as: :donation_overview
    get "activation_flow", to: "events#activation_flow", as: :activation_flow
    post "activate", to: "events#activate", as: :activate
    resources :disbursements, only: [:new, :create]
    resources :increase_checks, only: [:new, :create], path: "checks"
    resources :fees, only: [:create]
    resources :paypal_transfers, only: [:new, :create]
    resources :wires, only: [:new, :create]
    resources :wise_transfers, only: [:new, :create]
    resources :ach_transfers, only: [:new, :create]
    resources :g_suites, only: [:new, :create, :edit, :update]
    resources :documents, only: [:index]
    # FUIME-DISABLED: fiscal_sponsorship_letter, verification_letter.
    #
    # Both rendered on Hack Club letterhead — their logo, a real employee's
    # scanned signature, and EIN 81-2908499 — asserting that The Hack
    # Foundation fiscally sponsors the business. Fuime is not a fiscal sponsor
    # and has no 501(c)(3), so there is no truthful Fuime version of either.
    # The verification letter additionally attested an account "in good
    # standing with Column N.A., a Member of the FDIC" and printed account and
    # routing numbers: a bank-verification document Fuime cannot substantiate.
    #
    # Routes removed rather than the actions deleted (CLAUDE.md Rule 2); the
    # controller actions and templates remain for upstream diffability.
    resources :invoices, only: [:new, :create, :index]
    resources :tags, only: [:create, :update, :destroy]
    resources :event_tags, only: [:create, :destroy]
    resources :organizer_position_invites,
              only: [:new, :create],
              path: "invites"

    scope module: "organizer_position_invite" do
      resources :links,
                only: [:new, :create, :index],
                path: "invite_links",
                as: :invite_links
    end

    namespace :donation do
      resource :goals, only: [:create, :update]
      resource :tiers, only: [:create, :update, :destroy] do
        post :set_index, on: :member
      end
    end

    resources :recurring_donations, only: [:create], path: "recurring" do
      member do
        get "pay"
        get "finished"
      end
    end

    resources :check_deposits, only: [:index, :create], path: "check-deposits" do
      member do
        post "toggle_fronted"
      end
    end

    resources :card_grants, only: [:new, :create], path: "card-grants" do
      member do
        post "topup"
        post "withdraw"
        post "cancel"
        post "convert_to_reimbursement_report"
        post "toggle_one_time_use"
        post "disable_pre_authorization"
        post "permit_merchant"

        get "edit/overview", to: "card_grants#edit_overview"
        get "edit/usage_restrictions", to: "card_grants#edit_usage_restrictions"
        get "edit/expiration", to: "card_grants#edit_expiration"
        get "edit/purpose", to: "card_grants#edit_purpose"
        get "edit/actions", to: "card_grants#edit_actions"
        get "edit/balance", to: "card_grants#edit_balance"
        get "edit/topup", to: "card_grants#edit_topup"
        get "edit/withdraw", to: "card_grants#edit_withdraw"
      end
    end

    resource :column_account_number, controller: "column/account_number", only: [:create, :update], path: "account-number"

    resources :organizer_positions, path: "team", only: [] do
      resources :organizer_position_deletion_requests, path: "removal-requests", as: "remove", only: [:new]

      scope module: "organizer_position" do
        namespace :spending do
          resources :controls do
            resources :allowances, only: [:new, :create], controller: "control/allowances"
          end
        end
      end
    end

    resources :payment_recipients, only: [:destroy]

    resources :scoped_tags, module: :event, only: [:create, :update, :destroy] do
      member do
        post "toggle_tag"
      end
    end

    member do
      get "account-number", to: "events#account_number"
      post "toggle_event_tag/:event_tag_id", to: "events#toggle_event_tag", as: :toggle_event_tag
      get "audit_log"
      post "validate_slug"
      get "termination"
      post "permit_merchant"
      post "request_call"
      post "hide_onboarding_message"
      get "sub_organizations/check_name", to: "events#check_sub_organization_name", as: :check_sub_organization_name

      get "settings(/:tab)", to: "events#edit", as: :edit
    end

    get "balance_by_date"
  end

  scope as: "referral", module: "referral" do
    resources :links, only: [:show], path: "referrals"
    resources :links, only: [:show], path: "from/*slug"
  end

  # rewrite old event urls to the new ones not prefixed by /events/
  get "/events/*path", to: redirect("/%{path}", status: 302)

  # Beware: Routes after "resources :events" might be overwritten by a
  # similarly named event
end
