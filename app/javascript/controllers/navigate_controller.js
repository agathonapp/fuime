import { Controller } from '@hotwired/stimulus'

// Fuime: leave for another origin as soon as this element is on the page.
//
// For answering a Turbo form submission, where a redirect to another origin
// cannot work: Turbo follows redirects with fetch, the other origin sends no
// CORS headers, and Turbo's only response to the failed fetch is a
// console.error, so the visitor sees nothing happen. Rendering a page that
// carries this controller sends them on instead. `replace` so Back returns to
// the form rather than to this page.
export default class extends Controller {
  static get values() {
    return { url: String }
  }

  connect() {
    window.location.replace(this.urlValue)
  }
}
