# frozen_string_literal: true

module LogoHelper
  # Fuime: Returns URL for the Fuime logo (used in emails)
  def hcb_logo_variant_url(height: 80)
    # Use the public logo.svg for emails
    Rails.application.routes.url_helpers.root_url + "logo.svg"
  end

  # Alias for clarity
  def fuime_logo_url
    hcb_logo_variant_url
  end
end
