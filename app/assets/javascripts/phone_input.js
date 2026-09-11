;(() => {
  const phoneInputField = document.querySelector('#phone_raw')
  // Only the settings page renders #phone_raw; the signup form stopped asking
  // for a phone number (ONBOARDING_PLAN A2). Nothing to wire up without it.
  if (!phoneInputField) return
  const phoneInput = window.intlTelInput(phoneInputField, {
    initialCountry: 'us',
    preferredCountries: ['us', 'in', 'ca', 'sg', 'au', 'gb'],
    utilsScript:
      'https://cdnjs.cloudflare.com/ajax/libs/intl-tel-input/17.0.8/js/utils.js'
  })
  const callback = () => {
    document.getElementById('phone_number').value = phoneInput.getNumber()
    return true
  }

  window.onsubmit = callback
  phoneInputField.onblur = callback
})()
