# frozen_string_literal: true

# Second half of AddBusinessTypeToEventApplications, split per the house pattern:
# validating a check constraint takes a lock proportional to the table.
class ValidateEventApplicationBusinessType < ActiveRecord::Migration[8.0]
  def change
    validate_check_constraint :event_applications, name: "event_applications_starting_point_known"
  end

end
