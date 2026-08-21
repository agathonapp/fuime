# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors
#
# Fuime: the leftover HCB block allowlisted hackclub.com / bank.engineering /
# hcb-engr.hackclub.dev for credentialed `/api/current_user`. The second block
# used `domains.each`, which returns the array (always truthy), so every Origin
# was allowed — including on `resource "*"`.
#
# Origins are Fuime only (`app.fuime.com`, `fuime.com`, localhost in
# development). `resource "*"` is gone. Cookies stay on `/api/current_user`,
# which is the one API that reads the login session.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins do |source, _env|
      Fuime::RequestBoundary.allowed_cors_origin?(source)
    end

    # Session cookie: ApiController#the_current_user is the only API that
    # answers from the signed-in session rather than a bearer token.
    resource "/api/current_user",
             methods: %i[get options],
             credentials: true

    # Token-authenticated API (v3 / v4 / fuime). No cookies.
    resource "/api/*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             credentials: false,
             expose: ["X-Next-Page", "X-Offset", "X-Page", "X-Per-Page", "X-Prev-Page", "X-Request-Id", "X-Runtime", "X-Total", "X-Total-Pages"]
  end
end
