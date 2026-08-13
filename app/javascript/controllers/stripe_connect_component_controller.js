import { Controller } from '@hotwired/stimulus'
import { loadConnectAndInitialize } from '@stripe/connect-js'
import { connectAppearance } from '../common/stripeConnectAppearance'

// Fuime: mounts one or more Stripe embedded Connect components on a page.
//
// The sibling of stripe_connect_onboarding_controller. That one drives a single
// full-page form with an exit callback; this one is the general case — an
// arbitrary set of components rendered into a page Fuime owns, so that a parent
// can manage the money rails without ever opening a Stripe Dashboard.
//
// ── Why one controller instance rather than one per component ────────────────
//
// `loadConnectAndInitialize` returns a ConnectInstance that holds the Account
// Session. Every component created from the SAME instance shares that session
// and its refresh callback. Instantiating one per component would mint a
// separate Account Session per box on the page — several API calls on every
// render, several independently-expiring secrets, and Stripe's own guidance is
// explicitly against it. So this controller wraps a region of the page and each
// mount target inside it names the component it wants.
//
// Usage:
//   <div data-controller="stripe-connect-component"
//        data-stripe-connect-component-publishable-key-value="pk_test_…"
//        data-stripe-connect-component-session-url-value="/acme/payments/session">
//     <div data-stripe-connect-component-target="mount" data-component="notification-banner"></div>
//     <div data-stripe-connect-component-target="mount" data-component="account-management"></div>
//   </div>
//
// The client secret is ALWAYS fetched from `sessionUrl` rather than rendered
// into the page. Onboarding renders one inline because it is a single-shot form
// where saving a round trip matters; a management page is long-lived and its
// secret would expire while the parent reads it, so there is nothing to gain and
// a stale-secret error to lose.
export default class extends Controller {
  static targets = ['mount', 'fallback']
  static values = {
    publishableKey: String,
    sessionUrl: String,
  }

  async connect() {
    if (!this.publishableKeyValue || !this.sessionUrlValue) {
      this.showFallback("Payment tools aren't available right now.")
      return
    }

    try {
      const instance = await loadConnectAndInitialize({
        publishableKey: this.publishableKeyValue,
        fetchClientSecret: () => this.fetchClientSecret(),
        appearance: connectAppearance(),
      })

      this.mountTargets.forEach((target) => this.mountInto(instance, target))
      this.hideFallback()
    } catch (error) {
      // Never fail silently. A blank rectangle on the page a parent was sent to
      // in order to fix a payments problem is indistinguishable from the problem
      // itself, and they have no way to tell "still loading" from "broken".
      console.error('[Fuime] Stripe Connect components failed to load', error)
      this.showFallback(
        "Stripe's tools couldn't load. Check that your browser isn't blocking scripts from Stripe, then reload this page."
      )
    }
  }

  async fetchClientSecret() {
    const response = await fetch(this.sessionUrlValue, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    })
    if (!response.ok) throw new Error('Could not start a Stripe session')
    const body = await response.json()
    if (!body.client_secret) throw new Error('Stripe session had no client secret')
    return body.client_secret
  }

  mountInto(instance, target) {
    const name = target.dataset.component
    if (!name) return

    const component = instance.create(name)

    // The notification banner renders nothing when there is nothing to say, but
    // the surrounding markup (heading, spacing, border) would still be there —
    // a titled empty box reads as a broken widget. Collapse the whole region
    // until Stripe tells us it has something.
    if (name === 'notification-banner' && component.setOnNotificationsChange) {
      target.hidden = true
      component.setOnNotificationsChange(({ total }) => {
        target.hidden = total === 0
      })
    }

    target.appendChild(component)
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
