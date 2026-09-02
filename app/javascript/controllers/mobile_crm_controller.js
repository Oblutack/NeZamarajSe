// app/javascript/controllers/mobile_crm_controller.js
import { Controller } from "@hotwired/stimulus"

// Below the `sm` breakpoint the six w-72 Kanban columns would be ~1,730px of
// horizontal scroll, so on mobile only the selected status's column shows
// at a time, switched via a pill tab bar. Each column carries `hidden
// sm:flex` in the view - `sm:flex` always wins at the sm breakpoint and up
// regardless of what this toggles, so desktop's normal all-columns-visible
// layout is untouched; this only ever matters below `sm`.
export default class extends Controller {
  static targets = ["tab", "column"]

  connect() {
    this.show(this.tabTargets[0]?.dataset.status)
  }

  switch(event) {
    this.show(event.currentTarget.dataset.status)
  }

  show(status) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.status === status
      tab.classList.toggle("bg-zinc-900", active)
      tab.classList.toggle("text-white", active)
      tab.classList.toggle("dark:bg-white", active)
      tab.classList.toggle("dark:text-zinc-900", active)
      tab.classList.toggle("text-zinc-600", !active)
      tab.classList.toggle("dark:text-zinc-400", !active)
    })

    this.columnTargets.forEach((column) => {
      const active = column.dataset.status === status
      column.classList.toggle("hidden", !active)
      column.classList.toggle("flex", active)
    })
  }
}
