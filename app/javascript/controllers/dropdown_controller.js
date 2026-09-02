// app/javascript/controllers/dropdown_controller.js
import { Controller } from "@hotwired/stimulus"

// Generic click-to-open, click-outside-to-close dropdown menu - used by
// the navbar's "Manage" and account menus.
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.boundClickOutside = this.clickOutside.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
  }

  toggle() {
    this.menuTarget.classList.contains("hidden") ? this.open() : this.close()
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    // Deferred so the click that opened the menu doesn't immediately
    // bubble into this same listener and close it again.
    setTimeout(() => document.addEventListener("click", this.boundClickOutside))
  }

  close() {
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundClickOutside)
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
