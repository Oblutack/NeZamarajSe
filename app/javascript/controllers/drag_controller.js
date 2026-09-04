// app/javascript/controllers/drag_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "scrollable" ]

  // Fired when you start dragging a card
  dragStart(event) {
    event.dataTransfer.setData("application_id", event.target.dataset.id)
    event.currentTarget.classList.add("opacity-50", "scale-95")
  }

  // Fired when you drop the card
  dragEnd(event) {
    event.currentTarget.classList.remove("opacity-50", "scale-95")
  }

  // Fired repeatedly (many times a second) while a card hovers over a
  // column - required for HTML5 dropping to work at all (browsers only
  // allow a drop if dragover was preventDefault()'d), and also where the
  // column's own auto-scroll lives: a column with enough cards to need
  // scrolling had no way to reach anything below the fold while a drag was
  // in progress (native HTML5 drag doesn't auto-scroll a nested
  // overflow-y container on its own, only the whole page) - it looked and
  // felt like the column had a hard cap on card count, though nothing
  // ever actually enforced one.
  dragOver(event) {
    event.preventDefault()
    this.autoScroll(event)
  }

  autoScroll(event) {
    if (!this.hasScrollableTarget) return

    const rect = this.scrollableTarget.getBoundingClientRect()
    const edge = 48
    const speed = 14

    if (event.clientY < rect.top + edge) {
      this.scrollableTarget.scrollTop -= speed
    } else if (event.clientY > rect.bottom - edge) {
      this.scrollableTarget.scrollTop += speed
    }
  }

  // Fired when the card is dropped into a column
  drop(event) {
    event.preventDefault()

    const applicationId = event.dataTransfer.getData("application_id")
    const newStatus = event.currentTarget.dataset.status // Gets the status of the column

    this.submitMove(applicationId, newStatus)
  }

  // Keyboard/screen-reader/touch equivalent of a drag-and-drop move - wired
  // to each "Move to…" menu item on the card (see _application_card.html.erb
  // and dropdown_controller.js for the menu itself). Same hidden form and
  // the same result as dropping the card, just without a mouse.
  moveTo(event) {
    const { id, status } = event.currentTarget.dataset
    this.submitMove(id, status)
  }

  submitMove(applicationId, newStatus) {
    // One shared hidden form (applications/index.html.erb) instead of one
    // per application - its action just gets pointed at the right record
    // right before every submit.
    const form = document.getElementById("move-form")
    if (!form) return

    form.action = `/applications/${applicationId}`
    form.querySelector(".status-input").value = newStatus
    form.requestSubmit()
  }
}