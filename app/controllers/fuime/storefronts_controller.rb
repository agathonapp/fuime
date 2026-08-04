# frozen_string_literal: true

# Fuime: Public storefront page for businesses
module Fuime
  class StorefrontsController < ApplicationController
    skip_before_action :signed_in_user
    skip_after_action :verify_authorized

    # This page carries its OWN copy of the "not a bank / no FDIC-insured products"
    # disclosure, tailored for a payer about to enter a card number (see the view).
    # The shared footer now renders on the signed-out layout branch too, so without
    # this the storefront would state the same disclosure twice — and a duplicated
    # legal notice reads as boilerplate, which is the opposite of conspicuous.
    before_action :hide_footer

    def show
      @event = Event.find_by!(slug: params[:slug])

      # Check if business has public transparency enabled
      unless @event.is_public
        redirect_to root_path, alert: "This business's storefront is not public."
        return
      end

      @owner = @event.point_of_contact

      # Fuime: storefronts belong to businesses run by children, so this page is
      # deliberately narrower than HCB's transparency page — which was designed
      # for nonprofit ORGANISATIONS choosing to publish accountability data.
      #
      # A minor's first name plus a live balance plus a transaction history is a
      # targeting profile, so:
      #   * the owner's name is shown only when the owner is a confirmed adult;
      #   * the exact balance is never published (see the view);
      #   * the guardian badge asserts only that a guardianship is active.
      @show_owner_name = @owner.present? && @owner.known_adult?

      # `point_of_contact` is the admin who activated the venture, NOT the
      # founder (Event::Application#activate_event! passes the acting admin), so
      # the previous `@owner.has_active_guardian?` here was publishing whether a
      # Fuime staff member has a parent. Asks the venture directly instead.
      @has_guardian = @event.has_overseeing_guardian?

      # Whether a payer can actually be charged. `is_public` alone is not enough:
      # it defaults to true, so every activated venture looked payment-ready
      # before any guardian had set payments up.
      @accepts_payments = @event.accepts_payments?

      # The tax estimate is the business's own private figure — it is not
      # transparency data and must never appear on a public page.
      @tax_tracker = nil
    end

  end
end
