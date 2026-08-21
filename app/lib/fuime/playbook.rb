# frozen_string_literal: true

# Fuime: the reading list at /learn — the money lessons that are the same
# whether you mow lawns or edit video.
#
# ── Why this is metadata and the prose is not ───────────────────────────────
#
# Every lesson body is an ERB partial in app/views/learn/lessons/. This file
# holds only the title, the one-line summary, and the order. The prose is not
# here because it is prose: it wants links to real pages in the product
# (`fuime_taxes_path`, the ledger, the FAQ), it wants the platform fee read out
# of `Event::Plan` rather than typed as a number that will one day be wrong, and
# it wants a designer to be able to open it. A Ruby array of heredocs gets none
# of that and would have every one of those numbers hardcoded within a month.
#
# ── Why it is not a database table either ──────────────────────────────────
#
# The same reason the legal pages are not. These lessons tell a sixteen-year-old
# what a chargeback does to them, what the platform keeps, and what the IRS
# expects — claims about money and law made to minors. Editing them should
# require a pull request that someone reads, exactly like editing
# app/views/static_pages/terms.html.erb does. A CMS would make it an afternoon's
# work for one person with a login, which is the wrong amount of friction for
# this particular content.
#
# ── The one rule the lessons share with Fuime::ServiceCatalog ───────────────
#
# No lesson may suggest what to charge. The pricing lesson teaches the method
# without naming the answer, because §8.3 D2's mitigation for worker
# misclassification is that operators set their own rates and Fuime never does.
#
# The line is between arithmetic and advice. A worked example with real figures
# in it is arithmetic, and "the-numbers" would be useless without one — it is
# labelled as an illustration and the figures are costs, not rates. "Most people
# charge about X" is advice, and it is the thing that may not appear.
# spec/requests/learn_spec.rb holds that line against the rendered pages rather
# than trusting it to this paragraph.
module Fuime
  class Playbook
    # `key` is the URL slug and also names the partial: "what-you-keep" renders
    # app/views/learn/lessons/_what_you_keep.html.erb. One identifier rather than
    # two, so a lesson cannot be listed on the index and 500 when it is opened.
    Lesson = Struct.new(:key, :title, :blurb, keyword_init: true) do
      def to_param = key

      def partial = "learn/lessons/#{key.tr("-", "_")}"
    end

    # In the order the questions actually arrive in: is this worth selling, what
    # do I charge, does the arithmetic work, how do I find people, how do I keep
    # them, and how do I not run out of money. Fuime's own mechanics are last and
    # are one lesson, because a reader learning to run a business needs six pages
    # about business and one page about us.
    LESSONS = [
      Lesson.new(
        key: "what-people-pay-for",
        title: "What people actually pay for",
        blurb: "A good idea and a good business are different things. This is how to tell, before you spend a month on it."
      ),
      Lesson.new(
        key: "pricing",
        title: "How to set a price",
        blurb: "The number is yours to pick. This is how to pick it on purpose instead of guessing."
      ),
      Lesson.new(
        key: "the-numbers",
        title: "The numbers that decide if it works",
        blurb: "Costs, margin and break-even, worked through on a business somebody could actually run."
      ),
      Lesson.new(
        key: "getting-customers",
        title: "How to get customers",
        blurb: "Where the first few come from, and how to turn that into something that keeps happening."
      ),
      Lesson.new(
        key: "keeping-customers",
        title: "How to keep them",
        blurb: "Winning a customer is the expensive part. Most of the money is in the second sale."
      ),
      Lesson.new(
        key: "cash-and-records",
        title: "Cash, records and tax",
        blurb: "Profitable businesses run out of money all the time. Here is how that happens and how to avoid it."
      ),
      Lesson.new(
        key: "what-fuime-takes",
        title: "What Fuime takes, and when you get paid",
        blurb: "The fee, the payout, and who signs it off. Short, because it is the only part of this that is about us."
      )
    ].freeze

    class << self
      def lessons = LESSONS

      def find(key)
        LESSONS.find { |lesson| lesson.key == key.to_s }
      end

      def key?(key)
        LESSONS.any? { |lesson| lesson.key == key.to_s }
      end

    end

  end
end
