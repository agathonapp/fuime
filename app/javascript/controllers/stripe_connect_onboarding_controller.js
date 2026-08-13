import { Controller } from '@hotwired/stimulus'
import { loadConnectAndInitialize } from '@stripe/connect-js'
import { connectAppearance } from '../common/stripeConnectAppearance'

// Fuime: mounts Stripe's embedded Connect onboarding component.
//
// Embedded rather than a redirect to Stripe because Fuime is configured so that
// Stripe carries negative-balance liability. That configuration cannot use
// Account Links for account updates, so embedded components are required, not a
// stylistic preference.
//
// The client secret is rendered fresh by the server on each page load — Account
// Sessions are short-lived, so there is nothing worth caching here.
export default class extends Controller {
  static targets = ['container', 'fallback']
  static values = {
    publishableKey: String,
    clientSecret: String,
    returnUrl: String,
    refreshUrl: String,
  }

  async connect() {
    if (!this.publishableKeyValue || !this.clientSecretValue) {
      this.showFallback("Payment setup isn't available right now.")
      return
    }

    try {
      const instance = await loadConnectAndInitialize({
        publishableKey: this.publishableKeyValue,
        // Called both on first mount and whenever Stripe needs a new session.
        // Hitting the refresh path returns a page with a fresh secret rather
        // than surfacing an expiry error to a parent.
        fetchClientSecret: async () => {
          if (!this.usedInitialSecret) {
            this.usedInitialSecret = true
            return this.clientSecretValue
          }

          const response = await fetch(this.refreshUrlValue, {
            headers: { Accept: 'application/json' },
          })
          if (!response.ok) throw new Error('Could not refresh Stripe session')
          const body = await response.json()
          return body.client_secret
        },
        // Without an appearance, the component renders Stripe's white-card
        // defaults inside Fuime's dark UI — the first person to walk the school
        // flow described it as "not our app", which for an identity form is the
        // worst possible moment to look foreign. Shared with every other
        // embedded surface via common/stripeConnectAppearance so onboarding and
        // management cannot drift apart.
        appearance: connectAppearance(),
      })

      const onboarding = instance.create('account-onboarding')

      // Exiting the flow does NOT mean setup succeeded — it only means the form
      // was closed. The server re-asks Stripe on this path rather than trusting
      // the exit, which is the difference between showing a family a working
      // storefront and showing them a broken one.
      onboarding.setOnExit(() => {
        window.location.href = this.returnUrlValue
      })

      this.containerTarget.appendChild(onboarding)
      this.hideFallback()
    } catch (error) {
      // Deliberately not silent: a blank rectangle gives a parent no way to tell
      // "still loading" from "broken", and this flow is the one thing standing
      // between their kid and getting paid.
      console.error('[Fuime] Stripe Connect onboarding failed to load', error)
      this.showFallback(
        "Stripe's setup form couldn't load. Check that your browser isn't blocking scripts from Stripe, then reload this page."
      )
    }
  }

  hideFallback() {
    if (this.hasFallbackTarget) this.fallbackTarget.hidden = true
  }

  showFallback(message) {
    if (!this.hasFallbackTarget) return
    this.fallbackTarget.hidden = false
    this.fallbackTarget.textContent = message
  }
}
