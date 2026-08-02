import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static targets = ['badge']

  connect() {
    this.updateBadge()
  }

  // Disabled for Fuime.
  //
  // This issued a credentialed cross-origin fetch to
  // blog.hcb.hackclub.com/api/unreads on every page load — Hack Club's
  // changelog service, contacted with `credentials: 'include'` from a Fuime
  // user's browser (Prime Directive 4). Fuime has no changelog to count, so
  // the badge stays hidden rather than being repointed.
  //
  // The widget that hosts this badge is not rendered (see
  // application/_blog_widget.html.erb); this is kept so re-enabling it is one
  // place, not two.
  async updateBadge() {}
}
