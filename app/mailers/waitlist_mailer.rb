# frozen_string_literal: true

# Fuime: the "you're in" email the marketing site has been promising.
#
# Sent only when an admin admits an address from /admin/waitlist — never on
# the public capture POST. Reply-To is a real inbox for the same reason the
# guardian invite is: a no-reply From with no Reply-To looks like a blast.
class WaitlistMailer < ApplicationMailer
  def invite(user:, token:, cohort: nil)
    @user = user
    @login_url = waitlist_invite_url(token)
    @login_page_url = auth_users_url(email: user.email, signup: "true")
    @cohort = cohort
    @support_email = OPERATIONS_EMAIL

    mail(
      to: user.email,
      reply_to: OPERATIONS_EMAIL,
      subject: "You're in — log in to Fuime"
    ) do |format|
      format.html
      format.text
    end
  end

end
