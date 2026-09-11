import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static values = {
    url: String,
    title: String,
  }

  async share(event) {
    event.preventDefault()

    if (navigator.share) {
      try {
        await navigator.share({
          title: this.titleValue,
          url: this.urlValue,
        })
        return
      } catch (error) {
        if (error.name === 'AbortError') return
      }
    }

    if (navigator.clipboard) {
      await navigator.clipboard.writeText(this.urlValue)
      const button = event.currentTarget
      const previous = button.innerText
      button.innerText = 'Copied link'
      setTimeout(() => {
        button.innerText = previous
      }, 1500)
    }
  }
}
