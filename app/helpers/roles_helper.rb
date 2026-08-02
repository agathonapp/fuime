# frozen_string_literal: true

# Fuime: user-facing names for organizer position roles.
#
# The `role` enum keeps upstream's values (reader / member / manager) — they are
# woven through policies, `OrganizerPosition.role_at_least?`, spending controls,
# invites, and team filters, and CLAUDE.md Rule 6 keeps internals on upstream
# names so we can still merge fixes from hackclub/hcb. Only the words a teenager
# or a parent reads change here.
#
# The mapping is deliberately in ONE place: role names were previously rendered
# ad-hoc with `.capitalize` and `.humanize` in four different partials, which is
# how a rename ends up half-applied.
module RolesHelper
  ROLE_LABELS = {
    "manager" => "Owner",
    "member"  => "Team member",
    "reader"  => "Parent",
  }.freeze

  ROLE_DESCRIPTIONS = {
    "manager" => "Runs the business. Can do everything, including inviting people and changing settings.",
    "member"  => "Works in the business. Can see the money and use cards, but can't move money out or change settings.",
    "reader"  => "Can see everything, change nothing. This is the seat for a parent or guardian keeping an eye on things.",
  }.freeze

  # Falls back to `humanize` so an unmapped or future role still renders as
  # something readable rather than blank.
  def role_label(role)
    return "" if role.blank?

    ROLE_LABELS.fetch(role.to_s, role.to_s.humanize)
  end

  def role_description(role)
    ROLE_DESCRIPTIONS[role.to_s]
  end

  # [label, value] pairs for a role <select>, ordered most- to least-privileged
  # so the list reads top-down the way people think about permissions.
  def role_options_for_select(roles = OrganizerPosition.roles.keys)
    ordered = ["manager", "member", "reader"] & roles.map(&:to_s)
    ordered.map { |role| [role_label(role), role] }
  end
end
