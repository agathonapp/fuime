import { Controller } from '@hotwired/stimulus'

// Fuime: the family setup wizard's motion.
//
// Three things, all cosmetic and all optional: the progress bar animates from
// where it was rather than jumping, the panel enters from the side you are
// travelling, and the step you just finished draws its check.
//
// "Optional" is load-bearing. Every screen is a server-rendered form that
// works with no JavaScript at all: the bar renders at its final width inline,
// the rail renders its state in classes, and nothing here ever calls
// preventDefault or delays a navigation. If this controller throws, the wizard
// still works.
//
// Previous progress lives in sessionStorage rather than the server session so
// that a back-button render — which Turbo may serve from cache without a
// request — still animates correctly, and so that nothing about presentation
// occupies a cookie.
export default class extends Controller {
  static targets = ['panel', 'fill', 'step']
  static values = { key: String, progress: Number, step: Number }

  connect() {
    this.reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches

    const prev = this.readNumber('progress')
    const prevStep = this.readNumber('step')
    const back = Number.isFinite(prev) && prev > this.progressValue

    if (
      this.hasFillTarget &&
      !this.reduced &&
      Number.isFinite(prev) &&
      prev !== this.progressValue
    ) {
      this.fillTarget.style.width = `${prev}%`
      // Two frames: one to let the browser take the start width, one to change
      // it. A single frame is coalesced into the initial paint and the
      // transition never runs.
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          this.fillTarget.style.width = `${this.progressValue}%`
        })
      })
    }

    if (this.hasPanelTarget && !this.reduced) {
      this.panelTarget.classList.add(
        back ? 'wizard-panel--enter-back' : 'wizard-panel--enter'
      )
    }

    // Only the step that was just completed draws. Redrawing every earlier
    // check on every screen reads as a glitch rather than as progress.
    if (
      !this.reduced &&
      Number.isFinite(prevStep) &&
      prevStep === this.stepValue - 1
    ) {
      this.stepTargets[prevStep]?.classList.add('is-drawing')
    }

    this.write('progress', this.progressValue)
    this.write('step', this.stepValue)

    // Turbo caches the page as it stands for the back button. Without this the
    // cached copy keeps a mid-exit class and flashes half-faded on return.
    this.beforeCache = () => {
      this.panelTarget?.classList.remove(
        'wizard-panel--exit',
        'wizard-panel--exit-back',
        'wizard-panel--enter',
        'wizard-panel--enter-back'
      )
    }
    document.addEventListener('turbo:before-cache', this.beforeCache)
  }

  disconnect() {
    document.removeEventListener('turbo:before-cache', this.beforeCache)
  }

  // data-action="turbo:submit-start->wizard#leave" on the step form.
  leave() {
    if (!this.reduced) this.panelTarget?.classList.add('wizard-panel--exit')
  }

  // data-action="click->wizard#leaveBack" on a Back link.
  leaveBack() {
    if (!this.reduced)
      this.panelTarget?.classList.add('wizard-panel--exit-back')
  }

  storageKey(name) {
    return `fuime.wizard.${this.keyValue}.${name}`
  }

  readNumber(name) {
    try {
      const raw = sessionStorage.getItem(this.storageKey(name))
      return raw === null ? NaN : Number(raw)
    } catch {
      return NaN
    }
  }

  write(name, value) {
    try {
      sessionStorage.setItem(this.storageKey(name), String(value))
    } catch {
      /* private browsing, storage disabled — motion is optional */
    }
  }
}
