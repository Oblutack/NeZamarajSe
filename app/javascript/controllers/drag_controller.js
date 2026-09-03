// app/javascript/controllers/drag_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Fired when you start dragging a card
  dragStart(event) {
    event.dataTransfer.setData("application_id", event.target.dataset.id)
    event.currentTarget.classList.add("opacity-50", "scale-95")
  }

  // Fired when you drop the card
  dragEnd(event) {
    event.currentTarget.classList.remove("opacity-50", "scale-95")
  }

  // Fired when a card is hovering over a column (Required for HTML5 dropping)
  dragOver(event) { 
    event.preventDefault()
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