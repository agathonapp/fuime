import { Controller } from '@hotwired/stimulus'
import csrf from '../common/csrf'

const PLAID_SCRIPT_SRC =
  'https://cdn.plaid.com/link/v2/stable/link-initialize.js'

// Fuime: opens Plaid Link so an operator can connect where their money goes.
//
// ── Why the script is loaded here and not bundled ───────────────────────────
//
// Plaid does not ship the web drop-in as an npm package that can be bundled;
// `link-initialize.js` must be served from their CDN so the version tracks their
// backend. So it is injected on demand rather than on every page: this is one
// screen an operator visits roughly once, and a third-party script on every
// authenticated page load is exactly what was removed when the credentialed
// fetch to blog.hcb.hackclub.com was killed (Milestone 3).
//
// ── Why the token is fetched rather than rendered ───────────────────────────
//
// A Link token is single-use and expires in four hours. Rendering one into the
// page would mint a token on every visit including the ones where nobody clicks,
// and would hand an expired token to anyone who left the tab open — the same
// stale-secret problem stripe_connect_component_controller solves the same way.
//
// ── The exchange is a form post, not a fetch ────────────────────────────────
//
// What Link returns is exchanged server-side, and the result is a redirect with
// a flash. Posting a hidden form rather than fetching means the success and
// failure paths are ordinary Rails redirects that a person can reload, back out
// of, and read — instead of a page that has to re-render itself in JavaScript
// and has no story for what happens when that fails.
//
// Usage:
//   <div data-controller="plaid-link"
//        data-plaid-link-token-url-value="/acme/payout-method/link-token">
//     <button data-action="plaid-link#open" data-plaid-link-target="button">Connect</button>
//     <form data-plaid-link-target="form" method="post" action="/acme/payout-method">
//       <input type="hidden" name="public_token" data-plaid-link-target="publicToken">
//       <input type="hidden" name="account_id" data-plaid-link-target="accountId">
//     </form>
//     <p data-plaid-link-target="error" hidden></p>
//   </div>
export default class extends Controller {
  static targets = ['button', 'form', 'publicToken', 'accountId', 'error']
  static values = { tokenUrl: String }

  async open(event) {
    event.preventDefault()

    // Every failure below re-enables the button. A disabled button with no
    // explanation is indistinguishable from a broken page to somebody who came
    // here to get paid.
    this.setBusy(true)
    this.clearError()

    try {
      const handler = await this.buildHandler()
      handler.open()
    } catch (error) {
      this.showError(
        error.message ||
          "We couldn't open your bank just now. Please try again."
      )
      this.setBusy(false)
    }
  }

  async buildHandler() {
    const [token] = await Promise.all([
      this.fetchToken(),
      this.loadPlaidScript(),
    ])

    return window.Plaid.create({
      token,
      onSuccess: (publicToken, metadata) => this.submit(publicToken, metadata),
      onExit: error => {
        // A person closing the modal is not an error and must not be reported
        // as one — `err` is null on a deliberate exit, and only the other case
        // gets a message.
        if (error) {
          this.showError(
            error.display_message ||
              "Your bank connection didn't finish. You can try again."
          )
        }
        this.setBusy(false)
      },
    })
  }

  async fetchToken() {
    const response = await fetch(this.tokenUrlValue, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
    })

    const body = await response.json().catch(() => ({}))

    if (!response.ok) {
      throw new Error(
        body.error || "We couldn't start the bank connection just now."
      )
    }

    return body.link_token
  }

  loadPlaidScript() {
    if (window.Plaid) return Promise.resolve()

    // Reuse an in-flight load rather than appending a second <script>: a double
    // click would otherwise race two copies of the SDK onto the page.
    if (this.scriptPromise) return this.scriptPromise

    this.scriptPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script')
      script.src = PLAID_SCRIPT_SRC
      script.onload = () => resolve()
      script.onerror = () => {
        this.scriptPromise = null
        reject(
          new Error(
            "We couldn't reach your bank's connection service. Please try again."
          )
        )
      }
      document.head.appendChild(script)
    })

    return this.scriptPromise
  }

  submit(publicToken, metadata) {
    this.publicTokenTarget.value = publicToken
    // Link reports the chosen account here. The server does not trust it — it
    // checks the id against the accounts Plaid reports for the Item it just
    // exchanged — so a missing value is a fallback, not a failure.
    this.accountIdTarget.value =
      metadata?.account_id || metadata?.account?.id || ''
    this.formTarget.requestSubmit()
  }

  setBusy(busy) {
    if (!this.hasButtonTarget) return

    this.buttonTarget.disabled = busy
    this.buttonTarget.textContent = busy
      ? 'Opening your bank…'
      : this.buttonLabel
  }

  get buttonLabel() {
    return this.buttonTarget.dataset.label || 'Connect a bank account'
  }

  showError(message) {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (!this.hasErrorTarget) return

    this.errorTarget.hidden = true
  }
}
