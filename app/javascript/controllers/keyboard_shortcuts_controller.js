// app/javascript/controllers/keyboard_shortcuts_controller.js
import { Controller } from "@hotwired/stimulus"

// Page-level list navigation, independent of the command palette (which
// owns its own Cmd/Ctrl+K + arrow-key handling - see
// command_palette_controller.js). Lives on <body> since it needs to work
// across the whole page, not just inside one card grid or table.
//
// "/" focuses the current page's own search field - opt in per-page by
// adding data-shortcut="search" to a text input (Job Market and Companies
// both do). "j"/"k" move a highlight through every element marked
// data-shortcut-item="true" on the current page (job/company rows), and
// Enter follows that item's own link. None of this fires while the user is
// actually typing somewhere, or while the command palette is open.
export default class extends Controller {
  connect() {
    this.focusedIndex = -1
    this.boundKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  handleKeydown(event) {
    if (this.isTyping(event.target) || this.paletteIsOpen()) return

    if (event.key === "/") {
      const searchField = document.querySelector("[data-shortcut='search']")
      if (searchField) {
        event.preventDefault()
        searchField.focus()
      }
      return
    }

    if (event.key === "j" || event.key === "k") {
      const items = this.items()
      if (items.length === 0) return

      event.preventDefault()
      this.focus(items, event.key === "j" ? this.focusedIndex + 1 : this.focusedIndex - 1)
      return
    }

    if (event.key === "Enter" && this.focusedIndex >= 0) {
      const items = this.items()
      const current = items[this.focusedIndex]
      if (current) {
        const link = current.matches("a") ? current : current.querySelector("a")
        if (link) link.click()
      }
    }
  }

  items() {
    return Array.from(document.querySelectorAll("[data-shortcut-item]"))
  }

  focus(items, index) {
    items.forEach((item) => item.classList.remove("shortcut-focused"))

    if (index < 0) index = items.length - 1
    if (index >= items.length) index = 0
    this.focusedIndex = index

    const target = items[index]
    target.classList.add("shortcut-focused")
    target.scrollIntoView({ block: "center", behavior: "smooth" })
  }

  isTyping(target) {
    return [ "INPUT", "TEXTAREA", "SELECT" ].includes(target.tagName) || target.isContentEditable
  }

  paletteIsOpen() {
    const dialog = document.querySelector("[data-command-palette-target='dialog']")
    return dialog && !dialog.classList.contains("hidden")
  }
}
