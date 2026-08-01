# frozen_string_literal: true

# Fuime: Add business-specific fields to events (organizations)
class AddFuimeBusinessFieldsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :business_category, :string
    add_column :events, :storefront_tagline, :string
  end
end
