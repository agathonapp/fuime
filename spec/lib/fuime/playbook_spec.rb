# frozen_string_literal: true

require "rails_helper"

# Fuime: the /learn reading list.
#
# The prose lives in partials and is asserted against in
# spec/requests/learn_spec.rb, where it is rendered. What is checked here is the
# structure — and specifically the one invariant that makes the structure worth
# having: a lesson's key is both its URL and its partial name, so a lesson that
# appears on the index cannot 404 or 500 when somebody opens it.
RSpec.describe Fuime::Playbook do
  it "keeps every key unique" do
    keys = described_class.lessons.map(&:key)

    expect(keys.uniq).to eq(keys)
  end

  it "has a partial on disk for every lesson it lists" do
    described_class.lessons.each do |lesson|
      path = Rails.root.join("app/views/#{File.dirname(lesson.partial)}/_#{File.basename(lesson.partial)}.html.erb")

      expect(path).to exist, "#{lesson.key} is listed but #{path} does not exist"
    end
  end

  it "lists no partial that is not a lesson" do
    on_disk = Dir[Rails.root.join("app/views/learn/lessons/_*.html.erb")]
              .map { |f| File.basename(f, ".html.erb").delete_prefix("_") }
    listed = described_class.lessons.map { |lesson| lesson.key.tr("-", "_") }

    expect(on_disk.sort).to eq(listed.sort)
  end

  it "gives every lesson something to read on the index" do
    described_class.lessons.each do |lesson|
      expect(lesson.title).to be_present
      expect(lesson.blurb).to be_present
    end
  end

  it "resolves a key, and an unknown key to nothing" do
    expect(described_class.find("pricing")&.title).to be_present
    expect(described_class.find("how-to-get-rich")).to be_nil
    expect(described_class.key?("pricing")).to be(true)
    expect(described_class.key?("pricing ")).to be(false)
  end

  # URL slugs. A key with an underscore or a capital would still work as a route
  # and would quietly produce two spellings of the same lesson in links people
  # share.
  it "keeps every key url-shaped" do
    described_class.lessons.each do |lesson|
      expect(lesson.key).to match(/\A[a-z0-9]+(-[a-z0-9]+)*\z/), "#{lesson.key} is not a clean slug"
    end
  end

end
