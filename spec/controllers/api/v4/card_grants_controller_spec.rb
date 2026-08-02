# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V4::CardGrantsController do
  render_views

  describe "#create" do
    def card_grant_params
      {
        amount_cents: "123_45",
        email: "recipient@example.com",
        keyword_lock: "some keywords",
        purpose: "Raffle prize",
        one_time_use: "true",
        pre_authorization_required: "true",
        instructions: "Here's a card grant for your raffle prize"
      }
    end

    it "creates a card grant" do
      user = create(:user, full_name: "Orpheus the Dinosaur", email: "orpheus@hackclub.com")
      event = create(:event, :with_positive_balance, name: "Test Event", plan_type: Event::Plan::HackClubAffiliate)
      create(:card_grant_setting, event:)
      create(:organizer_position, user:, event:)

      token = create(:api_token, user:)
      request.headers["Authorization"] = "Bearer #{token.token}"

      # `UsersHelper#profile_picture_for` uses `gravatar_url` if the user
      # hasn't uploaded an image. The background colour for the Gravatar
      # fallback image is determined by the user's ID, which makes the
      # response value unpredictable.
      allow_any_instance_of(UsersHelper).to receive(:gravatar_url).and_return("https://gravatar.com/avatar/stubbed")

      post(:create, params: { event_id: event.friendly_id, **card_grant_params, expand: "disbursements,user,organization" }, as: :json)

      expect(response).to have_http_status(:created)
      card_grant = event.card_grants.sole
      disbursement = card_grant.disbursement
      recipient = card_grant.user

      serialized_event = {
        "id"                                => event.public_id,
        "object"                            => "organization",
        "parent_id"                         => nil,
        "name"                              => "Test Event",
        "slug"                              => "test-event",
        "background_image"                  => nil,
        "country"                           => nil,
        "fee_percentage"                    => 0.0,
        "financially_frozen"                => false,
        "icon"                              => nil,
        "donation_page_available"           => true,
        "playground_mode"                   => false,
        "playground_mode_meeting_requested" => nil,
        "transparent"                       => true,
        "created_at"                        => event.created_at.iso8601(3)
      }

      expect(response.parsed_body).to eq(
        {
          "id"                         => card_grant.public_id,
          "object"                     => "card_grant",
          "amount_cents"               => 123_45,
          "card_id"                    => nil,
          "one_time_use"               => true,
          "pre_authorization_required" => true,
          "status"                     => "active",
          "allowed_categories"         => [],
          "allowed_merchants"          => [],
          "category_lock"              => [],
          "merchant_lock"              => [],
          "purpose"                    => "Raffle prize",
          "keyword_lock"               => "some keywords",
          "email"                      => "recipient@example.com",
          "expires_on"                 => card_grant.expiration_at.iso8601,
          "disbursements"              => [
            {
              "id"                      => disbursement.public_id,
              "object"                  => "disbursement",
              "memo"                    => "Grant to recipient",
              "status"                  => "completed",
              "transaction_id"          => disbursement.local_hcb_code.public_id,
              "outgoing_transaction_id" => disbursement.outgoing_disbursement.local_hcb_code.public_id,
              "incoming_transaction_id" => disbursement.incoming_disbursement.local_hcb_code.public_id,
              "amount_cents"            => 123_45,
              "card_grant_id"           => card_grant.public_id,
              "from"                    => serialized_event,
              "to"                      => serialized_event,
              "sender"                  => {
                "id"       => user.public_id,
                "object"   => "user",
                "name"     => "Orpheus D",
                "email"    => "orpheus@hackclub.com",
                "admin"    => false,
                "auditor"  => false,
                "avatar"   => "https://gravatar.com/avatar/stubbed",
                # Fuime: the user factory now supplies a birthday by default,
                # because Fuime treats unknown age as a minor requiring a
                # guardian. Assert against the record rather than hardcoding
                # nil, so this doesn't re-break if the default changes.
                "birthday" => user.birthday&.to_date&.iso8601,
              },
              "created_at"              => disbursement.created_at.iso8601(3)
            }
          ],
          "organization"               => serialized_event,
          "user"                       => {
            "id"      => recipient.public_id,
            "object"  => "user",
            "name"    => "recipient",
            "admin"   => false,
            "auditor" => false,
            "avatar"  => "https://gravatar.com/avatar/stubbed",
          },
          "created_at"                 => card_grant.created_at.iso8601(3)
        }
      )
    end

    it "reports validation errors" do
      user = create(:user, full_name: "Orpheus the Dinosaur", email: "orpheus@hackclub.com")
      event = create(:event, :with_positive_balance, name: "Test Event", plan_type: Event::Plan::HackClubAffiliate)
      create(:card_grant_setting, event:)
      create(:organizer_position, user:, event:)

      token = create(:api_token, user:)
      request.headers["Authorization"] = "Bearer #{token.token}"

      post(
        :create,
        params: {
          event_id: event.friendly_id,
          **card_grant_params,
          purpose: "This is a very long purpose that should exceed the 30 character limit",
        },
        as: :json
      )

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        {
          "error"    => "invalid_operation",
          "messages" => ["Purpose is too long (maximum is 30 characters)"]
        }
      )
    end

    it "handles downstream errors" do
      user = create(:user, full_name: "Orpheus the Dinosaur", email: "orpheus@hackclub.com")
      event = create(:event, :with_positive_balance, name: "Test Event", plan_type: Event::Plan::HackClubAffiliate)
      create(:card_grant_setting, event:)
      create(:organizer_position, user:, event:)

      token = create(:api_token, user:)
      request.headers["Authorization"] = "Bearer #{token.token}"

      post(
        :create,
        params: {
          event_id: event.friendly_id,
          **card_grant_params,
          amount_cents: 12_345_67,
        },
        as: :json
      )

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        {
          "error"    => "invalid_operation",
          "messages" => ["You don't have enough money to make this disbursement."]
        }
      )
    end
  end

  # Activation issues a real card to the grantee. The HTML flow has always
  # refused to do that for an unverified phone number; this endpoint did not,
  # and `CardGrantPolicy#activate?` admits any admin — so an admin could issue
  # a card to someone who never verified a number.
  describe "#activate" do
    # `admin:write` because ApiAdminContext only treats a v4 caller as an admin
    # when the token carries that scope — an admin's ordinary token gets a 403
    # from Pundit long before reaching the action.
    def activate_as_admin(card_grant)
      token = create(:api_token, user: create(:user, :make_admin), scopes: "admin:write")
      request.headers["Authorization"] = "Bearer #{token.token}"

      post(:activate, params: { id: card_grant.public_id }, as: :json)
    end

    it "refuses when the grantee has no verified phone number" do
      card_grant = create(:card_grant, event: create(:event, :with_positive_balance),
                                       user: create(:user, phone_number_verified: false))

      expect_any_instance_of(CardGrant).not_to receive(:create_stripe_card)

      activate_as_admin(card_grant)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq(
        "A verified phone number is required to activate this grant card."
      )
    end

    it "activates when the grantee's phone number is verified" do
      card_grant = create(:card_grant, event: create(:event, :with_positive_balance),
                                       user: create(:user, phone_number_verified: true))

      allow_any_instance_of(CardGrant).to receive(:create_stripe_card)

      activate_as_admin(card_grant)

      expect(response).to have_http_status(:ok)
    end
  end
end
