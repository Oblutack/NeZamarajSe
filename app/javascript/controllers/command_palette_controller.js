// app/javascript/controllers/command_palette_controller.js
import { Controller } from "@hotwired/stimulus"

// Global ⌘K / Ctrl+K command palette - a static, server-rendered list of
// destinations (see shared/_command_palette.html.erb) filtered client-side
// and navigated via Turbo. Lives on <body> so the trigger button in the
// navbar and the dialog itself (siblings in the layout) can share one
// controller instance.
export default class extends Controller {
  static targets = ["dialog", "input", "item", "empty"]

  connect() {
    this.boundKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  handleKeydown(event) {
    const isMac = navigator.platform.toUpperCase().includes("MAC")
    const modifierPressed = isMac ? event.metaKey : event.ctrlKey

    if (modifierPressed && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.open()
      return
    }

    if (!this.isOpen) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      this.move(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.move(-1)
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.visitFocused()
    }
  }

  open() {
    // So focus can go back to whatever opened this (the navbar button, or
    // nothing in particular if it was the ⌘K shortcut) once it closes -
    // otherwise focus is just dropped when the dialog disappears.
    this.previouslyFocusedElement = document.activeElement

    this.isOpen = true
    this.dialogTarget.classList.remove("hidden")
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
    document.body.style.overflow = "hidden"
  }

  close() {
    this.isOpen = false
    this.dialogTarget.classList.add("hidden")
    document.body.style.overflow = ""
    this.previouslyFocusedElement?.focus()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    let firstVisible = null

    this.itemTargets.forEach((item) => {
      const matches = item.dataset.label.toLowerCase().includes(query)
      item.classList.toggle("hidden", !matches)
      this.deactivate(item)
      if (matches && !firstVisible) firstVisible = item
    })

    if (firstVisible) this.activate(firstVisible)
    this.emptyTarget.classList.toggle("hidden", !!firstVisible)
  }

  move(direction) {
    const visible = this.itemTargets.filter((item) => !item.classList.contains("hidden"))
    if (visible.length === 0) return

    const currentIndex = visible.findIndex((item) => item.getAttribute("aria-selected") === "true")
    visible.forEach((item) => this.deactivate(item))

    let nextIndex = currentIndex + direction
    if (nextIndex < 0) nextIndex = visible.length - 1
    if (nextIndex >= visible.length) nextIndex = 0

    const next = visible[nextIndex]
    this.activate(next)
    next.scrollIntoView({ block: "nearest" })
  }

  visitFocused() {
    const focused = this.itemTargets.find((item) => !item.classList.contains("hidden") && item.getAttribute("aria-selected") === "true")
    if (focused) Turbo.visit(focused.dataset.url)
  }

  // Keeps the visible highlight, `aria-selected`, and the input's
  // `aria-activedescendant` (what a screen reader announces as "current")
  // all pointing at the same item - the combobox/listbox pattern needs all
  // three to move together.
  activate(item) {
    item.classList.add("bg-zinc-100", "dark:bg-zinc-800")
    item.setAttribute("aria-selected", "true")
    this.inputTarget.setAttribute("aria-activedescendant", item.id)
  }

  deactivate(item) {
    item.classList.remove("bg-zinc-100", "dark:bg-zinc-800")
    item.setAttribute("aria-selected", "false")
  }

  visit(event) {
    Turbo.visit(event.currentTarget.dataset.url)
  }
}
