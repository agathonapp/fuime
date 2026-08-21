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

  # Fuime: an already-set date of birth was changed.
  #
  # Not a failure — `User#birthday_is_write_once` refuses the self-service case, so
  # reaching here means an admin, the console or a job did it legitimately. Reported
  # because age is the input every protective control on the platform derives from
  # (guardianship enforcement, the operator age floor, the payout guardian gate), so
  # a change to it is a change to somebody's eligibility to trade and a human should
  # see that it happened.
  class PrivilegedBirthdayChange < StandardError
  end

end
