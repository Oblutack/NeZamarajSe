// app/javascript/controllers/hint_controller.js
import { Controller } from "@hotwired/stimulus"

// Small dismissible inline help tip - not a modal, not a blocking product
// tour. Each instance carries its own `id` value, used as the localStorage
// key, so dismissing one tip doesn't affect any other and stays dismissed
// across visits (this is a client-side "don't show me this again", not
// server/account state). Same pattern as theme_controller.js's use of
// localStorage. `resetAll` powers the "Show tips again" toggle in Job
// Alerts settings, which doesn't need an `id` of its own.
export default class extends Controller {
  static values = { id: String }
  static targets = ["confirmation"]

  connect() {
    if (this.idValue && this.dismissed) this.element.hidden = true
  }

  dismiss() {
    localStorage.setItem(this.storageKey, "1")
    this.element.hidden = true
  }

  resetAll() {
    Object.keys(localStorage)
      .filter((key) => key.startsWith("hint:dismissed:"))
      .forEach((key) => localStorage.removeItem(key))

    if (this.hasConfirmationTarget) {
      this.confirmationTarget.hidden = false
    }
  }

  get dismissed() {
    return localStorage.getItem(this.storageKey) === "1"
  }

  get storageKey() {
    return `hint:dismissed:${this.idValue}`
  }
}
