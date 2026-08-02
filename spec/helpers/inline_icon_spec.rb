# frozen_string_literal: true

require "rails_helper"

# `ApplicationHelper#inline_icon` reads the SVG off disk and raises
# Errno::ENOENT when it is missing. Because icons appear in shared partials
# (the org nav, the transaction drawer), one bad name 500s every page that
# renders that partial — not just the feature it belongs to.
#
# This has bitten Fuime twice: the storefront and tax tracker shipped with
# nonexistent icons, and the Taxes nav item shipped with "money-dollar-box",
# which took out every page rendering events/_nav.
RSpec.describe "inline_icon references" do
  it "every literal icon name resolves to an SVG on disk" do
    names = Dir.glob(Rails.root.join("app/{views,helpers}/**/*.{erb,rb}")).flat_map { |file|
      File.read(file).scan(/inline_icon\s+["']([a-z0-9_-]+)["']/).flatten
    }.uniq

    expect(names).not_to be_empty, "the scan found no icon references — has inline_icon been renamed?"

    missing = names.reject do |name|
      Rails.root.join("app/assets/images/icons/#{name}.svg").exist?
    end

    expect(missing).to be_empty, "icons referenced but not on disk: #{missing.join(', ')}"
  end
end
