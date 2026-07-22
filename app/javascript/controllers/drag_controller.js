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
    
    // Find the hidden form for this specific application
    const form = document.getElementById(`move-form-${applicationId}`)
    
    if (form) {
      // Update the hidden input value and submit via Turbo
      form.querySelector(".status-input").value = newStatus
      form.requestSubmit()
    }
  }
}