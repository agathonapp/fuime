# Onboarding wizard — synthesized spec (2026-09-11 design panel)
**Status: design complete, NOT yet audited, NOT yet built.** Produced by a three-designer
judge panel (teen-first, parent-first, engineering-fit angles; three judges; one
synthesis). The planned adversarial constraint audit (L1–L8, ONBOARDING_PLAN §3/§7,
route/method verification) did **not** run — the session hit its usage limit — so
**run that audit before implementing**, and treat every route/method named here as
"verify by grep first". Branch for the build: `fuime/onboarding-wizard` (this file's
branch, off `origin/main` at #104). The Playground's *Start fresh as Sam*
(`fuime/playground-demo-polish`) lands a nameless founder on `/` → `redirect_to_onboarding`,
which this spec re-points at `/setup`.

**Founder's standing instructions (2026-09-11), which override anything below that
disagrees:** the parent invite is a step in onboarding, but the teen can keep going
and start selling while the parent's acceptance is pending — the guardian is needed
only for payouts (merchant-of-record; `User#permitted_to_operate_business?` is
unconditionally true under MoR and `Fuime::GuardianshipEnforcement` never parks a
teen). Both entry orders are wanted: parent sets up the family then adds the teen,
or the teen starts and invites a parent. Multi-screen, step-based, clean animations,
modern fintech look, following the current Fuime UI.

# Fuime family setup wizard — final implementable spec

Synthesised from Design 2 (majority winner, two of three judges; highest on constraint compliance and truthfulness) with every non-conflicting graft from Designs 1 and 3. Grounded in the read-only worktree `wt-playground` (branch `fuime/playground-demo-polish`, PRs #98–#105 merged). Every route, controller, method and view named below was verified by grep unless marked **NEW**. Production money model: merchant-of-record (`Fuime::Features.merchant_of_record?` reads `FEATURE_MERCHANT_OF_RECORD`, `true` in `.env.development` and `render.yaml`). No Connect-path behaviour is designed.

---

## 0. Decisions — every disagreement between the three designs, resolved

| # | Question | Decision | Taken from / why |
|---|---|---|---|
| D1 | Does the parent's "my teen is 13+" tick get persisted to the teen's `age_attestation`? | **No. Session-only entry gate; the teen ticks their own write-once box on `you`.** | Design 2. Design 1's `attest_minor_13_plus!` on the stub with the parent's IP/UA was a §3 violation (all three judges); Design 3 had no parent-side gate at all, so a 10-year-old could be signed for. |
| D2 | Guardianship status before the teen has joined | **`active`, no `awaiting_minor`.** `active` records exactly what happened: an adult signed agreement v4 for this minor, with version/IP/UA. "Teen hasn't joined" is derived from `minor.onboarding?` (`full_name_in_database.blank?`). | All three designs; ONBOARDING_PLAN §5 E1's `awaiting_minor` is superseded by this analysis (record in ONBOARDING_PLAN). |
| D3 | Who initiated the guardianship | **One additive migration: `guardianships.initiated_by` (`minor: 0`, `guardian: 1`).** `Guardianship#self_signed_signals` skips `accepted_suspiciously_fast?` when guardian-initiated; `accept!` gains `notify_minor:` so the "accepted your invitation" mail goes only to a teen who actually invited. | Design 3. Verified: `generate_invite_token` stamps `invite_sent_at` on every create, so every parent-first row would otherwise land on the payout reviewer's self-signed list (`FAST_ACCEPTANCE = 2.minutes`). All three judges asked for this. Migrations are permitted when additive. |
| D4 | Parent screens | **3: `teen` → `sign` → `done`.** The welcome bullets live in the `teen` step's info pane; the parent's name is asked on `sign` only when `current_user.full_name.blank?`. | Design 3. Design 2's zero-field `welcome` and Design 1's standalone name step were both flagged as an extra click. |
| D5 | Teen screens | **5: `you` → `business` → `name` → `family` → `done`.** | Design 1's split of "pick" and "describe", because the grafted 14-card `.wizard-option` grid plus two text fields is too long for one phone screen. Design 2's `review` step is folded into `family` (summary with Edit links in the info pane; blockers listed on 422). A dedicated `done` screen (Designs 1/3) beats landing on the venture page (judge 2: weaker demo beat). |
| D6 | When the draft `Event::Application` is created | **On the `business` POST**, never on GET. | Design 1. Gives the home "Continue your application" card and `start` something to resume; Design 3's create-on-GET is a GET with side effects; Design 2's session-only teen state lost everything on a cleared cookie. |
| D7 | Who persists the application | **The wizard controller, through the same model interfaces** (`assign_attributes` + `save!`, `derive_business_category` runs in `before_validation`, `mark_submitted!`, `Fuime::FounderAdmission`). It does **not** post to `Event::ApplicationsController#update`. | Designs 1/2. Design 3's reuse would 500 on a crafted `service_type` (`save!`) and leak the old wizard's pages on `redirect_back`. Nothing in `Event::ApplicationsController` is moved or edited; the four-line cohort lookup is re-expressed in a tiny **NEW** `Fuime::CohortStamp` module and the old controller keeps its private copy (judge 3: Design 1's "moved verbatim" was not verbatim). |
| D8 | Login routing | **`ApplicationController#redirect_to_onboarding`, `LoginsController#complete` (name-blank branch) and `WaitlistInvitesController` all send name-less users to `/setup`** — one front door. Path intent (parent vs teen) travels on `Login#return_to`, which is a DB row, not the session. | Designs 1/2 for the single front door; Design 3's `purpose: "onboarding"` is unnecessary because `Login.state.return_to` already carries `/setup/parent` on the row. Consequence: `GuardianshipsController#show/#accept` must skip `redirect_to_onboarding` and the accept page must collect a missing name (the half of C1 that is forced by this change; the `?k=` signed sign-in token in the guardian invite is **not** in this PR). |
| D9 | Layout | **NEW `app/views/layouts/fuime_setup.html.erb`**, cloned from `fuime_product`. `fuime_product` and `apply` are untouched. | Designs 1/2. Verified `application.html.erb:85,112` renders `application/footer` only `unless @no_app_shell`, so the disclosure must be rendered by the new layout via a **NEW `application/_status_disclosure` partial** extracted byte-for-byte from `_footer` (Design 3). |
| D10 | Pre-login chooser at `/onboarding` | **Rejected.** `/get-started` keeps pointing at `/users/auth?signup=true` (Phase A). The three-way fork copy is placed as two small links on the teen `you` screen instead. | Design 3's chooser added a screen before the login code; judges 1 and 2 flagged it. |
| D11 | Join-link lifetime | **7 days** (`signed_id`, purpose `:family_join`, minted inside the mailer, never stored, never rendered). | Designs 2/3; Design 1's 14 days was twice the waitlist pattern's exposure. |
| D12 | Progress-bar animation state | **`sessionStorage`** on the client (previous progress); direction derived from the delta. No `last_progress` in the server session, no `?dir=back`. | Design 3's mechanism with Design 1's direction awareness. |
| D13 | Playground | **Fixed personas that reset**: existing Sam (`playground+new@fuime.test`) plus **NEW** Priya (`playground+priya@fuime.test`) and her stub kid (`playground+kid@fuime.test`); one ActionMailer interceptor drops mail to any persona; personas may only type `@fuime.test` addresses for a teen/parent. | Design 1's reset model (extends the existing `reset_new_founder!`), Design 2's address guard. Design 2's new-user-per-click was rejected (rows accumulate). Interceptor rather than per-mailer conditionals (judge 3). |
| D14 | Quiet hours (L7) | **NEW `Fuime::MinorMailWindow`** applied as `deliver_later(wait_until:)` to the one new minor-addressed mail (`teen_join`). Pre-existing minor mail (`Event::ApplicationReminderJob`, `GuardianshipMailer#accepted`) is unchanged and logged as a known gap. | Designs 1/2. |
| D15 | Approval ETA sentence | **Absent** until the founder picks a true number (ONBOARDING_PLAN §6 #4). | All three. |
| D16 | Stub teen | `User.create!(email:, creation_method: :family_invite)` (additive enum value `9`), `preferred_name` = the first name the parent typed, `full_name` blank so `onboarding?` stays true. The `you` step greets by `preferred_name` and does **not** prefill the full-name field (a one-word prefill would fail the two-word format validation). | Design 2. |

---

## 1. Screens at a glance

| | Teen-first | Parent-first |
|---|---|---|
| Screens after the login code | **5** — `you` · `business` · `name` · `family` · `done` | **3** — `teen` · `sign` · `done` |
| Fields | full name · 13+ · starting point · service · business name · description · country · parent email (optional event code) = 8 | teen first name · teen email · teen-is-13+ · (your name, only if blank) · agree = 4–5 |
| Emails to open | 1 (login code) | 1 (login code); the teen later opens 1 (join link, signs them in) |
| Human gates before the founder is inside the venture | 0 (`Fuime::FounderAdmission` on submit) | — |
| Persisted at | `you` (User) · `business` (draft Application) · `name` · `family` (submit → Event) | `sign` only (name if blank, stub teen, Guardianship active, consent, join mail) |
| Progress values | 20 · 40 · 60 · 80 · 100 | 33 · 66 · 100 |
| Rail labels | You · What you do · Name it · Family · Done | Your teen · Sign · Done |
| Converges on | the same venture page | the teen's five screens, one field fewer (`family` shows "{Parent} already signed") |

---

## 2. Routes (`config/routes.rb`)

Declare immediately after `get "waitlist_invites/:token"` (line 82) — i.e. before `/learn` and every `/:event_slug/…` route (first at ~line 150) and before `resources :events, path: "/"` (line 1299) — so `setup` and `join` are never read as venture slugs.

```ruby
# Fuime: the family setup wizard (docs/fuime/ONBOARDING_PLAN.md §4, §5 E1; C1 partly).
# Both paths, one controller. The teen's last form step is `family`, not `parent`, so
# /setup/parent can never be swallowed by the teen :step segment.
get  "setup",              to: "fuime/onboarding#start",       as: :setup
get  "setup/parent",       to: "fuime/onboarding#start",       as: :parent_setup, defaults: { path: "parent" }
get  "setup/parent/:step", to: "fuime/onboarding#parent",      as: :parent_setup_step, constraints: { step: /teen|sign|done/ }
post "setup/parent/:step", to: "fuime/onboarding#parent_save", as: :parent_setup_save, constraints: { step: /teen|sign/ }
get  "setup/:step",        to: "fuime/onboarding#teen",        as: :teen_setup_step,   constraints: { step: /you|business|name|family|done/ }
post "setup/:step",        to: "fuime/onboarding#teen_save",   as: :teen_setup_save,   constraints: { step: /you|business|name|family/ }
# The parent-first teen's emailed sign-in link. Token-addressed, no session — same
# shape as waitlist_invites/:token.
get  "join/:token",        to: "fuime/family_invites#show",    as: :family_invite
```

Inside the existing `resources :guardianships … member do` block (line 69): add `post :resend_join` (id-addressed, authenticated — the parent re-mails the teen's join link).

Inside the admin `playground` block (line 547): add `post "playground/fresh_parent", to: "admin/playground#fresh_parent", as: "playground_fresh_parent"`.

`config/initializers/friendly_id.rb` `config.reserved_words`: add `setup` and `join` (verified list exists at line 22).

Existing routes the wizard links to (all verified): `auth_users_path`, `logout_users_path` (DELETE), `choose_login_preference_login_path(login)`, `new_application_path`, `start_applications_path`, `application_path`, `apply_path`, `new_guardianship_path`, `guardianships_path`, `guardianship_path(token)`, `record_guardianship_path`, `revoke_guardianship_path`, `event_path`, `new_fuime_offer_path(event_slug:)`, `learn_path(anchor:)`, `learn_template_path(slug:)`, `terms_path`, `privacy_path`, `guardian_agreement_path`, `impersonate_user_path`, `playground_admin_index_path`, `playground_fresh_founder_admin_index_path`, `root_path`.

---

## 3. Controller — `Fuime::OnboardingController` (**NEW**, `app/controllers/fuime/onboarding_controller.rb`)

```ruby
module Fuime
  class OnboardingController < ApplicationController
    layout "fuime_setup"
    skip_before_action :redirect_to_onboarding          # a name-less user is exactly who is here
    # signed_in_user stays ON (inherited): every action below needs a session.

    TEEN_STEPS   = %w[you business name family done].freeze
    PARENT_STEPS = %w[teen sign done].freeze
    TEEN_LABELS   = { "you" => "You", "business" => "What you do", "name" => "Name it", "family" => "Family", "done" => "Done" }.freeze
    PARENT_LABELS = { "teen" => "Your teen", "sign" => "Sign", "done" => "Done" }.freeze
    JOIN_RESEND_COOLDOWN = 10.minutes

    helper_method :wizard_path, :wizard_steps, :wizard_step, :wizard_step_index, :wizard_progress, :wizard_labels
```

**Add to `Fuime::GuardianshipEnforcement::ALLOWED_CONTROLLER_PATHS`** (exact entries): `"fuime/onboarding"`, `"fuime/family_invites"`. Under MoR the filter returns early on `permitted_to_operate_business?`; the entries matter under Connect and keep a parked teen able to reach the wizard.

**Authorization** (`verify_authorized` is an inherited after_action): `start`, `teen` (GET), `parent` (GET) call `skip_authorization`. `teen_save` step `you` → `authorize current_user, :update?` (`UserPolicy#update?` is `user.admin? || record == user`, verified). Steps `business`/`name`/`family` → `authorize @application, :create?` when new, else `:update?` (`Event::ApplicationPolicy`, verified: `create?` is `record.user == user`; `update?` is owner-while-draft). `parent_save` → `authorize Guardianship, :create_as_guardian?` (**NEW** policy method, §6.4).

### 3.1 Session state

```ruby
session[:teen_setup]   = { "application_id" => Integer,                                  # written at business
                           "done" => { "application_id" => Integer, "invite_error" => String|nil } }  # written at family, cleared after done renders
session[:parent_setup] = { "teen" => { "first_name" => String, "email" => String },        # written at teen (session only)
                           "guardianship_id" => Integer, "join_sent_at" => ISO8601 }      # written at sign, cleared after done renders
session[:family_join_sent] = { "<guardianship_id>" => ISO8601 }                          # resend_join cooldown
```

Helpers `teen_state`, `write_teen_state(attrs)`, `clear_teen_state`, `parent_state`, `write_parent_state(attrs)`, `clear_parent_state` — same shape as `Fuime::OffersController#wizard_state` / `write_wizard_state` / `clear_wizard_state` (stringified keys, merge on write). Nothing legally significant lives only in the session: every consent and attestation is written to its record the moment it is given.

### 3.2 Actions

| Action | Route | Behaviour |
|---|---|---|
| `start` | `GET /setup`, `GET /setup/parent` | Dispatcher (§3.3). Renders nothing. |
| `teen` | `GET /setup/:step` | `@step = params[:step]`; per-step guard + loader (§4); `render "fuime/onboarding/teen/#{@step}"`. |
| `teen_save` | `POST /setup/:step` | `case @step` → `save_you`, `save_business`, `save_name`, `save_family` (§4). |
| `parent` | `GET /setup/parent/:step` | guard: `redirect_to new_guardianship_path, alert: "This account is set up as a founder. To add a parent or guardian, invite them from here."` if `current_user.guardianships_as_minor.exists?`; loader (§5); render `fuime/onboarding/parent/#{@step}`. |
| `parent_save` | `POST /setup/parent/:step` | `save_teen`, `save_sign` (§5). |

Every 422 re-render sets `flash.now[:alert]` and renders the same step (`status: :unprocessable_entity`).

### 3.3 `start` — the dispatcher, in order

```ruby
def start
  skip_authorization
  return_to = url_from(params[:return_to])
  # 1. Parent path, chosen by URL or by the Login row's return_to (DB-backed, not session).
  if params[:path] == "parent" || return_to.to_s.start_with?("/setup/parent")
    return redirect_to parent_setup_step_path(parent_state["guardianship_id"].present? ? "done" : "teen")
  end
  # 2. A parent following a teen's invite (bare /guardian/:token then a code): the accept page collects the name now.
  return redirect_to return_to if return_to.to_s.start_with?("/guardian/")
  if current_user.onboarding? && current_user.guardianships_as_minor.none? &&
     (pending = current_user.guardianships_as_guardian.pending.order(:created_at).last)
    return redirect_to guardianship_path(pending.invite_token)
  end
  # 3. Name-less: the teen 'you' step (also the parent-first teen arriving from /join).
  return redirect_to teen_setup_step_path("you", return_to: return_to.presence) if current_user.onboarding?
  # 4. A finished parent with nothing to set up.
  if current_user.guardian_of_active_ward? && current_user.events.none? && current_user.applications.not_archived.none?
    return redirect_to guardianships_path
  end
  # 5. Resume a teen draft at its first incomplete step (old-wizard drafts included).
  draft = current_user.applications.not_archived.draft.order(:id).last
  if draft&.teen_led?
    write_teen_state("application_id" => draft.id)
    step = draft.service_type.blank? ? "business" : (draft.name.blank? || draft.description.blank?) ? "name" : "family"
    return redirect_to teen_setup_step_path(step)
  end
  return redirect_to application_path(draft) if draft                                     # adult draft → old status page
  return redirect_to root_path if current_user.events.any? || current_user.applications.not_archived.any?
  # 6. Known adults never get a teen-led application from this wizard.
  return redirect_to new_application_path, flash: { info: "You're signed in as an adult — the standard application is for you." } if current_user.known_adult?
  redirect_to teen_setup_step_path("business")                                             # named, no venture, no draft
end
```

---

## 4. Teen path — five screens

Entry: fuime.com "Start your business" → `/get-started` (307, unchanged) → `/users/auth?signup=true` (title "Start your business on Fuime" and the shipped MoR sub-line, unchanged) → code page → `LoginsController#complete` → `setup_path(return_to: @login.return_to)` (§8) → `start` → `/setup/you`.

`wizard_subtitle` on every teen screen: **Start your business**.

### 4.1 `you` — `GET /setup/you` — title "What should we call you?"

Loader: `@user = current_user`; `@attested = @user.age_attestation.present? || @user.birthday.present?`; `@guardian = @user.active_guardian` (non-nil only for a parent-first teen); `@return_to = url_from(params[:return_to])`. **Auto-skip**: if `@user.full_name.present? && @attested` → `redirect_to teen_setup_step_path("business")` (returning users).

Info pane (`content_for :info_pane`):
> **Fuime is a financial platform for young founders.** List what you sell, get paid, keep it all in one place. Your name and one checkbox — under a minute.

Above the form, only when `@guardian`: a `.card` — "**{@guardian.name} already signed as your parent or guardian.** They set this up for you — finish your part and you're in." Plus the muted line "Not you? `Sign out`" (`button_to logout_users_path, method: :delete, class: "link"`). When `@user.preferred_name.present?` the H1 reads "Hi {preferred_name} — what's your full name?" instead.

Form `form_with url: teen_setup_save_path("you"), method: :post, id: "setup_form", scope: :user` (an ordinary Turbo form):
- `user[full_name]` — label **Full name**; `required`, `pattern: '^\S+.+'`, `autocomplete: "name"`, placeholder "Maya Okafor", autofocus; prefilled with `@user.full_name` only. Model errors for `:full_name` rendered under the field.
- Age: if `@attested` → read-only line: `@guardian ? "You're set up as a founder under 18 — {@guardian.name} is your parent or guardian on Fuime." : "You've confirmed you're 13 or older."` Otherwise `.field.field--checkbox`: `user[age_attestation_confirmed]` value `"1"`, id `user_age_attestation_confirmed`, `required` — label **I'm 13 or older**. Helper (`p.h5.muted`): "Fuime is for founders 13 and up. Under 18, a parent or guardian signs off before you get paid — not before you start."
- Hidden `return_to` when `@return_to`.
- Terms paragraph, **byte-for-byte the MoR branch of `users/edit.html.erb` lines 74–87**: "By continuing you agree to Fuime's Terms of Service and Privacy Policy. If you're under 18, a parent or guardian also accepts the Guardian Agreement before you can get paid." (links to `terms_path`, `privacy_path`, `guardian_agreement_path`, `target: "_blank"`).

Footer: no Back. Primary `.btn.btn--fuime` **Let's go** (`form: "setup_form"`). Under the form, two `text-sm muted` links: "18 or older and running this yourself? **Use the standard application**" → `new_application_path`; "Parent or guardian? **Set up your family instead**" → `parent_setup_path`.

`save_you` — the same three calls `UsersController#update` makes, nothing else:
```ruby
@user = current_user
authorize @user, :update?
@user.assign_attributes(full_name: params.dig(:user, :full_name).to_s.strip)      # only full_name; never age_attestation
if ActiveModel::Type::Boolean.new.cast(params.dig(:user, :age_attestation_confirmed))
  @user.attest_minor_13_plus(ip: request.remote_ip, user_agent: request.user_agent)   # assigns; one save below
end
if @user.save(context: :onboarding)              # runs age_attestation_required_for_onboarding + write-once guard
  return_to = url_from(params[:return_to])
  redirect_to (return_to.present? && !return_to.start_with?("/setup")) ? return_to : teen_setup_step_path("business")
else
  flash.now[:alert] = @user.errors.full_messages.to_sentence
  render "fuime/onboarding/teen/you", status: :unprocessable_entity
end
```
The L6 refusal is the model's own (`age_attestation_required_for_onboarding`); the view adds one sentence under the unticked box in the error state: "Fuime is for founders 13 and up." No date of birth is asked anywhere; `adult_18_plus` cannot be produced here.

### 4.2 `business` — `GET /setup/business` — title "What do you do?"

Loader: `@application = teen_application` (nil on first visit); `@starting_points = Fuime::ServiceCatalog::STARTING_POINTS`; `@services = Fuime::ServiceCatalog.sellable`; `@selected_point = @application&.starting_point || "have_idea"`; `@selected_service = @application&.service_type`.

`teen_application` = `current_user.applications.not_archived.draft.find_by(id: teen_state["application_id"])` falling back to `current_user.applications.not_archived.draft.where(teen_led: true).order(:id).last`.

Info pane: `.card` **What you can sell today** — "Services — work you do for someone — and digital things you make, like a design, an edit, or a small piece of software. Physical products and food are coming later." (verbatim from `business_type.html.erb`). Then: "Not sure yet? **Browse the starter templates**" → `learn_path(anchor: "templates")`, `target: "_blank" rel: "noopener"`.

Form `POST /setup/business`, `scope: :setup`:
- `setup[starting_point]` — label **Where are you starting from?** — `.wizard-segment` pill group of the three `STARTING_POINTS` (`point.name`: "I already run this" / "I have an idea" / "Start from a template"), radios `sr-only`, `required`, default checked `@selected_point`. Helper: "There's no wrong answer — it just changes what we show you next."
- `setup[service_type]` — label **Pick the closest one** — `.wizard-option-grid` of 14 `.wizard-option` labels (radio `sr-only` + `<strong>{s.name}</strong><small class="muted">{s.blurb}</small>`), `required`. Helper: "You'll describe it in your own words on the next screen."

Footer: Back → `teen_setup_step_path("you")` (`.btn.bg-muted`, `data-action="click->wizard#leaveBack"`). Primary **Continue**.

`save_business`:
```ruby
point   = params.dig(:setup, :starting_point).to_s
service = params.dig(:setup, :service_type).to_s
unless Fuime::ServiceCatalog::STARTING_POINT_KEYS.include?(point) && Fuime::ServiceCatalog.sellable.map(&:key).include?(service)
  flash.now[:alert] = "Pick the closest one."; return render(..., status: :unprocessable_entity)
end
@application = teen_application || Event::Application.new(user: current_user, teen_led: true)
@application.assign_attributes(starting_point: point, service_type: service)      # business_category derived in before_validation
@application.fuime_cohort ||= Fuime::CohortStamp.from_waitlist(session:, user: current_user) if @application.new_record?
authorize @application, @application.new_record? ? :create? : :update?
@application.save!
write_teen_state("application_id" => @application.id)
redirect_to teen_setup_step_path("name")
```
`teen_led` is always `true` here (adults left at `you`). Creating the draft enqueues the existing `Event::ApplicationReminderJob` set (`after_create_commit`), exactly as the old wizard's `create` does — pre-existing, logged in the divergence file as an L7 gap, not solved here.

**NEW `app/lib/fuime/cohort_stamp.rb`** — `Fuime::CohortStamp.from_waitlist(session:, user:)`: reads `session[:waitlist_cohort]` when `stored["uid"].to_i == user.id` (and deletes it), else `Fuime::WaitlistRoster.invite_stamp(user.email)&.cohort_code`; returns `Fuime::Cohort.for_code(code)` if `&.admitting?`, else nil. `Fuime::CohortStamp.from_code(typed)` → `[cohort_or_nil, :unknown|:blank|:ok]`. The old controller's private `apply_waitlist_cohort_stamp` / `assign_cohort_from_code` are left exactly as they are.

### 4.3 `name` — `GET /setup/name` — title "Name it"

Guard: `@application = teen_application` or `redirect_to teen_setup_step_path("business")`. `@template = @application.service if @application.started_from_template?`.

Info pane: "Your own words. Customers read this on your storefront, so say what you do and for whom." When `@template`: the outline card **verbatim from `project_info.html.erb` lines 43–54** — "**Your {template.name.downcase} outline** — Things worth settling before your first customer. Nothing here is set by Fuime — including what you charge, which is always yours to decide." + `@template.checklist` bullets.

Form `POST /setup/name`, `scope: :setup`:
- `setup[name]` — **Business name**; `required`, `maxlength: 255`, placeholder "Maya's Lawn Care", value `@application.name`.
- `setup[description]` — **What do you do?**; `textarea rows: 4`, `required`, placeholder `@template&.description_prompt || "I mow lawns and trim hedges on weekends in Oakland…"`, value `@application.description`. Helper: "One or two sentences. You can change it later."

Footer: Back → `business`. Primary **Continue**.

`save_name`: `authorize @application, :update?`; blank name → 422 "Give it a name."; blank description → 422 "Say what you do — one sentence is enough."; `@application.update!(name:, description:)`; redirect `family`. Placeholders are never written as values.

### 4.4 `family` — `GET /setup/family` — title `@needs_parent ? "Your parent or guardian" : "Almost done"`

Guard: no `@application` → `business`; `name.blank? || description.blank?` → `name`. Loader: `@needs_parent = current_user.needs_guardian? && !current_user.institutionally_vouched_for?` (the exact predicate `required_submission_fields` uses, so the screen and the blocker can never disagree); `@guardian = current_user.active_guardian`; `@pending = current_user.guardianships_as_minor.pending.order(:created_at).last`; `@cohort = @application.fuime_cohort`; `@service = @application.service`.

Info pane, in order:
1. Summary `.card` — rows "**{@service.name}** · {starting point name}" (Edit → `business`), "**{@application.name}**" (Edit → `name`), "{@application.description}" (Edit → `name`).
2. Family sentence: `@needs_parent` → "**They don't have to do anything today.** We email them one page to sign. You can keep setting up, and sell as soon as Fuime approves your business. Nothing is paid out until they've signed." · `@guardian` → "**{@guardian.name} already signed** as your parent or guardian. Nothing else to add." · `@pending` → "**We've already emailed {@pending.guardian.redacted_email}.** You can change the address here."
3. On 422 only: `application/_callout` type `warning`, title "Still needed", listing `@blockers`.

Form `POST /setup/family`, `scope: :setup`, `x-data` with `disallowed_countries` and `country` (lifted from `personal_info.html.erb:23,91-99`):
- `setup[address_country]` — **Country** — `country_select` with `priority_countries: ["US"], priority_countries_divider: "", include_blank: "Select a country", required: true`, `x-model: "country"`, `x-on:change` / `x-init` setting custom validity `"Fuime is not supported in this country"` when in `Event::Application::DISALLOWED_COUNTRIES`; the explanatory `p.primary` sentence from `personal_info.html.erb:99`.
- If `@needs_parent`: `setup[cosigner_email]` — **Parent or guardian's email** — `type: email`, `required`, `autocomplete: "off"`, placeholder "parent@example.com", value `@application.cosigner_email || @pending&.guardian&.email`; `x-on:input` custom validity `"You cannot use your own email"` when equal to `current_user.email` (as `personal_info.html.erb:110`). Helper: "We'll send them one email with a one-page agreement — no Social Security number, no ID, no payment."
- `<details class="mt-4">` summary **Have an event code?** → `setup[cohort_code]` (`maxlength: Fuime::Cohort::MAX_CODE_LENGTH`, `autocapitalize: "characters"`, `autocomplete: "off"`, placeholder "FOUNDERS26", value `@cohort&.code`). Helper verbatim from `review.html.erb`: "If you're at an event that gave you a code, enter it here and your business gets set up right away." When `@cohort`: `p.success` "✓ You're in {@cohort.name}."; when `flash[:cohort_code_unknown]`: `p.error` "We didn't recognise that code. Check it with whoever gave it to you — you can still submit without one."

Footer: Back → `name`. Primary **Finish setup**.

`save_family`:
```ruby
authorize @application, :update?
email = params.dig(:setup, :cosigner_email).to_s.strip.downcase.presence
if Fuime::Playground.persona?(current_user.email) && email && !email.end_with?("@fuime.test")
  flash.now[:alert] = "Playground personas can only invite @fuime.test addresses."; return render 422
end
@application.assign_attributes(address_country: params.dig(:setup, :address_country).to_s.presence,
                               cosigner_email: (@needs_parent ? email : @application.cosigner_email))
if params[:setup]&.key?(:cohort_code)
  cohort, outcome = Fuime::CohortStamp.from_code(params[:setup][:cohort_code])
  @application.fuime_cohort = cohort if outcome != :unknown          # blank clears, unknown leaves as-is (old-wizard semantics)
  flash.now[:cohort_code_unknown] = true if outcome == :unknown
end
@application.save!
@blockers = @application.submission_blockers
return render("fuime/onboarding/teen/family", status: :unprocessable_entity) if @blockers.any?
@application.mark_submitted!                       # after-hook: GuardianInviteService (best-effort), contract/under_review, CohortAdmission, admission flag
::Fuime::FounderAdmission.new(application: @application.reload).call   # the same explicit second call #submit makes
invite_error = @application.guardian_invite_error  # attr_accessor — read on THIS instance before the reload below
@application.reload
if @application.event.present?
  confetti!
  write_teen_state("done" => { "application_id" => @application.id, "invite_error" => invite_error })
  redirect_to teen_setup_step_path("done")
else
  clear_teen_state
  redirect_to application_path(@application), flash: { error: "Your business is submitted — #{@application.activation_blockers.first.presence || "we couldn't finish setting it up"}." }
end
rescue AASM::InvalidTransition
  @blockers = @application.submission_blockers; flash.now[:alert] = "Something's missing — see the list."; render 422
```
Nothing here vets: `FounderAdmission` approves and activates and never calls `vet!`; the venture is `operator_vetting_status: unvetted` and `Event#offer_publish_blockers` refuses publishing until a human approves.

### 4.5 `done` — `GET /setup/done` — title "You're in."

Guard: `teen_state["done"]` absent → `redirect_to setup_path`. Loader: `@application = current_user.applications.find(teen_state.dig("done", "application_id"))`; `@event = @application.event` (nil → `redirect_to application_path(@application)`); `@progress = Fuime::FounderProgress.new(application: @application)`; `@invite_error = teen_state.dig("done", "invite_error")`; `@guardian = current_user.active_guardian`; `@cohort_vetted = @application.fuime_cohort.present? && @event.operator_vetting_approved?`. `clear_teen_state` after assigning (a refresh goes `/setup` → `start` → `root_path`).

Body (`.wizard-stagger`, each child `style="--i: n"`):
- H1 **You're in.** Sub: "**{@event.name}** is set up. A person at Fuime checks every new business before anything goes on sale — we'll email you when it's approved. Set everything up now and publish the moment we say yes."
- Rail: all five done (the last check draws).
- **What's next** `.card` list: ✓ **Your account** · ✓ **{@event.name}** created · ○ **Fuime reviews your business** — "By a person, before anything can be sold. We'll email you." · ○ **Add something to sell** — "Name it and set your own price." · ○ **Share your link**.
- Family line (exactly one): `@guardian` → "✓ {@guardian.name} signed as your parent or guardian." · `@application.cosigner_email.present? && @invite_error.nil?` → "We emailed **{cosigner_email}** a one-page agreement to sign. Nothing is paid out until they have." · `@invite_error` → error-styled "We couldn't invite {cosigner_email}: {@invite_error}. **Invite them from your account.**" → `new_guardianship_path` · `@cohort_vetted` → "✓ You're in {@application.fuime_cohort.name}: your business is approved to sell."
- Footer: secondary **Go to {@event.name}** → `event_path(@event)`; primary **Add something to sell** → `new_fuime_offer_path(event_slug: @event.slug)`.

Confetti: `confetti!` set in `save_family` renders through `layouts/_body_suffix` (verified `application.html.erb:116` renders it regardless of `no_app_shell`).

---

## 5. Parent path — three screens

Entry: fuime.com `/parents` CTA **Set up your family** → `/family` (**NEW** redirect in `site/server.js`: `['/family', \`${APP_ORIGIN}/users/auth?signup=true&return_to=%2Fsetup%2Fparent\`]`; the existing "Have your teen start" link stays; note `/parents` is currently in `CLOSED` — §6 #6 — so this is a one-line prep, not a launch). `LoginsController#new` (§8) renders the parent variant of the signup page. Code page unchanged. `#complete` → `setup_path(return_to: "/setup/parent")` → `start` → `/setup/parent/teen`.

`wizard_subtitle`: **Set up your family on Fuime**. The `parent` GET guard (§3.2) refuses any account that is the minor of a guardianship.

### 5.1 `teen` — `GET /setup/parent/teen` — title "Who's the founder?"

Loader: `@teen = parent_state["teen"] || {}`.

Info pane:
> **What you're setting up**
> • **You're the legal signer.** Your teen runs the business day to day; you're the responsible adult and the owner of record of its account on Fuime.
> • **You can see every sale and every dollar, always.** Your teen can't turn that off.
> • **Nothing is paid out until you've set up where the money goes.** A person at Fuime reviews every new business before it can sell.
>
> **What happens next** *(about three minutes)* — 1. Their first name and email. 2. Read and sign the guardian agreement. 3. We email them a link; they add their name, confirm they're 13 or older, and describe their business.
>
> We won't ask for a Social Security number, an ID, or a payment. When there's money to send, we'll ask where it should go.

Form `POST /setup/parent/teen`, `scope: :setup`:
- `setup[teen_first_name]` — **Their first name** — `required`, `maxlength: 30`, placeholder "Maya". Helper: "This is how we'll refer to them in the agreement. They add their full name themselves."
- `setup[teen_email]` — **Their email** — `type: email`, `required`, `autocomplete: "off"`, placeholder "maya@example.com"; `x-on:input` custom validity "Use your teen's email, not your own" when equal to `current_user.email`. Helper: "The address they'll sign in with. One email goes there."
- `.field.field--checkbox` `setup[teen_13_plus]` value `"1"`, `required` — **{first name or "They"} is 13 or older**. Helper: "Fuime is for founders 13 and up."

Footer: primary **Continue**. Under the form: "Not a parent or guardian? **Start as a founder**" → `setup_path`.

`save_teen` (session only — nothing is created for a mistyped address before the parent has signed):
- first name present, ≤ 30, matches `User`'s `preferred_name` format → else 422 "Tell us their first name."
- email present, valid (`ValidatesEmailFormatOf::validate_email_format`), `!= current_user.email` → else 422 "Use your teen's email, not your own."
- `teen_13_plus == "1"` → else 422 **"Fuime is for founders 13 and up."** (the L6 refusal on the parent side, before anything is signed; never persisted).
- `User.find_by(email:)&.known_adult?` → 422 "That address belongs to an account that's confirmed 18 or older, so it doesn't need a guardian. Use your teen's own address." (reveals nothing else).
- persona guard: `Fuime::Playground.persona?(current_user.email) && !email.end_with?("@fuime.test")` → 422 "Playground personas can only add @fuime.test addresses."
- `write_parent_state("teen" => { "first_name" => …, "email" => … })`; redirect `sign`.

### 5.2 `sign` — `GET /setup/parent/sign` — title "{Teen} needs a parent to sign off"

Guard: `parent_state["teen"]` absent → `teen`. Loader: `@teen_name = parent_state.dig("teen", "first_name")`; `@existing = User.find_by(email: parent_state.dig("teen", "email"))`; `@guardianship = Guardianship.find_by(guardian: current_user, minor: @existing) if @existing`; already `active?` → `write_parent_state("guardianship_id" => id)`; redirect `done`. `@minor_preview = @existing || User.new(email:, preferred_name: @teen_name)` (unsaved; only for rendering); `@agreement_partial = Guardianship.agreement_partial_for(Guardianship::CURRENT_AGREEMENT_VERSION)` (verified: v4 reads only `minor.name`, `minor.email` and `guardian` locals); `@needs_name = current_user.full_name.blank?`; `@structural_blockers = (@guardianship || Guardianship.new(guardian: current_user, minor: @minor_preview)).structural_activation_blockers`.

Info pane — the three MoR bullets **verbatim from `guardianships/show.html.erb`**, with "their business" for the venture: "• You'll be the legal signer and responsible adult for their business. {Teen} runs it day to day. • You can see every transaction, always. {Teen} can't turn that off. • Nothing is paid out until you've accepted and set up where the money goes. Money only ever goes to a destination a parent or guardian set up."

Body — form `form_with url: parent_setup_save_path("sign"), method: :post, data: { turbo: false }, id: "setup_form"` (same as the accept form):
- When `@needs_name`: `setup[parent_full_name]` — **Your full name** — `required`, `pattern: '^\S+.+'`, `autocomplete: "name"`. Helper: "As it should appear on the agreement."
- `render "guardianships/agreement_box", partial: @agreement_partial, minor: @minor_preview, guardian: current_user, minor_label: @teen_name` — **NEW shared partial `app/views/guardianships/_agreement_box.html.erb`**, extracted byte-for-byte from `show.html.erb` lines 96–124 (the "Guardian agreement" `h2`, the `max-height: 24rem` scroll box, the `agree` checkbox with `id: "agree"`, and the consent label). `show.html.erb` is changed to render the partial; the checkbox label bytes and every `guardianships/agreements/*` partial are unchanged. Label, exact: "I confirm I am the parent or legal guardian of **{minor_label}**, that I am 18 or older, and I agree to the guardian agreement above."
- Under the button (verbatim from `show`): "We'll record the date, your IP address, and the version of the agreement you signed. This is not an identity check. You can withdraw your consent at any time."
- When `@structural_blockers.any?`: the `application/_callout` from `show` instead of the checkbox.

Footer: Back → `teen`. Primary **I agree** (`.btn.bg-success`, `id: "guardian-accept-submit"`). The standing disclosure renders in the layout footer (§9).

`save_sign` — the one transaction of the parent path (same sequence as `GuardianshipsController#accept`, with creation first):
```ruby
authorize Guardianship, :create_as_guardian?
return render_sign_422("Please confirm you agree to the guardian agreement.") unless ActiveModel::Type::Boolean.new.cast(params[:agree])
teen_email = parent_state.dig("teen", "email"); first_name = parent_state.dig("teen", "first_name")
return redirect_to parent_setup_step_path("teen") if teen_email.blank?
existing = User.find_by(email: teen_email)
return render_sign_422("That address belongs to an account that's confirmed 18 or older…") if existing&.known_adult?
return render_sign_422("You withdrew consent for this founder before. Email support@fuime.com to restore it.") if existing && Guardianship.revoked.exists?(guardian: current_user, minor: existing)

failure = nil; guardianship = nil
ActiveRecord::Base.transaction do
  if current_user.full_name.blank?
    current_user.update!(full_name: params.dig(:setup, :parent_full_name).to_s.strip)   # plain save — NOT context: :onboarding, which would demand a 13+ tick from an adult
  end
  teen = existing || User.create!(email: teen_email, creation_method: :family_invite)
  teen.update!(preferred_name: first_name.first(30)) if teen.onboarding? && teen.preferred_name.blank?
  guardianship = Guardianship.find_by(guardian: current_user, minor: teen) ||
                 Guardianship.create!(guardian: current_user, minor: teen, initiated_by: :guardian)   # a teen-first pending row is reused as-is (initiated_by minor)
  unless guardianship.active?
    guardianship.guardian.attest_adult_18_plus!(ip: request.remote_ip, user_agent: request.user_agent)  # through guardianship.guardian, same instance #activation_blockers reads (update_columns) — the ONLY path to adult_18_plus
    blockers = guardianship.activation_blockers
    if blockers.any? then failure = blockers.to_sentence; raise ActiveRecord::Rollback end
    ok = guardianship.accept!(consent_ip: request.remote_ip, consent_user_agent: request.user_agent,
                              notify_minor: guardianship.initiated_by_minor?)          # "accepted your invitation" only when there was one
    unless ok then failure = "Failed to record your consent."; raise ActiveRecord::Rollback end
  end
end
return render_sign_422(failure) if failure
unless guardianship.initiated_by_minor?
  Fuime::FamilyMailer.teen_join(guardianship:).deliver_later(wait_until: Fuime::MinorMailWindow.earliest_send_time)
end
write_parent_state("guardianship_id" => guardianship.id, "join_sent_at" => Time.current.iso8601)
confetti!
redirect_to parent_setup_step_path("done")
rescue ActiveRecord::RecordInvalid => e
  render_sign_422(e.record.errors.full_messages.to_sentence)
```
`accept!` still writes `status: active`, `agreement_signed_at`, `agreement_ip`, `agreement_user_agent`, `agreement_version = CURRENT_AGREEMENT_VERSION` (`2026-09-11-v4`, untouched), nils `invite_token`, and enqueues `Fuime::ProvisionConnectAccountJob` (verified: returns on its first line under MoR).

### 5.3 `done` — `GET /setup/parent/done` — title "You're {Teen}'s guardian on Fuime"

Guard: `parent_state["guardianship_id"]` absent → `teen`. Loader: `@guardianship = current_user.guardianships_as_guardian.active.find(id)`; `@teen = @guardianship.minor`; `@teen_joined = !@teen.onboarding?`; `@resend_cooldown = parent_state["join_sent_at"].present? && Time.iso8601(parent_state["join_sent_at"]) > JOIN_RESEND_COOLDOWN.ago`. `clear_parent_state` after assigning.

Body (`.wizard-stagger`):
- H1 **You're {@teen.name}'s guardian on Fuime.** Sub (when `!@teen_joined`): "We emailed **{@teen.redacted_email}** a link to join. It works for 7 days and signs them in on their own device. When they open it, they add their name, confirm they're 13 or older, and describe their business. You'll be able to see all of it." When `@teen_joined`: "{@teen.name} already has a Fuime account — you're now on it as their parent or guardian."
- **What happens next** `.card`: "A person at Fuime reviews every new business before anything can be sold." · "You can see every sale on your guardian page." *(never "we'll email you when they sell" — D1 has not shipped)* · "Before any money is paid out, you'll set up where it goes. We'll ask then — not now."
- Buttons: secondary **Send the link again** (`button_to resend_join_guardianship_path(@guardianship)`, `disabled: @resend_cooldown`, `.tooltipped` "Sent a few minutes ago" when disabled; hidden when `@teen_joined`); secondary **Add another teen** → `parent_setup_step_path("teen")`; primary **Go to your guardian page** → `guardianships_path`.

No family-plan copy (only a second venture needs it).

---

## 6. Data model changes — all additive

### 6.1 Migration (**NEW** `db/migrate/<timestamp>_add_initiated_by_to_guardianships.rb`)
```ruby
class AddInitiatedByToGuardianships < ActiveRecord::Migration[8.0]   # match the version the latest file in db/migrate uses
  def change
    add_column :guardianships, :initiated_by, :integer, default: 0, null: false
  end
end
```
Existing rows are minor-initiated (default `0`); no backfill. Update the schema comment block in `app/models/guardianship.rb`.

### 6.2 `app/models/guardianship.rb`
- `enum :initiated_by, { minor: 0, guardian: 1 }, prefix: :initiated_by, default: :minor`.
- `def accept!(consent_ip: nil, consent_user_agent: nil, notify_minor: true)`; `GuardianshipMailer.accepted(guardianship: self).deliver_later if notify_minor`. Default unchanged for every existing caller.
- `self_signed_signals`: the fast-acceptance line becomes `if accepted_suspiciously_fast? && !initiated_by_guardian?` (the other four signals stay; `no_independent_guardian_activity?` is still meaningful for a parent-first parent).

### 6.3 `app/models/user.rb`
- `creation_method` enum gains `family_invite: 9` (integer column, no migration — same as `demo: 8`).

### 6.4 `app/policies/guardianship_policy.rb` (additive)
```ruby
def create_as_guardian? = user.present? && user.is_minor? != true && user.guardianships_as_minor.none?   # a founder account is never a parent; unknown age may proceed — 18+ is asserted on the tick, exactly as #accept?
def resend_join?        = user.present? && record.guardian == user && record.active? && record.minor.onboarding?
```

### 6.5 `app/models/login.rb` — unchanged (see D8).

---

## 7. The teen's side of a parent-first setup

### 7.1 `Fuime::FamilyInviteService` (**NEW** `app/services/fuime/family_invite_service.rb`)
```ruby
JOIN_EXPIRES_IN = 7.days; SIGNED_ID_PURPOSE = :family_join
def self.generate_token(user:) = user.signed_id(expires_in: JOIN_EXPIRES_IN, purpose: SIGNED_ID_PURPOSE)
def self.verify_token(token)   = User.find_signed(token, purpose: SIGNED_ID_PURPOSE)     # nil for expired/tampered
```
Stateless, no column (same as `Fuime::WaitlistInviteService`).

### 7.2 `Fuime::FamilyMailer#teen_join(guardianship:)` (**NEW** `app/mailers/fuime/family_mailer.rb` + `app/views/fuime/family_mailer/teen_join.{html,text}.erb`)
`to: minor.email`, `reply_to: OPERATIONS_EMAIL`, html + text, `ApplicationMailer` conventions as `Fuime::VettingMailer`. The token is minted inside the mailer (`@join_url = family_invite_url(Fuime::FamilyInviteService.generate_token(user: @minor))`) and appears nowhere else — not in a view, flash, session or log. `@existing_account = !@minor.onboarding?`.

> Subject: **{Parent name} set up Fuime for you — finish in two minutes**
>
> Hi {minor.preferred_name.presence || "there"} —
>
> **{Parent full name}** signed as your parent or guardian on Fuime, a financial platform for young founders. That means you can set up a business and, once a person at Fuime approves it, sell what you make or do. {Parent first name} signs off before any money is paid out to you — that part's already done.
>
> *(when `!@existing_account`)* Your part: your name, one checkbox, and what your business does. About three minutes.
> *(when `@existing_account`)* You already have a Fuime account — this just adds {Parent first name} to it as your parent or guardian.
>
> **[Set up my business]** *(button, `#2242FF`, the invite mail's style; label "Open Fuime" when `@existing_account`)*
> Or paste this link into your browser: {url}
>
> The link works for 7 days and signs you in on this browser with the same email this message was sent to. After that, go to {auth_users_url} and we'll email you a login code.
>
> Not expecting this? Ignore it — nothing happens unless you open it.
>
> — the Fuime team

Transactional only, no reminders (L7); the parent resends by hand.

### 7.3 `Fuime::MinorMailWindow` (**NEW** `app/lib/fuime/minor_mail_window.rb`)
`self.earliest_send_time(now: Time.current, zone: ENV.fetch("FUIME_MAIL_TIME_ZONE", "America/Los_Angeles"))` → `now` if the local hour is 6–23, else that day's 06:00 local. The app has no `config.time_zone` (verified — runs in UTC); the env var names the family's likely zone until profiles carry one. Used for `teen_join` only.

### 7.4 `SignedLinkSignIn` (**NEW** concern `app/controllers/concerns/signed_link_sign_in.rb`)
`sign_in_from_signed_link!(user:, purpose:, return_to: nil)` — the `Login.create!(user:, state: { purpose:, return_to: })` + `cookies.signed["browser_token_#{login.hashid}"]` + `ProcessLoginService.new(login:).process_signed_email_link` + `login.reload` + `with_lock` session block, **moved verbatim from `WaitlistInvitesController#show` lines 40–58**. Returns the `Login`. `WaitlistInvitesController#show` is refactored to call it (behaviour identical; its spec changes only for the redirect target). C1 will reuse it later.

### 7.5 `Fuime::FamilyInvitesController#show` (**NEW** `app/controllers/fuime/family_invites_controller.rb`, `GET /join/:token`)
`skip_before_action :signed_in_user`, `skip_before_action :redirect_to_onboarding`, `skip_after_action :verify_authorized`.
1. `user = Fuime::FamilyInviteService.verify_token(params[:token])`; nil → `flash[:error] = "This link has expired or isn't valid. Ask your parent or guardian to send it again, or enter your email and we'll send you a login code."` → `redirect_to auth_users_path(signup: true)`.
2. `signed_in? && current_user != user` → render `fuime/family_invites/wrong_account` (**NEW** view, 403): "**This link is for a different account.** It was sent to **{user.redacted_email}**, but you're signed in as **{current_user.email}**. Sign out, then open the link again." + `button_to "Sign out and open the link again", logout_users_path, method: :delete, class: "btn bg-accent", form: { data: { turbo: false } }` (copied from `guardianships/show`). Nothing about the parent.
3. `signed_in?` → `redirect_to setup_path`.
4. else `login = sign_in_from_signed_link!(user:, purpose: "family_join", return_to: setup_path)`; `login.complete? && login.user_session.present?` → `redirect_to setup_path`, else `redirect_to choose_login_preference_login_path(login)` (2FA preserved). `rescue SessionsHelper::AccountLockedError => e` → `auth_users_path` with the message.
Then `start` → `you` (guardian card, no attestation line, greets by `preferred_name`) → `business` → `name` → `family` (country only; "{Parent} already signed…") → `done` ("✓ {Parent} signed as your parent or guardian.").

### 7.6 `GuardianshipsController#resend_join` (edit)
`@guardianship = Guardianship.find(params[:id]); authorize @guardianship, :resend_join?`; cooldown: `session[:family_join_sent][id]` within `Fuime::OnboardingController::JOIN_RESEND_COOLDOWN` → `flash[:info] = "We sent a new link a few minutes ago — check their inbox."`; else `Fuime::FamilyMailer.teen_join(guardianship:).deliver_later(wait_until: Fuime::MinorMailWindow.earliest_send_time)`, stamp the session, `flash[:success] = "Sent again to #{minor.redacted_email}."`; `redirect_back_or_to guardianships_path`. Only the parent re-mints (the one party known to be real); the teen holding a dead link is told to ask them.

### 7.7 `/guardian` ward row (`app/views/guardianships/index.html.erb` lines 40–41, 74–100)
For `guardianship.active? && minor.onboarding?`: status line "Signed {agreement_signed_at} · {minor.name} hasn't joined yet" and, when `policy(guardianship).resend_join?`, `button_to "Send the link again", resend_join_guardianship_path(guardianship), class: "btn bg-muted"`; the ventures block shows "No venture started yet." as today.

---

## 8. Existing call sites (all small, all additive)

| File | Change |
|---|---|
| `app/controllers/application_controller.rb:151` `redirect_to_onboarding` | `redirect_to setup_path(return_to: (request.get? ? request.fullpath : nil))` instead of `my_settings_path`. `users/edit`'s onboarding branch stays (Rule 2) and `spec/controllers/fuime/onboarding_terms_spec.rb` still pins it. |
| `app/controllers/logins_controller.rb:184-185` | `elsif @user.full_name.blank? && !@login.for_application?` → `redirect_to setup_path(return_to: @login.return_to)`. |
| `app/controllers/logins_controller.rb:20-28` `#new` + `app/views/logins/new.html.erb` | `@parent_signup = @signup && url_from(params[:return_to]).to_s.start_with?("/setup/parent")`. Title becomes **Set up your family on Fuime**; sub-line: "One email code, then about three minutes. You'll name your teen and sign as their parent or guardian; they finish their own part from a link we email them. We won't ask for a Social Security number, an ID, or a payment." The founder sub-line is unchanged. |
| `app/controllers/waitlist_invites_controller.rb` | body uses `SignedLinkSignIn`; `after_waitlist_login_path` → `setup_path` when `full_name.blank?`. |
| `app/controllers/guardianships_controller.rb` | `skip_before_action :redirect_to_onboarding, only: [:new, :create, :renew, :show, :accept]` (closes the half-session bounce that D8 would otherwise turn into a teen 13+ tick); `#show` sets `@needs_name = current_user.full_name.blank?`; `#accept` saves `params.dig(:guardianship, :full_name)` with a plain `update` when present and blank in the database, before `attest_adult_18_plus!`; on success `redirect_to guardianships_path` (B3's landing page is a later PR; the redirect is this one); `#resend_join` (§7.6). |
| `app/views/guardianships/show.html.erb` | renders `guardianships/_agreement_box`; when `@needs_name`, a **Your full name** field (`guardianship[full_name]`, required, `pattern '^\S+.+'`) above the box. Everything else byte-identical. |
| `app/views/application/_footer.html.erb` | the disclosure `<p>` (lines 44–49) moves verbatim into **NEW `app/views/application/_status_disclosure.html.erb`**; `_footer` renders it. `status_disclosure_spec` bytes preserved. |
| `app/controllers/concerns/fuime/guardianship_enforcement.rb` | allowlist entries (§3). |
| `config/initializers/friendly_id.rb` | reserved words `setup`, `join`. |
| `docs/fuime/ONBOARDING_PLAN.md` | §5: E1 shipped (with the `active` + `initiated_by` decision replacing `awaiting_minor`); C1 partly shipped (name on accept, skip redirect; `?k=` pending, reuse `SignedLinkSignIn`). |
| `docs/fuime/UPSTREAM_DIVERGENCE.md`, `docs/fuime/SETUP_NOTES.md` | one row per change; handoff note. |

Untouched by rule: `Event::Application` (model), `Event::ApplicationsController`, `Fuime::FounderAdmission`, `Fuime::GuardianInviteService`, `User#attest_*`, every `guardianships/agreements/*` partial, `CURRENT_AGREEMENT_VERSION`, `fuime_product`/`apply` layouts, ledger, `HcbCode`, `Event` names.

---

## 9. Layout — `app/views/layouts/fuime_setup.html.erb` (**NEW**)

Cloned from `fuime_product.html.erb` (same `@is_dark` line, `content_for(:container_class, "container--full !px-0")`, `no_app_shell`, the `<style>` head block, `parent_layout "application"`, `@hide_flash = true` at the end), with these differences:

- Outer `<main class="container … h-screen" data-controller="wizard" data-wizard-key-value="<%= wizard_path %>" data-wizard-progress-value="<%= wizard_progress %>" data-wizard-step-value="<%= wizard_step_index %>">`.
- Header: `application/logo`; `h2` = `yield(:wizard_title)`; `h3.text-sm.muted` = `yield(:wizard_subtitle)`; right side: `button_to logout_users_path, method: :delete, class: "btn bg-muted text-sm"` labelled **Sign out** (a half-onboarded user has nowhere else to go; there is no "Exit").
- Flash slots as in `fuime_product`.
- Progress: `<div class="wizard-bar"><div class="wizard-fill" data-wizard-target="fill" style="width: <%= wizard_progress %>%"></div></div>`.
- Rail: `render "fuime/onboarding/rail"` (**NEW** partial) — `<ol class="wizard-rail">` of `<li class="wizard-rail__step is-done|is-current|is-todo" data-wizard-target="step">` each with `.wizard-rail__dot` (inline 12px check SVG `path` with `class="wizard-rail__check"`, `stroke-dasharray: 24; stroke-dashoffset: 24`) and `.wizard-rail__label` (`sr-only` below `sm` except the current one). Labels from `wizard_labels`.
- Body: the `fuime_product` two-column block (`info_pane` sticky at `md`, main column `md:max-w-[600px]`), the yielded form wrapped in `<section class="wizard-panel" data-wizard-target="panel">`.
- Footer strip (`border-t-2 border-smoke dark:border-slate dark:bg-darkless`, sticky bottom on phones with `padding-bottom: max(1rem, env(safe-area-inset-bottom))`): `yield(:footer)` (Back left as `.btn.bg-muted`, primary right as `.btn.btn--fuime` with `form="setup_form"`). Beneath it, always: `render "application/status_disclosure"` inside `p.text-xs.muted.text-center` — the byte-identical "financial technology company, not a bank" sentence (L5), because `no_app_shell` never renders `application/_footer`.

`wizard_path` = `"teen"` or `"parent"`; `wizard_steps` = the matching `STEPS`; `wizard_progress` = `((index + 1) * 100.0 / steps.length).round` (teen 20/40/60/80/100; parent 33/67/100 — render 66 as the label is never shown).

---

## 10. Styles — `app/assets/stylesheets/components/_wizard.scss` (**NEW**, imported from `application.scss` after `components/welcome`)

Everything derives from `_variables.scss`. `$wiz: map-get($palette, primary)` (= `$fuime-blue`). **Never use Tailwind `bg-primary`/`text-primary` for fills here** — `tailwind.config.js:84,93` defines `primary: '#ec3750'` (HCB red) while the SCSS palette is `$fuime-blue`; `fuime_product`'s `bg-primary h-1` bar is the trap. (`card--outline` is used in views but defined nowhere; the wizard uses plain `.card`.)

- `.btn--fuime` — `background: $wiz; color: #fff; border-radius: var(--radius-lg); height: 44px; min-height: 44px; box-shadow: none;` hover `darken($wiz, 6%)`, `:focus-visible` ring `0 0 0 3px rgba($wiz, .3)`, `[disabled] { opacity: .5 }`; identical under `html[data-dark='true'] &`.
- `.wizard-bar { height: 3px; background: $smoke; [data-dark='true'] & { background: $slate } }` `.wizard-fill { height: 100%; background: $wiz; transition: width .45s cubic-bezier(.2,.8,.2,1) }`.
- `.wizard-rail` (`list-style: none; display: flex; gap: 1rem; padding: .75rem 1rem 0`), `.wizard-rail__step` (flex, `gap: .5rem`, `color: $muted`; `.is-current` `font-weight: 600; color: $black` / dark `$snow`), `.wizard-rail__dot` (22px circle, `border: 1.5px solid $smoke-dark`; `.is-current &` `border-color: $wiz; background: rgba($wiz,.12); animation: wizard-pulse .6s ease-out 1`; `.is-done &` `background: $wiz; border-color: $wiz`), `.wizard-rail__check` (`stroke: #fff`; `.is-drawing &` `animation: wizard-check .28s ease-out .1s forwards`). Below `sm`: dots only, `.wizard-rail__label { @extend .sr-only }` except `.is-current`.
- `.wizard-segment` — pill group: `display: inline-flex; border: 1px solid $smoke; border-radius: 999px; padding: 3px`; `input { position: absolute; opacity: 0 }`; `input:checked + label { background: $wiz; color: #fff }`; labels `padding: .5rem .9rem; border-radius: 999px; cursor: pointer`. Wraps to a column below `sm`.
- `.wizard-option-grid { display: grid; gap: .75rem; grid-template-columns: 1fr; @media (min-width: 640px) { grid-template-columns: repeat(2, 1fr) } }` `.wizard-option { display: flex; flex-direction: column; gap: .15rem; min-height: 56px; padding: .875rem 1rem; border: 1px solid $smoke; border-radius: var(--radius-lg); background: $white; cursor: pointer; [data-dark='true'] & { background: $darkless; border-color: $slate } }` `input:checked + .wizard-option { box-shadow: 0 0 0 2px $wiz; background: rgba($wiz,.06) }` `input:focus-visible + .wizard-option { box-shadow: 0 0 0 3px rgba($wiz,.3) }` (radio is `sr-only` before the label). Not `.field--options`: those centre-stack and cap at 24rem, wrong for 14 options on a phone.
- `.wizard-panel--enter { animation: wizard-in .22s cubic-bezier(.2,.8,.2,1) both }` `--enter-back` (`wizard-in-back`) `--exit { animation: wizard-out .14s ease-in forwards }` `--exit-back`. `.wizard-stagger > * { animation: wizard-in .3s both; animation-delay: calc(var(--i, 0) * 60ms) }`.
- Keyframes: `wizard-in` (opacity 0→1, translateX(16px)→0), `wizard-in-back` (−16px→0), `wizard-out` (1→0, 0→−8px), `wizard-out-back` (→8px), `wizard-check` (`stroke-dashoffset` 24→0), `wizard-pulse` (`box-shadow: 0 0 0 0 rgba($wiz,.35)` → `0 0 0 8px rgba($wiz,0)`).
- `.wizard-footer { position: sticky; bottom: 0; }` on phones; `.wizard-agreement` = the `max-height: 24rem; overflow-y: auto` box class used by `_agreement_box`.
- `@media (prefers-reduced-motion: reduce) { .wizard-panel, .wizard-stagger > *, .wizard-rail__dot, .wizard-rail__check { animation: none !important } .wizard-fill { transition: none } }`. No element ever rests at `opacity: 0`.

Everything else is existing: `.card`, `.field`, `.field--checkbox`, `.btn.bg-muted`, `.btn.bg-success`, `.muted`, `.sr-only`, `application/_callout` (`type:`, `title:`), `inline_icon`, `country_select`, Tailwind spacing/flex utilities, the system font stack, `html[data-dark='true']` for dark mode.

---

## 11. Animation — `app/javascript/controllers/wizard_controller.js` (**NEW**, Stimulus; auto-registered by `controllers/index.js` `require.context`)

```js
import { Controller } from '@hotwired/stimulus'
export default class extends Controller {
  static targets = ['panel', 'fill', 'step']
  static values  = { key: String, progress: Number, step: Number }
  connect() {
    this.reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    let prev = null, prevStep = null
    try { prev = Number(sessionStorage.getItem(`fuime.wizard.${this.keyValue}.progress`)); prevStep = Number(sessionStorage.getItem(`fuime.wizard.${this.keyValue}.step`)) } catch (_) {}
    const back = Number.isFinite(prev) && prev > this.progressValue
    if (this.hasFillTarget && !this.reduced && Number.isFinite(prev) && prev !== this.progressValue) {
      this.fillTarget.style.width = `${prev}%`
      requestAnimationFrame(() => requestAnimationFrame(() => { this.fillTarget.style.width = `${this.progressValue}%` }))
    }
    if (this.hasPanelTarget && !this.reduced) this.panelTarget.classList.add(back ? 'wizard-panel--enter-back' : 'wizard-panel--enter')
    if (!this.reduced && Number.isFinite(prevStep) && prevStep === this.stepValue - 1) {
      const justDone = this.stepTargets[prevStep]; if (justDone) justDone.classList.add('is-drawing')   // only the step just completed draws its check
    }
    try { sessionStorage.setItem(`fuime.wizard.${this.keyValue}.progress`, this.progressValue); sessionStorage.setItem(`fuime.wizard.${this.keyValue}.step`, this.stepValue) } catch (_) {}
    this.beforeCache = () => this.panelTarget?.classList.remove('wizard-panel--exit', 'wizard-panel--exit-back', 'wizard-panel--enter', 'wizard-panel--enter-back')
    document.addEventListener('turbo:before-cache', this.beforeCache)
  }
  disconnect() { document.removeEventListener('turbo:before-cache', this.beforeCache) }
  leave()     { if (!this.reduced) this.panelTarget.classList.add('wizard-panel--exit') }        // data-action="turbo:submit-start->wizard#leave" on #setup_form
  leaveBack() { if (!this.reduced) this.panelTarget.classList.add('wizard-panel--exit-back') }   // data-action="click->wizard#leaveBack" on Back links
}
```
Exit is cosmetic and never blocks navigation (no `preventDefault`, no `await`). Forms are ordinary Turbo forms except `sign` (`data-turbo: false`, as the accept form). A 422 re-render has equal progress → no bar motion, a plain enter. Confetti on both `done` screens comes from `confetti!` + `layouts/_body_suffix`. gsap is available (`welcome_controller.js`) but not needed.

---

## 12. Playground (demo)

`app/services/fuime/playground.rb`: add `NEW_PARENT_EMAIL = "playground+priya@fuime.test"`, `NEW_KID_EMAIL = "playground+kid@fuime.test"`, `PERSONA_EMAILS = [TEEN_EMAIL, GUARDIAN_EMAIL, NEW_FOUNDER_EMAIL, NEW_PARENT_EMAIL, NEW_KID_EMAIL]`, `def self.persona?(email) = email.to_s.strip.downcase.then { |e| e.start_with?("playground+") && e.end_with?("@fuime.test") } || ::Fuime::DemoSandbox.demo_email?(email)`. **NEW** `reset_new_parent!` (mirrors `reset_new_founder!`): `Guardianship.where(guardian_id: priya.id).delete_all`, destroy the kid user if present (`User.find_by(email: NEW_KID_EMAIL)&.destroy`), null Priya's `full_name/preferred_name/birthday/age_attestation*`, `verified: true`. `seed!` calls it; `status` gains `new_parent`, `new_parent_fresh` (`full_name.blank? && guardianships_as_guardian.none?`); `banner` lists Priya.

`Admin::PlaygroundController#fresh_parent` (**NEW** action, mirrors `fresh_founder`): `authorize current_user, :impersonate?`; `user = Fuime::Playground.new.reset_new_parent!`; `impersonate_user(user)`; `redirect_to parent_setup_path, flash: { info: "You're Priya now — a parent who has never used Fuime." }`. `fresh_founder` keeps `redirect_to root_path` — `redirect_to_onboarding` now lands Sam on `/setup/you`, the same first screen a real signup sees.

`app/views/admin/playground/show.html.erb`: next to the Sam card, a **Priya** card: "brand-new parent · fresh / mid-demo" and `button_to "Start fresh as Priya", playground_fresh_parent_admin_index_path`. The narrative section gains: "**Start fresh as Priya.** Name a teen (use `playground+kid@fuime.test`), sign the agreement, land on the guardian page. The kid's join mail is suppressed; open `/join/…` from the log if you want to play the teen."

**NEW** `config/initializers/fuime_playground_mail.rb` registering `Fuime::PlaygroundMailInterceptor` (**NEW** `app/lib/fuime/playground_mail_interceptor.rb`): `delivering_email(message)` sets `message.perform_deliveries = false` when every recipient satisfies `Fuime::Playground.persona?`. Live demo clicks therefore never reach Resend; the `@fuime.test` guards in `save_teen`/`save_family` stop a persona from mailing a real inbox.

---

## 13. Edge cases

| Case | Behaviour |
|---|---|
| Returning user with name + venture hits `/setup` | `start` → `root_path`. With a teen draft → resumes at the first incomplete step; adult draft → old status page. |
| Known adult hits `/setup` with nothing | `new_application_path` with the flash (§3.3 #6); the wizard never creates `teen_led: false`. |
| Adult opt-out mid-wizard | `you` link → `new_application_path` (old wizard's `_begin` radio sets `teen_led=false`). |
| Under-13 | Teen `you` unticked → model refusal + "Fuime is for founders 13 and up."; parent `teen` unticked → same sentence, nothing signed, nothing persisted. No DOB, no promise of a younger tier. |
| Teen-first pending invite, then the same parent goes parent-first (or vice versa) | `Guardianship.find_by(guardian:, minor:)` finds the pending row; `accept!` activates it; `initiated_by` stays `minor`; the teen gets the existing `accepted` mail, no join mail; the teen's `family` step drops the email field. |
| Parent-first for a teen who already has a full account | no `preferred_name` write (`onboarding?` false); row created `initiated_by: guardian`, accepted; `teen_join` with the "already have an account" paragraph; next `/setup` visit shows "{Parent} already signed" on `family`. |
| Parent typed the wrong teen email | `/guardian` row: "hasn't joined yet · Send the link again · Withdraw consent"; parent revokes (`GuardianshipPolicy#revoke?`) and runs `/setup/parent/teen` again with a different address (a revoked pair is refused at `sign`; a different address is a different minor). The stub stays: no name, no venture, harmless. |
| Join link opened while signed in as the parent | wrong-account page with the redacted teen email and a sign-out button; the parent never lands in the teen's session. |
| Join link expired (7 days) / tampered | flash naming the fix; ordinary login code always works; `/guardian` and parent `done` offer "Send the link again" (cooldown 10 min). |
| Signed-in stranger opens `/join/:token` | refused (403 page), nothing written. |
| 2FA users | both `/join/:token` and the code path land on `choose_login_preference` with `return_to`, as the waitlist invite does. |
| Parent abandons at `teen` or `sign` | session only; nothing persisted. Teen abandons after `business` | draft application persists; home card and `start` resume it. |
| Parent whose account earlier ticked 13+ | `attest_adult_18_plus!` overwrites `minor_13_plus` — the one documented legitimate transition. |
| Two parents for one teen | unique index is on `(guardian_id, minor_id)`; a second parent may run `/setup/parent`. |
| Self-signing (teen with two inboxes) | unchanged: `self_signed_signals` still fires on shared fingerprint/IP/alias/no-activity; only the fast-acceptance signal is skipped for guardian-initiated rows, and the same human reviews every payout batch. |
| Guardian invite mail fails at submit | `guardian_invite_error` on `done` with the `new_guardianship_path` recovery link, as the old submit flash does. |
| Cohort code | typed on `family`; unknown never blocks; `Fuime::CohortAdmission` runs inside `mark_submitted!`'s after-hook as today. |
| Free-plan slot on a first venture | cannot happen (no events); a second venture goes through `apply_path` (old wizard) where `activation_blockers` surfaces. |
| Session lost mid-wizard | `start` rebuilds from records (draft → step; parent → `teen`). |
| Nameless parent following a bare `/guardian/:token` | signs in with a code → `complete` → `/setup?return_to=/guardian/…` → `start` #2 → accept page, which now collects the name. |
| Impersonated personas | all persona mail dropped by the interceptor; personas may only type `@fuime.test` addresses. |

---

## 14. Copy invariants (L5 / L8) — pinned by `spec/requests/fuime_setup_copy_spec.rb`

Never on any wizard page, the parent signup variant, or either mail: `bank`, `banking`, `neobank`, `checking`, `savings`, `deposit`, `insured`, `FDIC`, `your money is safe`, `start selling now`, `activate`, `approve every payout`, `usually within`, any `$` amount, and nothing matching `Fuime::OffersController::PRICE_SUGGESTION_COPY` — except the standing disclosure sentence itself, which must be present on every `/setup/**` page. Always true today: "financial platform for young founders"; vetting "by a person … before anything can be sold"; "signs off before you get paid" / "before any money is paid out"; "no Social Security number, ID, or payment"; "not an identity check". The guardian gates whether payouts can happen and where they go, never each payout. No date of birth, no price, no ETA.

---

## 15. Specs

**New** (`spec/requests/` unless noted; sign in with the `login_as!` helper from `family_signup_flow_spec.rb`):
1. `fuime_setup_teen_flow_spec.rb` — `/users/auth?signup=true` → code → `complete` redirects to `setup_path` → `you` (422 without the tick; 200 with; `minor_13_plus` + IP/UA recorded; never `adult_18_plus` however crafted) → `business` (422 on bad keys; creates one draft, `teen_led: true`, derived `business_category`; second POST reuses it) → `name` → `family` (422 own email; 422 disallowed country; 422 lists `submission_blockers`; success: `Event` exists, manager `OrganizerPosition`, `operator_vetting_status == "unvetted"`, `offer_publish_blockers` names vetting, `Guardianship.pending` for the parent, one invite mail enqueued) → `done` renders venture name, cosigner email, "by a person"; second GET → `setup_path` → `root_path`.
2. `fuime_setup_teen_resume_spec.rb` — abandoning after `business` and re-entering `/setup` resumes at `name`; an old-wizard teen draft is picked up; a user with a venture → home; a known adult → `new_application_path`; the `you` auto-skip.
3. `fuime_setup_teen_with_guardian_spec.rb` — active guardian: no email field on `family`, submit without `cosigner_email`, `done` says the guardian signed.
4. `fuime_setup_parent_flow_spec.rb` — `?signup=true&return_to=/setup/parent` title/sub-line; code → `/setup/parent/teen` (nameless parent NOT bounced to settings) → `teen` (422 own email, blank name, unticked 13+, known-adult address; nothing persisted) → `sign` renders the v4 partial, the byte-exact label, `NOT_A_BANK` + `NO_FDIC`; POST without `agree` changes nothing; happy path: stub `User` (`full_name` nil, `preferred_name` "Maya", `creation_method` `family_invite`, `age_attestation` nil), parent `attested_adult_18_plus?`, name saved with a plain save, `Guardianship` `active` with `initiated_by` `guardian`, `agreement_version == CURRENT_AGREEMENT_VERSION`, IP/UA; `GuardianshipMailer#accepted` **not** enqueued; one `teen_join` enqueued with `wait_until` in-window when frozen at 01:00; `done` renders; the signed token appears in no HTML response of the parent path or `/guardian`.
5. `fuime_setup_parent_converges_spec.rb` — pending teen-first pair accepted in place (`initiated_by` minor, `accepted` mail sent, no join mail); parent-first then `/join/:token` → session, `/setup/you` with the guardian card, completes with no email field, venture created, `has_active_guardian?`.
6. `fuime_family_invite_spec.rb` — valid token → signed in (`verified: true`, `User::Session`), → `setup_path`; expired/tampered → `auth_users_path(signup: true)` with the flash; signed-in stranger → 403 page with sign-out and no teen name; 2FA user → `choose_login_preference`; `resend_join` policy (minor cannot, guardian can, only while `minor.onboarding?`) and cooldown.
7. `fuime_setup_copy_spec.rb` — §14 across all eight wizard pages, both mails and the parent signup variant.
8. `spec/controllers/fuime/guardianship_enforcement_spec.rb` — add "allowlists fuime/onboarding and fuime/family_invites" next to the applications example.
9. `spec/models/guardianship_spec.rb` — `initiated_by` default; `accept!(notify_minor: false)` skips the mail and default still sends; `self_signed_signals` ignores fast acceptance when guardian-initiated and still reports it when minor-initiated.
10. `spec/mailers/fuime/family_mailer_spec.rb` — subject, `find_signed`-verifiable token, existing-account paragraph, no L5 words.
11. `spec/services/fuime/playground_spec.rb` — Priya is nameless/unattested/idempotent; reset clears her guardianships and the kid; `persona?`.
12. `spec/lib/fuime/minor_mail_window_spec.rb`, `spec/lib/fuime/playground_mail_interceptor_spec.rb`, `spec/policies/guardianship_policy_spec.rb` (two new methods).

**Updated**: `spec/requests/family_signup_flow_spec.rb:47`, `spec/controllers/logins_controller_spec.rb:460`, `spec/requests/fuime_waitlist_invite_spec.rb:52` (`edit_user_path` → `setup_path`); `spec/requests/fuime/status_disclosure_spec.rb` (+ `/setup/parent/sign`, `/setup/you`; `_footer` extraction keeps `/faq`, `/terms`, guardian page green); `spec/controllers/guardianships_render_spec.rb` (partial extraction keeps "I am 18 or older"; name field shown for a nameless guardian); `spec/mailers/guardianship_mailer_spec.rb` unchanged. `bundle exec rspec` green before merge; branch `fuime/onboarding-wizard`.

---

## 16. Files

**New**: `app/controllers/fuime/onboarding_controller.rb`, `app/controllers/fuime/family_invites_controller.rb`, `app/controllers/concerns/signed_link_sign_in.rb`, `app/lib/fuime/cohort_stamp.rb`, `app/lib/fuime/minor_mail_window.rb`, `app/lib/fuime/playground_mail_interceptor.rb`, `app/services/fuime/family_invite_service.rb`, `app/mailers/fuime/family_mailer.rb`, `app/views/fuime/family_mailer/teen_join.{html,text}.erb`, `app/views/layouts/fuime_setup.html.erb`, `app/views/fuime/onboarding/_rail.html.erb`, `app/views/fuime/onboarding/teen/{you,business,name,family,done}.html.erb`, `app/views/fuime/onboarding/parent/{teen,sign,done}.html.erb`, `app/views/fuime/family_invites/wrong_account.html.erb`, `app/views/guardianships/_agreement_box.html.erb`, `app/views/application/_status_disclosure.html.erb`, `app/assets/stylesheets/components/_wizard.scss`, `app/javascript/controllers/wizard_controller.js`, `config/initializers/fuime_playground_mail.rb`, `db/migrate/<ts>_add_initiated_by_to_guardianships.rb`, the specs in §15.

**Edited**: `config/routes.rb`, `config/initializers/friendly_id.rb`, `app/controllers/application_controller.rb`, `app/controllers/logins_controller.rb`, `app/views/logins/new.html.erb`, `app/controllers/waitlist_invites_controller.rb`, `app/controllers/guardianships_controller.rb`, `app/views/guardianships/{show,index}.html.erb`, `app/views/application/_footer.html.erb`, `app/policies/guardianship_policy.rb`, `app/models/guardianship.rb`, `app/models/user.rb` (enum value), `app/controllers/concerns/fuime/guardianship_enforcement.rb`, `app/services/fuime/playground.rb`, `app/controllers/admin/playground_controller.rb`, `app/views/admin/playground/show.html.erb`, `app/assets/stylesheets/application.scss`, `site/server.js` (+ `site/parents.html` CTA, optional until `/parents` reopens), `docs/fuime/ONBOARDING_PLAN.md`, `docs/fuime/UPSTREAM_DIVERGENCE.md`, `docs/fuime/SETUP_NOTES.md`.

## 17. Migrations

One, additive: `AddInitiatedByToGuardianships` (`initiated_by :integer, default: 0, null: false`). Everything else is an additive enum value, a keyword argument, a signed id, a policy method, one concern, one module, one mailer, one controller pair, one layout, one stylesheet, one Stimulus controller.

---

## File plan (from the synthesis)

- app/controllers/fuime/onboarding_controller.rb — NEW: both paths (start dispatcher, teen/teen_save, parent/parent_save), STEP lists, session helpers, layout fuime_setup, enforcement-allowlisted
- app/controllers/fuime/family_invites_controller.rb — NEW: GET /join/:token; verifies the signed_id, wrong-account 403, signs in via SignedLinkSignIn, redirects to /setup
- app/controllers/concerns/signed_link_sign_in.rb — NEW: sign_in_from_signed_link!(user:, purpose:, return_to:) moved verbatim from WaitlistInvitesController#show
- app/lib/fuime/cohort_stamp.rb — NEW: from_waitlist(session:, user:) and from_code(typed) so the wizard resolves cohorts through Fuime::Cohort.for_code without touching Event::ApplicationsController
- app/lib/fuime/minor_mail_window.rb — NEW: earliest_send_time(now:, zone:) for L7 quiet hours (06:00 local), used by teen_join
- app/lib/fuime/playground_mail_interceptor.rb — NEW: ActionMailer interceptor that drops mail whose recipients are all Fuime::Playground.persona?
- app/services/fuime/family_invite_service.rb — NEW: generate_token/verify_token (signed_id purpose :family_join, 7 days)
- app/mailers/fuime/family_mailer.rb — NEW: teen_join(guardianship:) mints the join URL inside the mailer; html+text
- app/views/fuime/family_mailer/teen_join.html.erb — NEW: the parent-first teen's one transactional email
- app/views/fuime/family_mailer/teen_join.text.erb — NEW: text part of the same mail
- app/views/layouts/fuime_setup.html.erb — NEW: wizard layout cloned from fuime_product with wizard rail, progress fill, sticky footer, sign-out, and the standing disclosure partial
- app/views/fuime/onboarding/_rail.html.erb — NEW: step rail (dots + labels, is-done/is-current/is-todo, data-wizard-target=step)
- app/views/fuime/onboarding/teen/you.html.erb — NEW: name + write-once 13+ + terms; guardian card for parent-first teens; adult/parent fork links
- app/views/fuime/onboarding/teen/business.html.erb — NEW: starting-point segment + 14-service .wizard-option grid
- app/views/fuime/onboarding/teen/name.html.erb — NEW: business name + description; template outline card
- app/views/fuime/onboarding/teen/family.html.erb — NEW: summary with Edit links, country, parent email when needed, event code details, Finish setup
- app/views/fuime/onboarding/teen/done.html.erb — NEW: You're in; next-steps checklist; family line; two CTAs
- app/views/fuime/onboarding/parent/teen.html.erb — NEW: welcome bullets in the info pane; teen first name, email, session-only 13+ gate
- app/views/fuime/onboarding/parent/sign.html.erb — NEW: name if blank, shared agreement box, I agree
- app/views/fuime/onboarding/parent/done.html.erb — NEW: You're {Teen}'s guardian; what happens next; Send the link again / Add another teen / guardian page
- app/views/fuime/family_invites/wrong_account.html.erb — NEW: 403 page with redacted teen email and sign-out button only
- app/views/guardianships/_agreement_box.html.erb — NEW: agreement scroll box + agree checkbox extracted byte-for-byte from guardianships/show
- app/views/application/_status_disclosure.html.erb — NEW: the not-a-bank sentence extracted verbatim from application/_footer
- app/assets/stylesheets/components/_wizard.scss — NEW: .btn--fuime, .wizard-bar/.wizard-fill, .wizard-rail, .wizard-segment, .wizard-option(-grid), panel/stagger keyframes, reduced-motion; all from map-get($palette, primary)
- app/javascript/controllers/wizard_controller.js — NEW: Stimulus 'wizard' (values key/progress/step; targets panel/fill/step); sessionStorage-based bar and direction, check draw, cosmetic exit
- config/initializers/fuime_playground_mail.rb — NEW: registers Fuime::PlaygroundMailInterceptor
- db/migrate/<timestamp>_add_initiated_by_to_guardianships.rb — NEW: add_column :guardianships, :initiated_by, :integer, default: 0, null: false
- config/routes.rb — EDIT: /setup, /setup/parent, /setup/parent/:step, /setup/:step, /join/:token before the /:event_slug routes; guardianships member post :resend_join; admin playground/fresh_parent
- config/initializers/friendly_id.rb — EDIT: reserved words setup, join
- app/controllers/application_controller.rb — EDIT: redirect_to_onboarding → setup_path(return_to:)
- app/controllers/logins_controller.rb — EDIT: name-blank branch of #complete → setup_path(return_to: @login.return_to); #new sets @parent_signup
- app/views/logins/new.html.erb — EDIT: parent-signup title and sub-line variant
- app/controllers/waitlist_invites_controller.rb — EDIT: use SignedLinkSignIn; after_waitlist_login_path → setup_path when name blank
- app/controllers/guardianships_controller.rb — EDIT: skip redirect_to_onboarding for show/accept; @needs_name; accept saves a blank name and redirects to /guardian; resend_join
- app/views/guardianships/show.html.erb — EDIT: render _agreement_box; full-name field when @needs_name
- app/views/guardianships/index.html.erb — EDIT: active ward who is still onboarding? shows 'hasn't joined yet' + Send the link again
- app/views/application/_footer.html.erb — EDIT: render application/status_disclosure in place of the moved paragraph
- app/policies/guardianship_policy.rb — EDIT: create_as_guardian?, resend_join?
- app/models/guardianship.rb — EDIT: enum initiated_by; accept!(notify_minor: true); self_signed_signals skips fast acceptance when guardian-initiated; schema comment
- app/models/user.rb — EDIT: creation_method family_invite: 9
- app/controllers/concerns/fuime/guardianship_enforcement.rb — EDIT: allowlist fuime/onboarding, fuime/family_invites
- app/services/fuime/playground.rb — EDIT: NEW_PARENT_EMAIL, NEW_KID_EMAIL, PERSONA_EMAILS, persona?, reset_new_parent!, status/banner additions
- app/controllers/admin/playground_controller.rb — EDIT: fresh_parent action
- app/views/admin/playground/show.html.erb — EDIT: Priya card and narrative
- app/assets/stylesheets/application.scss — EDIT: @import 'components/wizard'
- site/server.js — EDIT: /family → app /users/auth?signup=true&return_to=%2Fsetup%2Fparent (site/parents.html CTA optional until /parents reopens)
- docs/fuime/ONBOARDING_PLAN.md — EDIT: E1 shipped as active+initiated_by (awaiting_minor retired); C1 partly shipped
- docs/fuime/UPSTREAM_DIVERGENCE.md — EDIT: one row per change above
- docs/fuime/SETUP_NOTES.md — EDIT: handoff note
- spec/requests/fuime_setup_teen_flow_spec.rb — NEW
- spec/requests/fuime_setup_teen_resume_spec.rb — NEW
- spec/requests/fuime_setup_teen_with_guardian_spec.rb — NEW
- spec/requests/fuime_setup_parent_flow_spec.rb — NEW
- spec/requests/fuime_setup_parent_converges_spec.rb — NEW
- spec/requests/fuime_family_invite_spec.rb — NEW
- spec/requests/fuime_setup_copy_spec.rb — NEW: L5/L8 invariants
- spec/mailers/fuime/family_mailer_spec.rb — NEW
- spec/lib/fuime/minor_mail_window_spec.rb — NEW
- spec/lib/fuime/playground_mail_interceptor_spec.rb — NEW
- spec/policies/guardianship_policy_spec.rb — NEW or extended: create_as_guardian?, resend_join?

## Existing specs that must change

- spec/requests/family_signup_flow_spec.rb (line 47) — expects edit_user_path(teen.slug) after the login code; the name-blank branch now redirects to setup_path(return_to:). Add a parent-first example that ends with the teen submitting on the wizard and has_active_guardian? true.
- spec/controllers/logins_controller_spec.rb (line 460, 'redirects to the profile form if they don't have a name') — expectation becomes setup_path(return_to: nil); the example at ~467 (named user → product) is unchanged.
- spec/requests/fuime_waitlist_invite_spec.rb (line 52) — expects edit_user_path(user.slug) for a nameless invitee; becomes setup_path. Behaviour of the sign-in block is unchanged (moved into SignedLinkSignIn).
- spec/requests/fuime/status_disclosure_spec.rb — add /setup/parent/sign and /setup/you as surfaces that must include NOT_A_BANK and NO_FDIC; the _footer → _status_disclosure extraction must keep /faq, /terms and the guardian page green byte-for-byte.
- spec/controllers/guardianships_render_spec.rb — the accept page now renders guardianships/_agreement_box; the 'I am 18 or older' assertion (line 146) must still pass; add: a nameless guardian sees the Your full name field.
- spec/models/guardianship_spec.rb ('#accept!' at line 103) — add: default still enqueues GuardianshipMailer.accepted; accept!(notify_minor: false) does not; initiated_by defaults to minor; self_signed_signals omits the fast-acceptance line when initiated_by_guardian? and keeps it when minor-initiated; IP/UA/version recording unchanged.
- spec/controllers/fuime/guardianship_enforcement_spec.rb — add an example next to 'allowlists the applications controller' asserting fuime/onboarding and fuime/family_invites are in ALLOWED_CONTROLLER_PATHS and business pages remain denied.
- spec/services/fuime/playground_spec.rb — add: reset_new_parent! leaves Priya nameless/unattested with no guardianships and no kid user; idempotent; persona? covers the five playground addresses and demo+ addresses.
- spec/controllers/fuime/onboarding_terms_spec.rb — unchanged (users/edit onboarding branch stays); add a twin request example that /setup/you links Terms, Privacy and Guardian Agreement with the MoR sentence.
- spec/mailers/guardianship_mailer_spec.rb — unchanged; confirm #accepted is still delivered on the default accept! path.

## Migrations (additive only)

- AddInitiatedByToGuardianships — add_column :guardianships, :initiated_by, :integer, default: 0, null: false (enum minor: 0, guardian: 1, prefix :initiated_by). Additive; existing rows are minor-initiated by default; no backfill, no index. Records who initiated the relationship so Guardianship#self_signed_signals can skip accepted_suspiciously_fast? for parent-first rows and accept! can skip the 'accepted your invitation' mail when there was no invitation.

---

## Appendix — review findings from the parallel platform review (session fuime-70, 2026-09-11)

Found by a multi-agent review plus a screenshot walk of a brand-new teen signup
(shots at the reviewer's scratchpad, `shots/NOTES.md` then `teen-new/step-01…18`:
14 screens, 18 interactions from "start signup" to "a draft offer saved"). None of
these were fixed; fold them into the wizard build.

1. The login-code screen is headed "Sign in to Fuime" during a brand-new signup that
   arrived from `?signup=true` ("Start your business on Fuime").
2. The 6-digit code is in the email subject line — deliberate, keep it.
3. Minting a login code now supersedes the account's other live codes, and
   `POST /logins/:id/complete` is rate limited (10 / 15 min per Login, 30 per IP) —
   fixed on the reviewer's branch `fuime/platform-review-p0`. If the wizard mints
   codes, only the newest is valid.
4. After the name screen the flash says "You'll invite a parent or guardian when your
   business is ready to launch." Under MoR the guardian gates payouts, not launch.
5. `POST /applications` takes ~9.5 s ("Completed 302 Found in 9488ms") — the worst
   latency in the funnel; profile before or during the rewrite.
6. `/applications/new` is a marketing interstitial with no input.
7. `project_info` still carries HCB's annual budget / committed amount / funding
   source / team size / planning duration fields hidden in the DOM.
8. One Submit sends three HCB lifecycle emails, one describing fiscal sponsorship
   (`Event::Application` ~line 269).
9. Adult signup ("No, I'm 18+") is a dead end: still asked for a parent's email and
   HCB nonprofit budget questions (`_begin.html.erb` ~line 95).
10. The first-visit welcome overlay covers a 375px phone entirely; dismissal
    persists. Check mobile framing.
11. Playground Buy refused for the impersonated teen — **fixed** in
    `fuime/playground-demo-polish` (`refuse_minor_buyer` skips demo ventures).

Also fixed on the reviewer's branch, so do not redo: the review page's out-of-office
callout is gone; a blocked submit now flashes why; `_selling_blockers` no longer
prints a literal `%>` and honours `title:`.
