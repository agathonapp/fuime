# frozen_string_literal: true

# Fuime: fail loudly at boot when outbound email is misconfigured.
#
# Login codes are delivered over SMTP, so a missing SMTP password doesn't just
# break email — it breaks signing in entirely. Without this check the only
# symptom is an Errno::ECONNREFUSED deep in a request, which is hard to trace
# back to an unset environment variable.
#
# This warns rather than raises: a running app that can't send mail is more
# useful than one that refuses to boot, and Render restarts on a crash loop.
Rails.application.config.after_initialize do
  next unless Rails.env.production? || Rails.env.staging?
  next unless Rails.application.config.action_mailer.delivery_method == :smtp

  settings = Rails.application.config.action_mailer.smtp_settings || {}
  missing = settings.slice(:address, :port, :user_name, :password)
                    .select { |_k, v| v.blank? }
                    .keys

  if missing.any?
    Rails.logger.error(<<~MSG)
      [Fuime] SMTP is not fully configured — missing: #{missing.join(', ')}.
      Outbound email AND email login codes will fail until these are set.
      Set SMTP__PASSWORD (your Resend API key) in the Render dashboard;
      the remaining SMTP__* values have defaults in config/application.rb.
    MSG
  end
end
