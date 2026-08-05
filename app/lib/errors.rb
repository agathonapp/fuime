# frozen_string_literal: true

module Errors
  class InvalidLoginCode < StandardError
  end

  class ValidationError < StandardError
  end

  class InvalidStripeCardLogoError < StandardError
  end

  class StripeIssuingBalanceAnomaly < StandardError
  end

  class StripeInvalidNameError < StandardError
  end

  # Fuime: a card grant whose spending policy resolves to nothing it may buy.
  # Raised instead of activating, because the empty allowlist such a policy
  # produces would reach Stripe as no restriction at all.
  class CardGrantPolicyConflictError < StandardError
  end

  class TwilioAbuseError < StandardError
  end

end
