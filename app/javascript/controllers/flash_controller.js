// app/javascript/controllers/flash_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Automatically trigger the dismiss animation after 4 seconds
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, 4000)
  }

  dismiss() {
    // Add Tailwind classes to fade out and slide up
    this.element.classList.remove("opacity-100", "translate-y-0")
    this.element.classList.add("opacity-0", "-translate-y-4")
    
    // Wait for the Tailwind transition to finish (300ms) before completely removing the DOM node
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}