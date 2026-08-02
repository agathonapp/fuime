# frozen_string_literal: true

module LoginsHelper
  # Emptied for Fuime. The single entry was Hack Club's 2022 "Assemble"
  # hackathon: a photo of its crowd served from cdn.hackclub.com, used as a
  # login-page background, linking to a `/assemble` route that does not exist
  # in this app.
  #
  # `sample_hackathon` has no callers anywhere in app/ or spec/ — the module is
  # included via ApplicationHelper, which makes the method available but never
  # invokes it — so nothing renders today either way. Kept rather than deleted
  # (CLAUDE.md Rule 2); `sample_hackathon` now returns nil, so any future caller
  # must handle the empty case.
  HACKATHONS = [].map do |hackathon|
    hackathon[:url] = "/#{hackathon[:slug]}"

    hackathon
  end.freeze

  def sample_hackathon
    HACKATHONS.sample(1, random: Random.new(Time.now.to_i / 5.minutes)).first
  end

end
