// app/javascript/controllers/confirm_dialog_controller.js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Replaces Turbo's default confirm for every data-turbo-confirm link/button
// (Remove card, Delete template, Cancel send, etc.) with this in-page
// <dialog> instead of window.confirm(). window.confirm() is a native
// browser dialog that some browsers - and their own popup-blocker settings
// - suppress outright, which silently turns a destructive action's
// confirmation into a no-op with no visible error. A <dialog> is just page
// content, so it's unaffected either way.
export default class extends Controller {
  static targets = ["message", "confirmButton"]

  connect() {
    this.resolve = null
    this.element.addEventListener("close", () => {
      this.resolve?.(this.element.returnValue === "confirm")
      this.resolve = null
    })
    Turbo.config.forms.confirm = (message) => this.show(message)
  }

  show(message) {
    this.messageTarget.textContent = message
    this.element.returnValue = ""
    this.element.showModal()
    this.confirmButtonTarget.focus()
    return new Promise((resolve) => { this.resolve = resolve })
  }

  confirm() {
    this.element.close("confirm")
  }

  cancel() {
    this.element.close("cancel")
  }

  backdropClick(event) {
    if (event.target === this.element) this.cancel()
  }
}
