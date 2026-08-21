import React, { useEffect, useState } from 'react'
import PropTypes from 'prop-types'
import TourStep from './TourStep'
import csrf from '../../common/csrf'

// Fuime: the welcome tour, rewritten from HCB's.
//
// What it used to say, on a platform where none of it is true: issue a virtual
// *HCB* card, share your *donation form*, get free newsletter tools and
// stickers, and — worst of the four — "it's like multiplayer banking!", which is
// the exact vocabulary CLAUDE.md L5 forbids while no partner bank exists.
//
// Three of its four steps also pointed at nav items that no longer render.
// Donations and Perks are disabled for Fuime (Milestone 5) and `invite` was
// never a `data-tour-step` anywhere, so those steps attached to nothing and the
// bubble floated loose in the corner. See the filter below, which is what stops
// that happening again.
//
// The order is the order a founder actually needs: say what you sell, watch the
// money arrive, learn how to get it out, and know what the tax side is doing.
const tours = {
  welcome(options) {
    const steps = []

    const isMobile = window.matchMedia('(max-width: 56em)').matches

    if (options.demo) {
      steps.push({
        attachTo: 'playground_mode',
        text: "You're in demo mode — nothing here moves real money, so try anything you like.",
        placement: 'bottom',
      })
      return steps
    }

    steps.push({
      attachTo: 'offers',
      text: 'Start here: list what you sell and set your price. Fuime never picks the number for you.',
      placement: isMobile ? 'bottom' : 'right',
      strategy: 'fixed',
    })

    steps.push({
      attachTo: 'balance',
      text: 'Money from your sales lands here, with a receipt on every transaction.',
      placement: isMobile ? 'bottom' : 'right',
    })

    steps.push({
      attachTo: 'payouts',
      text: "When you've earned something, this is how it reaches your family's account. A parent or guardian approves it.",
      placement: isMobile ? 'top' : 'right',
      strategy: 'fixed',
    })

    steps.push({
      attachTo: 'taxes',
      text: 'We keep a running total of what you have earned, so nothing about tax season is a surprise.',
      placement: isMobile ? 'top' : 'right',
      strategy: 'fixed',
    })

    steps.push({
      attachTo: 'learn',
      text: 'Never run a business before? Ten starter templates and seven short lessons on how the money works.',
      placement: isMobile ? 'top' : 'right',
      strategy: 'fixed',
    })

    if (options.initial) {
      steps.push({
        attachTo: 'team',
        text: 'Running this with someone else? Invite them here.',
        placement: isMobile ? 'top' : 'right',
        strategy: 'fixed',
      })
    }

    return steps
  },
}

// Drop any step whose target is not on the page.
//
// Nav items come and go by feature flag and by policy — Payments and Payout
// account are mutually exclusive on `merchant_of_record?`, Cards is off whenever
// Stripe is live, Taxes and Payouts are policy-gated — so a static step list
// cannot know what a given founder is looking at. Without this, a hidden target
// means `document.querySelector` returns null, floating-ui gets no reference,
// and the bubble renders unanchored in the corner. That is precisely how the
// HCB tour broke: it kept pointing at Donations and Perks after both were
// disabled, and nothing failed loudly enough for anyone to notice.
function onlyVisible(steps) {
  return steps.filter(step =>
    document.querySelector(`[data-tour-step='${step.attachTo}']`)
  )
}

function TourOverlay(props) {
  const [currentStep, setCurrentStep] = useState(props.step)

  // Filtered once at mount and again after, deliberately. The org nav is
  // server-rendered so it is normally in the DOM before this mounts, but this
  // component sits near the top of the layout — if it ever mounts first, the
  // lazy initialiser would find no targets and filter every step away, turning
  // a cosmetic race into "the tour does nothing". The effect re-runs the filter
  // once mounting is finished, which cannot be too early.
  const [tour, setTour] = useState(() =>
    props.tour ? onlyVisible(tours[props.tour](props.options)) : null
  )

  useEffect(() => {
    if (props.tour) setTour(onlyVisible(tours[props.tour](props.options)))
  }, [props.tour])

  useEffect(() => {
    ;(async () => {
      if (props.tour && currentStep < (tour?.length ?? 0)) {
        await fetch(`/tours/${props.id}/set_step`, {
          method: 'POST',
          headers: {
            'X-CSRF-Token': csrf(),
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ step: currentStep }),
        })
      }
    })()
  }, [currentStep])

  return (
    <div>
      {tour &&
        tour.map((step, index) => (
          <TourStep
            key={index}
            text={step.text}
            attachTo={`[data-tour-step='${step.attachTo}']`}
            placement={step.placement ?? 'right'}
            strategy={step.strategy}
            last={index == tour.length - 1}
            visible={index == currentStep}
            stepIndex={index}
            stepCount={tour.length}
            tourId={props.id}
            onNext={() => {
              if (currentStep + 1 >= tour.length) {
                fetch(`/tours/${props.id}/mark_complete`, {
                  method: 'POST',
                  headers: {
                    'X-CSRF-Token': csrf(),
                  },
                })
              }

              setCurrentStep(currentStep + 1)
            }}
            onSkip={() => {
              setCurrentStep(null)

              fetch(`/tours/${props.id}/mark_complete`, {
                method: 'POST',
                headers: {
                  'X-CSRF-Token': csrf(),
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({ cancelled: true }),
              })
            }}
          />
        ))}

      {props.backToTour && (
        <a
          href={props.backToTour}
          className="flex items-center text-decoration-none card back-to-tour"
        >
          Continue tour <span className="ml1 back-to-tour__arrow">→</span>
        </a>
      )}
    </div>
  )
}

TourOverlay.propTypes = {
  step: PropTypes.number,
  id: PropTypes.number,
  options: PropTypes.object,
  tour: PropTypes.string,
  backToTour: PropTypes.string,
}

export default TourOverlay
