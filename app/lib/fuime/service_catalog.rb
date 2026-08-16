# frozen_string_literal: true

# Fuime: the services a 16- or 17-year-old can actually sell through Fuime today,
# and the starter template for each.
#
# ── Why a catalog exists at all ─────────────────────────────────────────────
#
# `Event::BUSINESS_CATEGORIES` is five words (`crafts services digital food
# other`) and `Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES` is one of them.
# That is enough to decide whether a venture may sell and nothing like enough to
# ask a teenager what their business is. "Services" is not an answer anybody gives
# to "what do you do"; "I mow lawns" is.
#
# So this sits between the two: a list of concrete things a person recognises,
# each mapping to the one category the launch scope permits. Product copy, not
# schema — which is why it lives here and not in an enum or a table. It will be
# edited far more often than the database will.
#
# ── Why some obvious teen businesses are missing ────────────────────────────
#
# **Babysitting and childcare are deliberately absent, and so is coaching
# children.** They are the two most common teen service businesses in the
# country, so their absence is a decision rather than an oversight.
#
# Under merchant-of-record Fuime LLC is the legal seller of whatever the operator
# sells. For lawn mowing that means Fuime carries the risk that the lawn is cut
# badly. For childcare it means Fuime is the seller of record on a service where
# the foreseeable failure is injury to a child — a different order of liability,
# a different insurance conversation, and one nobody has had. The same reasoning
# excludes coaching and instruction involving physical activity with minors.
#
# Music and academic tutoring stay: the failure mode is a wasted hour.
#
# This is a launch-scope judgement, not a permanent one. It belongs in the
# vetting conversation with counsel (MOR_MIGRATION_PLAN §7 Q1), and the right
# outcome may well be "allowed, with insurance" rather than "never".
#
# ── Why no template carries a price ─────────────────────────────────────────
#
# The most useful line a starter template could contain is "most people charge
# about $25 for this", and it is the one line Fuime may not write. §8.3 D2's
# mitigation for worker misclassification is that operators control their own
# pricing, clients and hours, and that Fuime never routes work or sets rates. A
# *suggested* rate is a set rate with a softer verb — it is precisely what an
# examiner would read it as. Templates carry structure and words; the operator
# brings the number.
#
# `spec/lib/fuime/service_catalog_spec.rb` asserts this against every template
# rather than trusting it to a comment, because the pressure to add "typical
# pricing" to this file will be constant.
module Fuime
  class ServiceCatalog
    # One thing a person can say they do.
    #
    # `category` is the `Event::BUSINESS_CATEGORIES` value this resolves to. Every
    # entry currently resolves to "services" — that is the launch scope, not a
    # property of the structure, and the field exists so opening `digital` later
    # is an addition here rather than a rewrite.
    Service = Struct.new(:key, :name, :blurb, :category, :description_prompt, :checklist, keyword_init: true) do
      def to_param = key
    end

    SERVICES = [
      Service.new(
        key: "tutoring",
        name: "Tutoring",
        blurb: "Help other students with a subject you're good at.",
        category: "services",
        description_prompt: "I tutor students in …",
        checklist: [
          "Decide which subjects and year groups you'll take",
          "Work out how long a session runs and what you'll cover",
          "Decide whether you meet in person, online, or both",
          "Set your own rate — Fuime never sets it for you",
          "Write one sentence a parent can read and understand"
        ]
      ),
      Service.new(
        key: "lawn_and_garden",
        name: "Lawn & garden",
        blurb: "Mowing, weeding, leaf clearing, and seasonal tidy-ups.",
        category: "services",
        description_prompt: "I mow lawns and do garden work for …",
        checklist: [
          "List exactly which jobs you do and which you don't",
          "Check whose equipment you're using and who maintains it",
          "Decide how far you'll travel",
          "Set your own rate — per visit or per hour, your call",
          "Agree what happens if it rains"
        ]
      ),
      Service.new(
        key: "pet_care",
        name: "Pet care",
        blurb: "Dog walking, feeding, and looking in on pets while owners are away.",
        category: "services",
        description_prompt: "I walk dogs and look after pets for …",
        checklist: [
          "Decide which animals you'll take and which you won't",
          "Agree how you'll get keys or access, and hand them back",
          "Ask every owner for their vet's number before the first booking",
          "Set your own rate — per walk, per visit, or per day",
          "Say what happens if an animal gets ill on your watch"
        ]
      ),
      Service.new(
        key: "cleaning",
        name: "Cleaning & tidying",
        blurb: "Houses, cars, garages, and post-event clear-ups.",
        category: "services",
        description_prompt: "I clean …",
        checklist: [
          "List which rooms or jobs are included and which cost extra",
          "Decide whose cleaning supplies you use",
          "Work out how long a typical job takes before you quote",
          "Set your own rate",
          "Agree what you do if something gets broken"
        ]
      ),
      Service.new(
        key: "photography_video",
        name: "Photo & video",
        blurb: "Events, portraits, product shots, and editing.",
        category: "services",
        description_prompt: "I photograph and film …",
        checklist: [
          "Decide what you shoot and what you don't",
          "Say how many edited photos or minutes a booking includes",
          "Agree how long delivery takes",
          "Write down who may use the images and where",
          "Set your own rate"
        ]
      ),
      Service.new(
        key: "design_and_art",
        name: "Design & illustration",
        blurb: "Logos, posters, social graphics, and commissions.",
        category: "services",
        description_prompt: "I design …",
        checklist: [
          "Decide how many rounds of changes a price includes",
          "Say which file formats the customer gets",
          "Agree who owns the finished artwork",
          "Decide your turnaround time and stick to it",
          "Set your own rate"
        ]
      ),
      Service.new(
        key: "web_and_tech",
        name: "Websites & tech help",
        blurb: "Building simple sites, fixing devices, and setting things up.",
        category: "services",
        description_prompt: "I build websites and help people with …",
        checklist: [
          "Decide what counts as the job and what counts as support afterwards",
          "Agree who pays for domains, hosting, and anything else bought in",
          "Say what happens if something breaks later",
          "Never take a customer's passwords — get your own access",
          "Set your own rate"
        ]
      ),
      Service.new(
        key: "music_lessons",
        name: "Music lessons",
        blurb: "Teaching an instrument or voice you already play well.",
        category: "services",
        description_prompt: "I teach …",
        checklist: [
          "Decide the instrument, the levels you'll take, and the lesson length",
          "Say whether the student needs their own instrument",
          "Decide where lessons happen",
          "Agree your cancellation rule before the first lesson",
          "Set your own rate"
        ]
      ),
      Service.new(
        key: "event_help",
        name: "Event help",
        blurb: "Setting up, serving, running a stall, and clearing away.",
        category: "services",
        description_prompt: "I help at events by …",
        checklist: [
          "List exactly what you'll do on the day",
          "Agree your start and finish times in writing",
          "Check whether you need to bring anything",
          "Decide your minimum booking length",
          "Set your own rate"
        ]
      ),
      Service.new(
        key: "other_service",
        name: "Something else",
        blurb: "A service that isn't on this list — tell us about it.",
        category: "services",
        description_prompt: "I …",
        checklist: [
          "Write one sentence saying exactly what the customer gets",
          "Decide what's included and what isn't",
          "Work out how long it takes you",
          "Set your own rate",
          "Say what happens if the customer isn't happy"
        ]
      )
    ].freeze

    # have_business | have_idea | from_template.
    #
    # The fork Whop opens with, with the third card changed — see
    # AddBusinessTypeToEventApplications for why "clone a proven business" cannot
    # exist here.
    StartingPoint = Struct.new(:key, :name, :blurb, keyword_init: true)

    STARTING_POINTS = [
      StartingPoint.new(
        key: "have_business",
        name: "I already run this",
        blurb: "You're selling now and want Fuime to handle the money side."
      ),
      StartingPoint.new(
        key: "have_idea",
        name: "I have an idea",
        blurb: "You know what you want to sell and haven't started yet."
      ),
      StartingPoint.new(
        key: "from_template",
        name: "Start from a template",
        blurb: "Not sure yet? Pick a common service and we'll set up the outline."
      )
    ].freeze

    STARTING_POINT_KEYS = STARTING_POINTS.map(&:key).freeze

    class << self
      def services = SERVICES

      def find(key)
        SERVICES.find { |service| service.key == key.to_s }
      end

      def key?(key)
        SERVICES.any? { |service| service.key == key.to_s }
      end

      def starting_point(key)
        STARTING_POINTS.find { |point| point.key == key.to_s }
      end

      # Which `Event::BUSINESS_CATEGORIES` value a service key resolves to, or nil
      # for a key that is not in the catalog.
      #
      # nil rather than a default, deliberately: a category guessed on behalf of a
      # venture is a category `Fuime::OperatorEligibility` will then act on, and
      # "services" is the one value that unblocks selling. Guessing it would be
      # guessing an approval.
      def category_for(key)
        find(key)&.category
      end

      # The services a venture may actually be created under right now.
      #
      # Everything, today — the catalog is already scoped to the launch categories.
      # It exists as its own method so that opening `digital` later widens the
      # catalog without also widening what the picker offers on the same commit.
      def sellable
        SERVICES.select { |service| ::Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES.include?(service.category) }
      end

    end

  end
end
