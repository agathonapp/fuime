# frozen_string_literal: true

class CardGrant
  # Resolves a card grant's spending policy through the event tree, rather than
  # from the grant's own event alone.
  #
  # Upstream reaches exactly one CardGrantSetting, via
  # `has_one :card_grant_setting, through: :event` — the grant's own event and
  # nowhere else, enforced by a UNIQUE index on card_grant_settings.event_id.
  # That is right for HCB, where a card grant is a one-off gift issued by the
  # organization that holds the money.
  #
  # It does not hold for an institution. Fuime's school structure is
  #
  #   School (Event) -> Student venture (Event, parent: school)
  #
  # and grants live on the student's venture, because that is where the student's
  # subledger and ledger lines are. Without inheritance the school's policy never
  # reaches a single grant. Worse, it fails open rather than closed:
  # `before_validation :create_card_grant_setting` calls
  # find_or_create_by!(event_id:), which manufactures an EMPTY setting on the
  # student's venture. An empty allowlist combined with an empty grant-level lock
  # is not a restrictive card — it is an unrestricted one. The default path
  # silently produces the opposite of what a school is buying.
  #
  # Direction of combination differs per field, and getting it backwards is how
  # the control inverts:
  #
  #   bans       UNION up the chain. A ban set by the school can never be undone
  #              by anything beneath it.
  #   allowlists INTERSECT down the chain, skipping empty levels. Each level may
  #              only narrow what its ancestors already permitted. This is what
  #              makes "a guide can tighten a student's card but never loosen the
  #              school's policy" actually true. Upstream's `+` union made it
  #              false: a grant-level lock ADDED categories the school had never
  #              allowed.
  #
  # One deliberate asymmetry: an empty allowlist at a level means "inherit", not
  # "allow nothing". That is how upstream's existing data already reads, and
  # treating empty as a deny would brick every HCB grant that relies on a
  # setting-level lock with no grant-level override.
  module InheritablePolicy
    extend ActiveSupport::Concern

    # Settings from every event in the chain, nearest first. Event#ancestor_ids
    # returns [self.id, parent.id, grandparent.id, ...] and guarantees that order
    # via SEARCH BREADTH FIRST, so a single query preserves precedence.
    def policy_settings
      return Array(setting) if event.blank?

      ids = event.ancestor_ids
      by_event_id = CardGrantSetting.where(event_id: ids).index_by(&:event_id)
      ids.filter_map { |id| by_event_id[id] }
    end

    # Levels that actually constrain, empty ones dropped ("inherit", not "deny").
    def constraining_levels(local, inherited)
      ([local] + inherited).map { |value| Array(value).compact_blank }
                           .reject(&:empty?)
    end

    # Intersection of every level that constrains. Returns [] when no level
    # constrains, which callers read as "no allowlist" exactly as upstream does —
    # so an unconfigured tree behaves as it does today rather than declining
    # everything.
    #
    # DANGER, and the reason #policy_conflict? exists: [] is also what an
    # intersection of levels that share nothing produces, and those two states
    # mean opposite things. "Nobody configured a lock" is unrestricted by design.
    # "The school allows {hardware} and this grant locks to {gambling}" must deny
    # everything — but as a bare [] it reaches Stripe as no allowlist at all, i.e.
    # an unrestricted card. Since category_lock is free text with no validation
    # anywhere in the app, a single typo lands in exactly that state. Callers must
    # check #policy_conflict? before trusting an empty result.
    def narrowed_policy(local, inherited)
      levels = constraining_levels(local, inherited)
      return [] if levels.empty?

      levels.reduce { |acc, level| acc & level }
    end

    # True when levels were configured but share nothing — a contradiction that
    # must never be resolved as "unrestricted".
    def narrowed_policy_conflict?(local, inherited)
      levels = constraining_levels(local, inherited)

      levels.any? && levels.reduce { |acc, level| acc & level }.empty?
    end

    # Any policy contradiction on this grant. A card must not be activated while
    # this is true: the safe reading of a contradiction is "deny", and the one
    # thing we cannot do is ship it to Stripe as an empty allowlist.
    def spending_policy_conflict?
      settings = policy_settings

      narrowed_policy_conflict?(category_lock, settings.map(&:category_lock)) ||
        narrowed_policy_conflict?(merchant_lock, settings.map(&:merchant_lock))
    end

    def spending_policy_conflict_message
      "This card's spending policy resolves to nothing it is allowed to buy. " \
        "That happens when a category or merchant lock on this grant shares no " \
        "values with the policy set above it — often a mistyped category. " \
        "Activating it would produce a card with no restrictions at all. " \
        "Fix the lock, then try again."
    end

    # Union of every level. Bans only ever accumulate.
    def widened_policy(local, inherited)
      ([local] + inherited).flat_map { |value| Array(value) }.compact_blank.uniq
    end

    # Nearest level that sets the field at all wins.
    def nearest_policy(local, inherited)
      return local if local.present?

      inherited.find(&:present?)
    end
  end

end
