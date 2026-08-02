# Mint real User::Session rows and print the *encrypted* cookie value for each,
# so an external crawler can hit the app as a genuinely signed-in user.
emails = %w[admin@bank.engineering teen@fuime.test guardian@fuime.test adult@fuime.test noguardian@fuime.test]

# A fresh jar per user: one shared jar reuses the same @set_cookies slot, so
# every line would carry the last user's ciphertext.
def fresh_jar
  req = ActionDispatch::Request.new(Rails.application.env_config.deep_dup.merge(
    "HTTP_HOST" => "localhost:3000", "rack.input" => StringIO.new
  ))
  ActionDispatch::Cookies::CookieJar.build(req, {})
end

emails.each do |email|
  jar = fresh_jar
  u = User.find_by(email:)
  next puts("MISSING\t#{email}") unless u

  s = User::Session.create!(
    user: u,
    verified: true,
    expiration_at: 30.days.from_now,
    session_token: SecureRandom.urlsafe_base64(32),
    fingerprint: "crash-test",
    device_info: "crash-test", os_info: "crash-test", timezone: "UTC",
    ip: "127.0.0.1", last_seen_at: Time.now
  )

  jar.encrypted[:session_token] = { value: s.session_token }
  raw = jar.instance_variable_get(:@set_cookies)["session_token"][:value]
  puts "COOKIE\t#{email}\t#{raw}"
end
