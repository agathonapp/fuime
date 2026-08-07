# frozen_string_literal: true

# Fuime: send every request to the canonical host.
#
# fuime.com is the product's real address. The Render hostname
# (fuime-web.onrender.com) stays resolvable — Render owns that DNS and we
# can't switch it off — so instead of serving the app there we 301 to the
# canonical host. That keeps one address in search results, one origin for
# cookies and WebAuthn, and stops the old URL from working as a second
# front door.
#
# Runs as middleware rather than a controller filter so it also covers
# routes that skip ApplicationController's callbacks.
#
# Deliberately NOT redirected:
#   * the health check — Render probes it on the internal hostname, and a
#     redirect there would fail the check and take the service down.
#   * Stripe webhooks — a 301 on a POST can drop the body, and Stripe's
#     signature is computed over the original request. The endpoint verifies
#     its own signature, so leaving it reachable is safe.
class CanonicalHost
  # Paths that must answer on any hostname.
  EXEMPT_PATHS = [
    "/up",                      # Render health check
    "/fuime/webhooks/stripe",   # Stripe webhook receiver
  ].freeze

  def initialize(app, canonical_host: nil)
    @app = app
    @canonical_host = canonical_host
  end

  def call(env)
    host = @canonical_host
    return @app.call(env) if host.blank?

    request = Rack::Request.new(env)
    return @app.call(env) if request.host == host
    return @app.call(env) if exempt?(request.path)

    # Preserve the path and query string so bookmarked and emailed links
    # land where they were pointing.
    target = URI::HTTPS.build(
      host:,
      path: request.path,
      query: request.query_string.presence
    ).to_s

    [301, { "location" => target, "content-type" => "text/html", "cache-control" => "no-cache" },
     ["<html><body>Moved to <a href=\"#{target}\">#{target}</a></body></html>"]]
  end

  private

  def exempt?(path)
    EXEMPT_PATHS.any? { |p| path == p || path.start_with?("#{p}/") }
  end

end
