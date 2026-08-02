# frozen_string_literal: true

# Fuime: Public storefront page for businesses
module Fuime
  class StorefrontsController < ApplicationController
    skip_before_action :signed_in_user
    skip_after_action :verify_authorized

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
      @has_guardian = @owner.present? && @owner.has_active_guardian?

      # The tax estimate is the business's own private figure — it is not
      # transparency data and must never appear on a public page.
      @tax_tracker = nil
    end
  end
end
