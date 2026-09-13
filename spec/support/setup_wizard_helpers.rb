# frozen_string_literal: true

# Fuime: the real login dance, for request specs about the setup wizard.
#
# Copied from spec/requests/family_signup_flow_spec.rb rather than reached into:
# these specs exist to prove the wizard works over real HTTP from a cold start,
# and a session helper that fabricates what the controller would have built is
# the one shortcut that would hide the bugs they are looking for.
module SetupWizardHelpers
  def login_as!(email, return_to: nil)
    post logins_path, params: { email:, login: { purpose: "", return_to: } }
    login = Login.order(:id).last
    expect(login).to be_present,
                     "POST /logins created no Login: status=#{response.status} flash=#{flash.to_hash.inspect}"

    post email_login_path(login)
    code = LoginCode.active.where(user: login.user).order(:id).last
    expect(code).to be_present, "no login code was issued for #{email}"

    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user: login.user)).to exist, "login did not produce a session"
    login.user
  end

  def logout!
    delete logout_users_path
  end

  # The rendered page as a reader sees it.
  #
  # ERB escapes an apostrophe to `&#39;`, so `include("You're in")` against a
  # raw body is a false negative on every sentence Fuime's copy actually uses.
  # Every copy assertion in the setup specs goes through here.
  def page_text(body = response.body)
    CGI.unescapeHTML(body)
  end
end

RSpec.configure do |config|
  config.include SetupWizardHelpers, type: :request
end
