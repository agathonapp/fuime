# frozen_string_literal: true

# Second half of CreateFuimeOffers, split per the house pattern: validating a
# foreign key or check constraint takes a lock proportional to the table.
class ValidateFuimeOfferConstraints < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :fuime_offers, :events
    validate_check_constraint :fuime_offers, name: "fuime_offers_state_known"
    validate_check_constraint :fuime_offers, name: "fuime_offers_price_in_range"
  end
end
