# frozen_string_literal: true

class Rack::Attack
  # Fuime: the real client IP, not Cloudflare's edge address.
  #
  # ── The outage this fixes (2026-08-21) ──────────────────────────────────────
  #
  # app.fuime.com is proxied through Cloudflare, with Render behind it. Rack's
  # `Request#ip` returns the LAST untrusted entry in X-Forwarded-For, and
  # Cloudflare appends its own edge address after the real client's — so `req.ip`
  # on an inbound Stripe webhook was a Cloudflare IP (104.21.x / 172.67.x). It
  # matched nothing in stripe_ips_webhooks.txt, and the blocklist below returned
  # 403 to Stripe before Fuime::WebhooksController could verify the signature.
  #
  # Every live payment therefore vanished: Stripe took the money, the webhook was
  # refused at the door, no CanonicalPendingTransaction was written, and the
  # venture's ledger stayed empty with nothing in any log to point at. The IP
  # allowlist file was correct and current the whole time — it was being compared
  # against the wrong address.
  #
  # ── It was also breaking every throttle ─────────────────────────────────────
  #
  # The same `req.ip` keys `throttle("req/ip", limit: 1000, period: 5.minutes)`
  # and the login limiters. Behind Cloudflare that is ONE bucket for the entire
  # internet, so the general limit was a site-wide ceiling rather than a per-user
  # one, and the brute-force limiters counted every visitor's attempts together.
  #
  # ── Why trusting this header is acceptable here ─────────────────────────────
  #
  # CF-Connecting-IP is set by Cloudflare and cannot be forged by a client whose
  # traffic goes through Cloudflare. It CAN be forged by anything that reaches the
  # Render origin directly, so this should be paired with restricting the origin
  # to Cloudflare's ranges — see docs/fuime/PRODUCTION_READINESS.md.
  #
  # Even unpaired it is the safer of the two failure modes for the rules below:
  # for the webhook paths the signature check is the real authentication and a
  # spoofed IP gains an attacker nothing, and for the throttles a forgeable
  # per-IP key is strictly better than the single shared bucket it replaces.
  #
  # `req.ip` on the fallback is Rack's own, and must stay that way: the
  # search-and-replace that introduced this helper rewrote every `req.ip` in the
  # file INCLUDING the one in its own body, so this method called itself and any
  # request without the header died of SystemStackError. Production survived only
  # because Cloudflare always sets the header, which meant the recursion was
  # unreachable for real traffic and reachable for everything else — health
  # checks, direct-to-origin requests, and the whole test suite.
  def self.client_ip(req)
    req.get_header("HTTP_CF_CONNECTING_IP").presence || req.ip
  end

  ### Configure Cache ###

  # If you don't want to use Rails.cache (Rack::Attack's default), then
  # configure it here.
  #
  # Note: The store is only used for throttling (not blocklisting and
  # safelisting). It must implement .increment and .write like
  # ActiveSupport::Cache::Store

  # Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Blacklist
  bad_ips = Credentials.fetch("BLOCKED_IPS")&.split(",")&.map(&:strip)
  Rack::Attack.blocklist "Block IPs from Environment Variable" do |req|
    bad_ips&.include?(Rack::Attack.client_ip(req))
  end

  # Safelist Hack Club Office(s)
  Credentials.fetch(:OFFICE_IP)&.split(",")&.map(&:strip)&.each do |office_ip|
    safelist_ip(office_ip)
  end
  safelist_ip("10.0.0.0/16")

  # Get the IP addresses of stripe as an array
  stripe_ips_webhooks = File.readlines(Rails.root.join("config/stripe_ips_webhooks.txt")).map(&:strip)
  column_ips_webhooks = File.readlines(Rails.root.join("config/column_ips_webhooks.txt")).map(&:strip)

  # Allow those IP addresses to send us as many webhooks as they like, but block all others
  safelist("always allow Stripe IPs to send webhooks") do |req|
    req.post? && stripe_ips_webhooks.include?(Rack::Attack.client_ip(req)) && req.path == "/stripe/webhook"
  end

  safelist("always allow Column IPs to send webhooks") do |req|
    req.post? && column_ips_webhooks.include?(Rack::Attack.client_ip(req)) && req.path == "/webhooks/column"
  end

  blocklist("block Stripe webhooks from non-Stripe IPs") do |req|
    next false unless req.path == "/stripe/webhook"

    !stripe_ips_webhooks.include?(Rack::Attack.client_ip(req))
  end

  blocklist("block Column webhooks from non-Column IPs") do |req|
    next false unless req.path == "/webhooks/column"

    !column_ips_webhooks.include?(Rack::Attack.client_ip(req))
  end

  # Fuime: the same treatment for Fuime's OWN Stripe endpoints.
  #
  # Upstream protects `/stripe/webhook` this way and Fuime added two more Stripe
  # endpoints (`Fuime::WebhooksController#stripe` and `#connect`) without adding
  # them here, so they were the only webhook paths in the app any IP could reach.
  #
  # Defence in depth, stated as such: signature verification in the controller is
  # the real control and it fails closed — a missing secret returns 503 rather
  # than accepting. This closes the gap that let an arbitrary host spend CPU on
  # signature checks against a payments endpoint.
  FUIME_STRIPE_WEBHOOK_PATHS = [
    "/fuime/webhooks/stripe",
    "/fuime/webhooks/stripe/connect"
  ].freeze

  safelist("always allow Stripe IPs to send Fuime webhooks") do |req|
    req.post? && stripe_ips_webhooks.include?(Rack::Attack.client_ip(req)) &&
      FUIME_STRIPE_WEBHOOK_PATHS.include?(req.path)
  end

  blocklist("block Fuime Stripe webhooks from non-Stripe IPs") do |req|
    next false unless FUIME_STRIPE_WEBHOOK_PATHS.include?(req.path)

    !stripe_ips_webhooks.include?(Rack::Attack.client_ip(req))
  end

  ### Throttle Spammy Clients ###

  # If any single client IP is making tons of requests, then they're
  # probably malicious or a poorly-configured scraper. Either way, they
  # don't deserve to hog all of the app server's CPU. Cut them off!
  #
  # Note: If you're serving assets through rack, those requests may be
  # counted by rack-attack and this throttle may be activated too
  # quickly. If so, enable the condition to exclude them from tracking.

  # Throttle all requests by IP (60rpm)
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:req/ip:#{req.ip}"
  throttle("req/ip", limit: 1000, period: 5.minutes) do |req|
    next if req.path.start_with?("/assets") ||
            req.path.start_with?("/admin") ||
            req.path.start_with?("/stats")

    Rack::Attack.client_ip(req)
  end

  ### Prevent Brute-Force Login Attacks ###

  # The most common brute-force login attack is a brute-force password
  # attack where an attacker simply tries a large number of emails and
  # passwords to see if any credentials match.
  #
  # Another common method of attack is to use a swarm of computers with
  # different IPs to try brute-forcing a password for a specific account.

  # Paths that initiate a Login flow. /logins is the canonical entry point;
  # /first creates a Login on the existing-user branch of the FIRST signup
  # form. Both should share the same per-IP and per-email throttles.
  LOGIN_INITIATION_PATHS = ["/logins", "/first"].freeze

  # Throttle POST requests to login-initiation paths by IP address
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:logins/ip:#{req.ip}"
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if LOGIN_INITIATION_PATHS.include?(req.path) && req.post?
      Rack::Attack.client_ip(req)
    end
  end

  # Throttle POST requests to login-initiation paths by email param
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:logins/email:#{normalized_email}"
  #
  # Note: This creates a problem where a malicious user could intentionally
  # throttle logins for another user and force their login requests to be
  # denied, but that's not very common and shouldn't happen to you. (Knock
  # on wood!)
  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if LOGIN_INITIATION_PATHS.include?(req.path) && req.post?
      # /logins uses params[:email]; /first uses params[:user][:email].
      raw = req.params["email"] || req.params.dig("user", "email")
      raw.to_s.downcase.gsub(/\s+/, "").presence
    end
  end

  # Throttle POSTs to per-Login factor-trigger endpoints (POST /logins/:id/email
  # and POST /logins/:id/sms). These dispatch real emails / Twilio SMS, so a
  # single Login row can become a bombing channel without rate limits. The
  # first cap is per IP (cross-victim flood); the second is per Login hashid
  # (sustained flood against one victim).
  LOGIN_FACTOR_TRIGGER_PATH = /\A\/logins\/[^\/]+\/(?:email|sms)\z/

  throttle("logins/factor-trigger/ip", limit: 5, period: 20.seconds) do |req|
    if req.post? && LOGIN_FACTOR_TRIGGER_PATH.match?(req.path)
      Rack::Attack.client_ip(req)
    end
  end

  throttle("logins/factor-trigger/login", limit: 3, period: 1.minute) do |req|
    if req.post? && (m = req.path.match(/\A\/logins\/(?<hashid>[^\/]+)\/(?:email|sms)\z/))
      m[:hashid]
    end
  end

  # Throttle POST requests to SMS verification by IP address
  throttle("sms_verify/ip", limit: 5, period: 8.hours) do |req|
    if req.path == "/users/start_sms_auth_verification" && req.post?
      Rack::Attack.client_ip(req)
    end
  end

  # Throttle POST /first/request_org_invite to 2 per day per signed-in user.
  # Each request creates an OrganizerPositionInvite::Request and dispatches a
  # notification email to event managers; the in-controller "no pending
  # request" guard only blocks identical re-submits, leaving room for
  # request → manager-denial → request loops to spam managers. Keyed on the
  # encrypted session_token cookie (stable per session) — unauthenticated
  # requests are rejected at the controller and aren't counted.
  throttle("first/request_org_invite/user", limit: 2, period: 1.day) do |req|
    if req.path == "/first/request_org_invite" && req.post?
      req.cookies["session_token"]
    end
  end

  ### Custom Throttle Response ###

  # By default, Rack::Attack returns an HTTP 429 for throttled responses,
  # which is just fine.
  #
  # If you want to return 503 so that the attacker might be fooled into
  # believing that they've successfully broken your app (or you just want to
  # customize the response), then uncomment these lines.
  # self.throttled_response = lambda do |env|
  #  [ 503,  # status
  #    {},   # headers
  #    ['']] # body
  # end
  #
  # Throttle POST requests to /donations/start/hq by IP address
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:logins/ip:#{req.ip}"
  throttle("donations/start/ip", limit: 100, period: 20.seconds) do |req|
    if req.path.start_with?("/donations/start")
      Rack::Attack.client_ip(req)
    end
  end

  throttle("donations/hq/ip", limit: 100, period: 20.seconds) do |req|
    if req.path.start_with?("/donations/hq")
      Rack::Attack.client_ip(req)
    end
  end

  # Reading an organization's transactions runs the transaction engines, which
  # cost seconds per request, and a transparent organization can be read without
  # signing in. The page and its Turbo frame are each requested directly, so both
  # need covering.
  ledger_path = %r{
    \A/
    (?!admin/)                    # `req/ip` above exempts /admin
    [^/]+/                        # organization slug
    (transactions_list | transactions | ledger)
    (\.[^/]*)?                    # `(.:format)` reaches the same action
    /?\z
  }x

  # Presence only: the cookie is encrypted, and verifying it would mean a database
  # lookup ahead of Rails. A forged value falls through to the wider throttle
  # below, which is why that one exists.
  #
  # `Rack::Request#cookies` is string-keyed; a symbol reads as nil every time and
  # throttles signed-in organizers too.
  throttle("transparency/ledger/ip", limit: 25, period: 1.minute) do |req|
    Rack::Attack.client_ip(req) if req.path.match?(ledger_path) && req.cookies["session_token"].nil?
  end

  # Set far above what clicking through pages reaches, so it only catches
  # automation sending an unverified `session_token`.
  throttle("ledger/ip", limit: 100, period: 1.minute) do |req|
    Rack::Attack.client_ip(req) if req.path.match?(ledger_path)
  end

  # Lockout IP addresses that are hammering your donation page.
  # After 5 requests in 30 seconds, block all requests from that IP for 3 hours.
  blocklist("allow2ban donation scrapers") do |req|
    # `filter` returns false value if request is to your donation page (but still
    # increments the count) so request below the limit are not blocked until
    # they hit the limit.  At that point, filter will return true and block.
    Rack::Attack::Allow2Ban.filter(Rack::Attack.client_ip(req), maxretry: 100, findtime: 30.seconds, bantime: 3.minutes) do
      # The count for the IP is incremented if the return value is truthy.
      req.path.start_with?("/donations/start", "/donations/hq")
    end
  end

  # ── Fuime: the three endpoints that cost money or send mail ────────────────

  # Fuime: starting a checkout.
  #
  # Public, unauthenticated, and every request creates a Stripe PaymentIntent. Two
  # abuses it stops: card testing (a stranger cycling stolen numbers through a
  # teenager's storefront, whose decline rate lands on the account the charge is
  # on), and simply running up API volume against Fuime's Stripe account.
  #
  # 20 in 5 minutes is far above a real buyer — who starts one checkout, maybe
  # retries once — and low enough that automation hits it in seconds.
  throttle("fuime/checkout/ip", limit: 20, period: 5.minutes) do |req|
    Rack::Attack.client_ip(req) if req.post? && req.path.match?(/\A\/b\/[^\/]+\/pay\z/)
  end

  # Fuime: inviting a guardian.
  #
  # `GuardianshipsController#create` creates a `User` row for whatever address is
  # typed and sends it mail, so without a cap one signed-in teen is a mail cannon
  # and a way to squat accounts on addresses whose owners have not registered yet.
  #
  # Keyed on the session cookie rather than the IP, following the
  # `first/request_org_invite` throttle above: a household or a school shares an
  # IP, and rate-limiting a classroom because one student is inviting a parent is
  # the wrong failure. Unauthenticated requests never reach the action.
  #
  # 10 a day is generous for a real family — two guardians, a couple of typos, a
  # resend — and ends the bombing channel.
  throttle("fuime/guardian_invite/user", limit: 10, period: 1.day) do |req|
    if req.post? && req.path == "/guardianships"
      req.cookies["session_token"]
    end
  end

  # Fuime: the venture API.
  #
  # Not brute-force protection — keys are 32 bytes of SecureRandom and guessing is
  # not the threat. This is the ceiling that makes a LEAKED key's abuse visible and
  # bounded: a stolen key minting payment links in a loop, or an agent stuck in a
  # retry. `Fuime::ApiKey::MAX_LIVE_LINKS_PER_KEY` bounds the total; this bounds
  # the rate.
  #
  # Keyed on the presented credential, so one compromised key cannot throttle
  # every other venture's integration. Hashed because throttle keys reach the
  # cache and, on some stores, logs — a rate-limit key is not a place to put a
  # live secret in plaintext.
  throttle("fuime/api/key", limit: 120, period: 1.minute) do |req|
    if req.path.start_with?("/api/fuime/v1/")
      presented = req.get_header("HTTP_AUTHORIZATION").to_s.strip
      presented = presented.sub(/\Abearer\s+/i, "")
      Digest::SHA256.hexdigest(presented) if presented.present?
    end
  end

end

# Fuime: on in staging too.
#
# This was production-only, which meant the staging environment — the one place
# these rules get exercised before they matter — ran with no throttling at all, so
# a misconfigured limit was only ever discovered in production. Staging is also
# internet-reachable and holds test-mode Stripe credentials.
#
# Still off in development and test: a throttle that fires mid-suite is a flaky
# spec, and localhost does not need protecting from itself.
Rack::Attack.enabled = Rails.env.production? || Rails.env.staging?
