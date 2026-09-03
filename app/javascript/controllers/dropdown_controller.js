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
    // Lifts this controller's own root element (e.g. a Kanban card) above
    // its normal-flow siblings while the menu is open. Without this, a
    // menu that overflows past its own card's bottom edge can render
    // behind the next card: `position: relative` with no z-index doesn't
    // establish a stacking context, so the menu's own z-index only wins
    // locally - the card housing it still stacks below a later sibling
    // card at the parent level, and the menu goes down with it.
    this.element.classList.add("z-30")
    // Deferred so the click that opened the menu doesn't immediately
    // bubble into this same listener and close it again.
    setTimeout(() => document.addEventListener("click", this.boundClickOutside))
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.element.classList.remove("z-30")
    document.removeEventListener("click", this.boundClickOutside)
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
