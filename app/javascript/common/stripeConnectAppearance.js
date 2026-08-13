// Fuime: the appearance Stripe's embedded Connect components render with.
//
// Extracted so that every embedded surface — onboarding, account management, the
// notification banner, payouts — is themed by one function. When this lived
// inside the onboarding controller, the second surface to be embedded would have
// had its own copy, and the two would have drifted the first time the palette
// changed. A parent moving between "set up payments" and "manage payments"
// noticing the forms look like two different products is exactly the failure this
// prevents.
//
// Values are READ FROM THE LIVE PAGE rather than hardcoded, so the components
// follow whichever theme the user is actually in (this app ships dark and light)
// instead of a palette here that goes stale the next time the CSS changes.
export function connectAppearanceVariables() {
  const styles = getComputedStyle(document.body)
  const rootStyles = getComputedStyle(document.documentElement)
  const bodyBackground = styles.backgroundColor

  // getComputedStyle reports an unset background as fully transparent rgba,
  // which Stripe would render as a black or invisible card. Fall back rather
  // than pass it through.
  const transparent = /rgba\(\s*0,\s*0,\s*0,\s*0\s*\)/

  return {
    colorBackground: transparent.test(bodyBackground) ? '#ffffff' : bodyBackground,
    colorText: styles.color,
    // --primary is $fuime-blue from _variables.scss; the fallback is the same
    // value so a missing custom property degrades to the identical color.
    colorPrimary: rootStyles.getPropertyValue('--primary').trim() || '#2242FF',
    borderRadius: '8px',
    fontFamily: styles.fontFamily,
  }
}

export function connectAppearance() {
  return { variables: connectAppearanceVariables() }
}
