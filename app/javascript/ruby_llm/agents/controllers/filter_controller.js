import { Controller } from "@hotwired/stimulus"

// Filter controller for live filtering of executions
//
// Usage:
//   <form data-controller="filter">
//     <select data-action="change->filter#submit">...</select>
//   </form>
//
export default class extends Controller {
  static targets = ["form"]
  static values = {
    debounce: { type: Number, default: 300 }
  }

  connect() {
    this.timeout = null
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  // Submit the form with debouncing
  submit(event) {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, this.debounceValue)
  }

  // Submit immediately without debounce
  submitNow(event) {
    this.element.requestSubmit()
  }

  // Update URL with current filter state
  updateUrl() {
    const formData = new FormData(this.element)
    const params = new URLSearchParams()

    for (const [key, value] of formData) {
      if (value) {
        params.set(key, value)
      }
    }

    const newUrl = `${window.location.pathname}?${params.toString()}`
    window.history.pushState({}, "", newUrl)
  }
}
