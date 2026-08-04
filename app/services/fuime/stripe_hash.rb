# frozen_string_literal: true

# Fuime: turn a Stripe object into a plain, deeply-converted, symbol-keyed Hash.
#
# ── Why this exists rather than just calling `to_h` ──────────────────────────
#
# `Stripe::StripeObject#to_h` is SHALLOW in the stripe-ruby version pinned here
# (11.7.0): the top level becomes a Hash, but nested values remain StripeObjects.
# Since StripeObject does not implement `dig`, this reads as correct and then fails:
#
#   card.to_h.dig(:spending_controls, :allowed_categories)
#   # => TypeError: #<Class:#<Stripe::StripeObject>> does not have #dig method
#
# It fails on the SECOND key, so any code that only ever digs one level deep passes
# and gives no warning that the same pattern breaks a level down. That is a trap
# worth removing once rather than rediscovering per call site.
#
# The JSON round-trip is used because it is the only conversion that is deep for
# every nesting shape Stripe returns, including arrays of objects (a card's
# `spending_controls.spending_limits` is exactly that). Method-chain access
# (`card.spending_controls.spending_limits`) would also work but raises NoMethodError
# on absent fields, and Stripe legitimately omits fields.
module Fuime
  module StripeHash
    # Returns {} for nil or blank input, so callers can dig without guarding first.
    def self.deep(object)
      return {} if object.blank?
      return object.deep_symbolize_keys if object.is_a?(Hash)

      JSON.parse(object.to_json, symbolize_names: true)
    rescue JSON::ParserError, TypeError => e
      # Never let a malformed payload take down a webhook or a card sync. The caller
      # sees an empty hash and treats the fields as absent, which is the same path a
      # legitimately-omitted field takes.
      Rails.logger.error("[Fuime] could not convert Stripe object to hash: #{e.class}: #{e.message}")
      {}
    end
  end
end
