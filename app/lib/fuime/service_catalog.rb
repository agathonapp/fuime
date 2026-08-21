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
# ── Software, and the one thing it may not promise ──────────────────────────
#
# The four software templates are shaped around a ONE TIME payment, and that is
# a fact about Fuime rather than a view about software. `Fuime::Offer` has no
# recurring concept and merchant-of-record checkout is `mode: "payment"`, so an
# operator can sell access to a tool and cannot bill for it monthly. The
# subscription machinery that does exist (`Fuime::Subscription`) bills the
# FAMILY for Fuime, not an operator's customers for the operator.
#
# So none of these may describe a monthly plan, and `web_apps` says the limit out
# loud, because "charge a few dollars a month" is the first thing anybody thinks
# of when they think SaaS. That is L8: never let copy describe a product that
# does not exist. When recurring billing ships, the spec breaks until the copy is
# updated.
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
#
# `offer_ideas` is where that pressure now lands hardest, because an offer is a
# name AND a price everywhere else in the product, and an idea that carries only
# half of one looks unfinished. It is not unfinished. It is the half Fuime is
# allowed to write.
module Fuime
  class ServiceCatalog
    # One thing a person can say they do.
    #
    # `category` is the `Event::BUSINESS_CATEGORIES` value this resolves to.
    # `services` and, since 2026-08-20, `digital` — the two that
    # `Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES` allows a venture to sell
    # under. `crafts`, `food` and `other` are still closed, so no template may
    # resolve to one; a template for something a venture cannot be created under
    # is an advert for a dead end.
    #
    # ── The last three fields, and why they live here ────────────────────────
    #
    # `key`..`checklist` are what the application flow asks for. The three below
    # are what /learn shows somebody who has not applied yet, and they are on the
    # same object rather than in a parallel "content" file for one reason: a
    # second list keyed by the same strings drifts. Add a service and forget the
    # other file, and the browsable version of the catalog quietly disagrees with
    # the one a teenager signs up through.
    #
    #   offer_ideas      — things to list on a storefront. NAMES AND UNITS ONLY.
    #                      Each one links to the new-offer form with the name
    #                      pre-filled and the price box empty, which is the whole
    #                      shape of the rule below: Fuime writes the words, the
    #                      operator writes the number.
    #   first_customers  — where the first few actually come from, for this trade.
    #   watch_out        — what goes wrong in this trade specifically, including
    #                      the costs that a first-time quote forgets.
    #
    # All three are optional at the struct level and read through `Array()` by
    # callers, so a service added without them renders a shorter page rather than
    # raising on a nil.
    Service = Struct.new(:key, :name, :blurb, :category, :description_prompt, :checklist,
                         :offer_ideas, :first_customers, :watch_out, keyword_init: true) do
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
          "Set your own rate. Nobody else picks it for you",
          "Write one sentence a parent can read and understand"
        ],
        offer_ideas: [
          { name: "One-hour tutoring session", unit_label: "per session" },
          { name: "Block of four sessions", unit_label: "per block" },
          { name: "Exam revision session", unit_label: "per session" }
        ],
        first_customers: [
          "Your own teachers. Ask which students have come to them wanting extra help",
          "The year below you, sitting the exam you sat last year",
          "Parents' groups a guardian of yours is already in",
          "The noticeboard at a library or community centre"
        ],
        watch_out: [
          "Never guarantee a grade. You are selling the hours, not the result.",
          "Meeting in a library or another public place protects you as much as the student.",
          "Doing the homework for them is the fastest way to lose the parent who pays.",
          "Agree what happens to a session cancelled the night before, before one is."
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
          "Set your own rate, per visit or per hour, your call",
          "Agree what happens if it rains"
        ],
        offer_ideas: [
          { name: "Front and back lawn mow", unit_label: "per visit" },
          { name: "A month of weekly mows", unit_label: "paid up front" },
          { name: "Leaf clearing", unit_label: "per visit" },
          { name: "Hedge trim", unit_label: "per visit" }
        ],
        first_customers: [
          "The houses either side of yours, and then the rest of the street",
          "Any garden you walk past that has visibly got away from someone",
          "Neighbours who have stopped being able to do it themselves",
          "A note through the door beats a post online in a street you already live on"
        ],
        watch_out: [
          "Fuel, bags and blade sharpening come out of what you charge. Count them before you quote.",
          "Look at the garden before you name a number. A photo hides the slope and the size.",
          "Agree the rain rule at the start: rescheduled, or done anyway.",
          "A stone thrown by a mower can break a window. Ask a guardian whether the household insurance covers you."
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
          "Set your own rate, per walk, per visit, or per day",
          "Say what happens if an animal gets ill on your watch"
        ],
        offer_ideas: [
          { name: "30-minute dog walk", unit_label: "per walk" },
          { name: "Drop-in visit while you're away", unit_label: "per visit" },
          { name: "A week of daily visits", unit_label: "per week" }
        ],
        first_customers: [
          "The dog owners you already pass at the same time every day",
          "A vet's noticeboard, with a guardian's phone number on it",
          "Neighbours the week before a school holiday, when they are booking travel",
          "Someone whose dog you have already walked once for nothing"
        ],
        watch_out: [
          "Get the owner's vet number and a second contact before the first booking, not during the first emergency.",
          "Write down who pays if an animal needs a vet on your watch.",
          "Never take on an animal you cannot physically hold if it decides to go somewhere.",
          "Keys: agree how you get them and hand them back, and never keep a copy."
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
        ],
        offer_ideas: [
          { name: "Car wash, inside and out", unit_label: "per car" },
          { name: "Garage or shed clear-out", unit_label: "per job" },
          { name: "Post-party clear-up", unit_label: "per job" }
        ],
        first_customers: [
          "Your own street on the morning after any big local event",
          "Neighbours with a car that is never clean and a drive you can see",
          "Anyone who has just moved in or is about to move out",
          "A family friend's small office or shop, out of hours"
        ],
        watch_out: [
          "Time one job properly before you ever quote a fixed price for that job again.",
          "Decide whose cleaning supplies are used. If they are yours, they are a cost.",
          "Say in advance what happens if something gets broken. It will, eventually.",
          "Do not move anything heavy on your own, however much it would speed the job up."
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
        ],
        offer_ideas: [
          { name: "Portrait session, edited photos included", unit_label: "per session" },
          { name: "Event coverage", unit_label: "per hour" },
          { name: "Product photos for a small shop", unit_label: "per batch" }
        ],
        first_customers: [
          "Local shops whose product photos were taken on a phone in bad light",
          "Sports teams and clubs, in the week before their season starts",
          "One friend's business for free, on the condition you may show the pictures",
          "Anyone already running an event you were going to attend anyway"
        ],
        watch_out: [
          "Editing is the job, not the afterthought. Count those hours or you are working for a fraction of what you thought.",
          "Put in writing who may use the images, where, and for how long.",
          "Ask before photographing anyone under 18, and ask again before posting them.",
          "Back up the card before you format it. There is no second take of a wedding."
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
        ],
        offer_ideas: [
          { name: "Logo with three concepts", unit_label: "per logo" },
          { name: "Set of social media graphics", unit_label: "per set" },
          { name: "Character commission", unit_label: "per piece" }
        ],
        first_customers: [
          "Communities you are already in, where people have seen your work for free",
          "Small businesses whose sign and whose website do not look like each other",
          "Anyone who has already asked you to 'just quickly make' something",
          "A public post of finished work beats a public post asking for work"
        ],
        watch_out: [
          "Cap the number of revision rounds in writing. 'Until you're happy' is not a scope.",
          "Say who owns the finished artwork and whether you may show it.",
          "Never use a font, photo or brush you do not have a license for. The customer inherits that problem.",
          "Ask for part of the payment before you start on anything large."
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
          "Never take a customer's passwords. Get your own account with your own access",
          "Set your own rate"
        ],
        offer_ideas: [
          { name: "One-page site for a small business", unit_label: "per site" },
          { name: "Monthly updates and small changes", unit_label: "per month" },
          { name: "Device setup or repair", unit_label: "per job" }
        ],
        first_customers: [
          "Local businesses whose website is a Facebook page or nothing at all",
          "The place you already buy from, where you can point at what you would change",
          "Older neighbors, for setup and repair work nobody else will sit down and do",
          "One site built free and shown publicly, used as the thing you point people at"
        ],
        watch_out: [
          "Agree who buys the domain and the hosting. If it is you, it is a cost that repeats.",
          "Never take a customer's password. Get your own account with your own access.",
          "Say clearly where the job ends and where paid support starts.",
          "Back up whatever you are about to change before you change it."
        ]
      ),
      # Fuime: the software half of the catalog, added 2026-08-20.
      #
      # `digital` became sellable the same day (Fuime::OperatorEligibility, opened
      # on the founder's call), which is what makes these templates honest rather
      # than an advert for a dead end.
      #
      # ⚠️ Every one of these is shaped around a ONE TIME payment, and that is not a
      # style choice. Fuime::Offer has no recurring concept and merchant-of-record
      # checkout is `mode: "payment"`, so an operator can sell access to software
      # but cannot bill for it monthly. A template that said "charge $5 a month"
      # would be describing a product Fuime does not have, which is exactly the L8
      # failure. When subscriptions ship, these three fields are where to look, and
      # spec/lib/fuime/service_catalog_spec.rb fails until somebody does.
      Service.new(
        key: "web_apps",
        name: "Web apps & tools",
        blurb: "Small software people pay to use. Built quickly, sold once.",
        category: "digital",
        description_prompt: "I build a tool that …",
        checklist: [
          "Write down the one thing your tool does, in one sentence, before you build it",
          "Decide what a buyer actually gets: access to yours, or their own copy",
          "Work out what it costs you every month to keep it running, hosting and AI usage included",
          "Set your own rate. Fuime cannot bill your customers monthly yet, so price it as a one time purchase",
          "Say what happens if you stop maintaining it"
        ],
        first_customers: [
          "The community where you already watch people complain about the problem",
          "Anyone doing the job by hand in a spreadsheet",
          "A small business you can physically watch doing it the slow way",
          "Post the thing working, not the thing planned. A demo finds buyers, an announcement finds nobody"
        ],
        watch_out: [
          "Hosting and AI usage cost you money every month whether anybody buys or not. Know that number before you launch, because it is the first fixed cost most software businesses meet.",
          "Fuime cannot charge your customers monthly yet, so sell lifetime access or a setup fee rather than promising a subscription you have no way to bill.",
          "Free users are not customers. Ten people happily using it for nothing is not evidence that one person will pay.",
          "Selling software is taxed in a lot of states. Ask before you assume it is not.",
          "Collect nothing about your users that you do not need, and never store anybody's password."
        ],
        offer_ideas: [
          { name: "Lifetime access to the tool", unit_label: "one time" },
          { name: "Set it up on the customer's own account", unit_label: "per setup" },
          { name: "A custom version built for one business", unit_label: "per build" }
        ]
      ),
      Service.new(
        key: "discord_bots",
        name: "Discord bots & servers",
        blurb: "Building bots and setting up servers for people who run communities.",
        category: "services",
        description_prompt: "I build Discord bots and set up servers for …",
        checklist: [
          "Write down exactly what the bot does before you write any of it",
          "Agree who hosts it and who pays for the hosting",
          "Say what happens if Discord changes something and it breaks",
          "Set your own rate, per bot or per hour, your call",
          "Never ask for somebody's Discord account. Get your own bot token"
        ],
        first_customers: [
          "Servers you are already in, where you can see what is missing",
          "Anybody asking for a bot in a community you are part of",
          "Small creators whose server is growing faster than they can moderate it",
          "One server done well and publicly credited is the best advert you will get"
        ],
        watch_out: [
          "A bot you host is a bot you are responsible for at two in the morning. Handing over the code is a completely different job to running it, and should be a different price.",
          "Hosting costs money every month. Decide whose cost that is before you quote, not after.",
          "Discord changes how its API works. Say in advance whether fixing that later is included.",
          "Never take somebody's password or account access. You do not need either to build them a bot."
        ],
        offer_ideas: [
          { name: "A custom bot built to order", unit_label: "per bot" },
          { name: "Full server setup with roles and channels", unit_label: "per server" },
          { name: "Adding a feature to a bot you already built", unit_label: "per feature" }
        ]
      ),
      Service.new(
        key: "ai_automation",
        name: "AI & automation",
        blurb: "Setting up tools that do the boring, repeated parts of somebody's work.",
        category: "services",
        description_prompt: "I set up automations that …",
        checklist: [
          "Find one task somebody does the same way every week. That is the one to automate",
          "Time how long it takes them now, so you can say what you saved",
          "Agree who pays for the tools and accounts it runs on",
          "Set your own rate, and price what it is worth to them rather than how long it took you",
          "Say what happens when it breaks, because eventually it will"
        ],
        first_customers: [
          "Small businesses near you still doing something repetitive by hand",
          "Anyone who has said out loud that they do this every week and hate it",
          "The people who already come to you when a computer misbehaves",
          "Your own family's business, done once for free, then shown to everyone else"
        ],
        watch_out: [
          "Never take a customer's passwords. Ask them to give you your own access, which they can take back.",
          "An automation doing the wrong thing quietly is worse than no automation. Watch it run for a week before you walk away.",
          "You are building on tools that can change their prices or shut down. Say in advance who deals with that.",
          "Do not promise it will save a specific amount of money. Promise exactly what it does and let them do that sum."
        ],
        offer_ideas: [
          { name: "One task automated, set up and handed over", unit_label: "per automation" },
          { name: "A session working out what to automate first", unit_label: "per session" },
          { name: "Fixing or improving an automation later", unit_label: "per visit" }
        ]
      ),
      Service.new(
        key: "digital_downloads",
        name: "Templates & downloads",
        blurb: "Notion templates, presets, icon packs, and anything else somebody downloads once.",
        category: "digital",
        description_prompt: "I make and sell …",
        checklist: [
          "Pick one thing that solves one problem, rather than a bundle of everything",
          "Decide what a buyer may do with it, and whether they may resell it",
          "Check you have the right to every font, image and asset inside it",
          "Set your own rate, and remember that a second copy costs you nothing to make",
          "Write the instructions as if the buyer has never opened the tool before"
        ],
        first_customers: [
          "The community where you first watched people struggle with the thing",
          "Show it being used rather than a picture of it sitting there",
          "The people who asked you to share yours after they saw it",
          "A free simple version, with the full one for sale next to it"
        ],
        watch_out: [
          "Your cost of making one more copy is close to nothing, which changes how to price it completely. Pricing by how long it took you is the wrong instinct here.",
          "Selling digital goods is taxed in a lot of states. Ask before you assume it is not.",
          "Check the license on every font and asset you used. Selling something built on an asset you may not resell becomes the buyer's problem and then yours.",
          "Once it has been downloaded you cannot take it back. Decide and publish your refund rule before your first sale."
        ],
        offer_ideas: [
          { name: "The template on its own", unit_label: "one time" },
          { name: "A bundle of several", unit_label: "one time" },
          { name: "A custom version made for one buyer", unit_label: "per commission" }
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
        ],
        offer_ideas: [
          { name: "30-minute lesson", unit_label: "per lesson" },
          { name: "Block of four lessons", unit_label: "per block" }
        ],
        first_customers: [
          "Your own teacher, who turns away beginners they have no room for",
          "The younger years at your school who have just picked up the instrument",
          "A local music shop's noticeboard",
          "Whoever runs the ensemble or band you already play in"
        ],
        watch_out: [
          "Agree the cancellation rule before the first lesson, not after the first no-show.",
          "Say whether the student needs their own instrument.",
          "Teach only to a level you can actually hear. Turning a student away builds more trust than struggling.",
          "Lessons happen somewhere a parent knows about and can walk into."
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
        ],
        offer_ideas: [
          { name: "Setup and clear-away", unit_label: "per event" },
          { name: "Running a stall", unit_label: "per day" },
          { name: "Serving shift", unit_label: "per hour" }
        ],
        first_customers: [
          "Venues and halls that host the same events every month",
          "Market organizers, who are always short-handed on the morning",
          "Anyone in your family already helping run something",
          "The event you were going to attend anyway"
        ],
        watch_out: [
          "Get the start and finish times in writing. 'Until we're done' has no end.",
          "Set a minimum booking so a two-hour round trip is not paid as one hour.",
          "Some venues will not let under-18s do some jobs, and anything involving alcohol is one of them. Ask first.",
          "Handling food for the public can need a hygiene certificate. Check before the day, not on it."
        ]
      ),
      Service.new(
        key: "other_service",
        name: "Something else",
        blurb: "A service that isn't on this list. Tell us about it.",
        category: "services",
        description_prompt: "I …",
        checklist: [
          "Write one sentence saying exactly what the customer gets",
          "Decide what's included and what isn't",
          "Work out how long it takes you",
          "Set your own rate",
          "Say what happens if the customer isn't happy"
        ],
        offer_ideas: [
          { name: "The main thing you do", unit_label: "per job" }
        ],
        first_customers: [
          "Everyone who has already asked you to do this for nothing",
          "The place where those people already talk to each other",
          "One customer served visibly well, asked out loud for a recommendation",
          "The person nearest to you with the problem you solve"
        ],
        watch_out: [
          "Write one sentence saying exactly what the customer gets. If you cannot, you cannot price it either.",
          "Say what is not included, in the same breath as what is.",
          "Time yourself doing it once before you quote it twice.",
          "Decide now what you do if someone is unhappy."
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
