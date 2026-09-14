# frozen_string_literal: true

# == Schema Information
#
# Table name: event_tags
#
#  id          :bigint           not null, primary key
#  description :string
#  name        :string           not null
#  purpose     :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_event_tags_on_name_and_purpose  (name,purpose) UNIQUE
#
class EventTag < ApplicationRecord
  include ActionView::Helpers::TextHelper # for `pluralize`

  has_and_belongs_to_many :events

  validates :name, presence: true, uniqueness: { scope: :purpose }

  def removal_confirmation_message
    message = "Are you sure you'd like to delete this tag?"
    return message if events.none?

    message + " It will be removed from #{pluralize(events.size, 'organization')}."
  end

  def api_name(format = :short)
    components = [name]
    components << purpose unless format == :short
    components.compact.join("_").parameterize.underscore
  end

  def full_name
    return name unless purpose.present?

    "#{purpose}: #{name}"
  end

  module Tags
    ALL = [
      ORGANIZED_BY_HACK_CLUBBERS = "Organized by Hack Clubbers",
      ORGANIZED_BY_TEENAGERS = "Organized by Teenagers",
      CLIMATE = "Climate",
      PARTNER_128_COLLECTIVE_FUNDED = "128 Collective Funded",
      PARTNER_128_COLLECTIVE_RECOMMENDED = "128 Collective Recommended",
      VERMONT_BASED = "Vermont-based",
      ROBOTICS_TEAM = "Robotics Team",
      HACKATHON = "Hackathon",
      HACK_CLUB = "Hack Club",
      YSWS = "YSWS"
    ].to_set

    # Fuime: which of the above an admin may still APPLY.
    #
    # Every member of ALL is one of Hack Club's: their hackathon and FIRST
    # Robotics programmes ("Hackathon", "Robotics Team"), their funder
    # partnerships ("Climate", "128 Collective Funded/Recommended",
    # "Vermont-based"), their own orgs ("Hack Club", "Organized by Hack
    # Clubbers"), and "YSWS" (You Ship We Ship). "Organized by Teenagers" is
    # the odd one out and is still wrong here: on Fuime every venture is
    # teen-run, so the tag distinguishes nothing.
    #
    # Same lever as `Event::Plan.selectable?` — the values stay defined so
    # existing `event_tags` rows keep resolving and `Event#hackathon?` /
    # `Event.ysws` keep working (CLAUDE.md Rule 2 and Rule 6: these are stored
    # strings). They are simply no longer offered. Admins can still create
    # free-form tags through events/settings/_tags.
    #
    # Empty rather than replaced with a guessed Fuime taxonomy: inventing
    # business categories is a product decision, not a rebrand.
    SELECTABLE = [].to_set
  end

end
