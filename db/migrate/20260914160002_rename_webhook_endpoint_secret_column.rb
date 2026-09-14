# frozen_string_literal: true

# Fuime: `encrypted_secret` → `secret_ciphertext`.
#
# Lockbox's `has_encrypted :secret` reads and writes `secret_ciphertext`; the
# column created in 20260914160000 was named for the wrong convention, so the
# model had no `secret=` writer at all and every create raised NoMethodError.
# Fuime::ApiKey has had it right all along (`token_ciphertext`).
#
# Rule 5 — new migration rather than editing the one that already ran.
# `safety_assured` for the same reasons as 20260914150000, which are stronger
# here: the table was created minutes ago, has never been deployed, and holds no
# rows in any environment.
class RenameWebhookEndpointSecretColumn < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      rename_column :fuime_webhook_endpoints, :encrypted_secret, :secret_ciphertext
    end
  end

end
