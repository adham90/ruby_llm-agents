import { Controller } from "@hotwired/stimulus"

// Auto-refresh controller for dashboard with toggle support
//
// Usage:
//   <div data-controller="refresh"
//        data-refresh-interval-value="30000"
//        data-refresh-enabled-value="false">
//     <button data-action="refresh#toggle" data-refresh-target="button">
//       Live Poll: Off
//     </button>
//   </div>
//
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 30000 },
    enabled: { type: Boolean, default: false }
  }

  static targets = ["button", "indicator"]

  connect() {
    this.updateUI()
    if (this.enabledValue) {
      this.startRefresh()
    }
  }

  disconnect() {
    this.stopRefresh()
  }

  toggle() {
    this.enabledValue = !this.enabledValue

    if (this.enabledValue) {
      this.startRefresh()
      this.refresh() // Immediate refresh when enabled
    } else {
      this.stopRefresh()
    }

    this.updateUI()
  }

  startRefresh() {
    if (this.intervalValue > 0 && !this.timer) {
      this.timer = setInterval(() => this.refresh(), this.intervalValue)
    }
  }

  stopRefresh() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  refresh() {
    const frame = this.element.closest("turbo-frame") ||
                  this.element.querySelector("turbo-frame")

    if (frame && typeof frame.reload === "function") {
      frame.reload()
    }
  }

  updateUI() {
    if (this.hasButtonTarget) {
      if (this.enabledValue) {
        this.buttonTarget.classList.remove("bg-gray-100", "text-gray-600")
        this.buttonTarget.classList.add("bg-green-100", "text-green-700")
      } else {
        this.buttonTarget.classList.remove("bg-green-100", "text-green-700")
        this.buttonTarget.classList.add("bg-gray-100", "text-gray-600")
      }
    }

    if (this.hasIndicatorTarget) {
      this.indicatorTarget.textContent = this.enabledValue ? "On" : "Off"
    }
  }
}
