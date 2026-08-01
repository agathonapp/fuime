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
      @has_guardian = @owner&.has_active_guardian? if @owner.present?
      @tax_tracker = TaxTrackerService.new(event: @event) if @event.is_public
    end
  end
end
