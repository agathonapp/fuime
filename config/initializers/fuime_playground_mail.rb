# frozen_string_literal: true

# Fuime: drop any mail whose recipients are all demo personas.
#
# The playground lives on the production deploy with live Stripe keys, and the
# family setup wizard sends real mail — a parent naming a teen enqueues a join
# link. See Fuime::PlaygroundMailInterceptor.
#
# `on_load(:action_mailer)` rather than `to_prepare`: the hook runs once, in
# the context of ActionMailer::Base, and by the time it does the autoloader can
# resolve the interceptor. Registering inside `to_prepare` would add a second
# copy on every code reload in development, and ActionMailer exposes no list to
# check against (`delivery_interceptors` does not exist).
ActiveSupport.on_load(:action_mailer) do
  register_interceptor(::Fuime::PlaygroundMailInterceptor)
end
