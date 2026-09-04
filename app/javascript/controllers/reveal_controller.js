// app/javascript/controllers/reveal_controller.js
import { Controller } from "@hotwired/stimulus"

// Click a trigger to reveal a hidden target and hide the trigger itself -
// generic one-way progressive disclosure (no toggle/close), for a small
// form or detail that's only worth showing on demand. First used by the
// "do you know who to email here?" prompt (shared/_email_suggestion_form).
export default class extends Controller {
  static targets = ["trigger", "content"]

  show() {
    this.triggerTarget.classList.add("hidden")
    this.contentTarget.classList.remove("hidden")

    const input = this.contentTarget.querySelector("input, textarea")
    if (input) input.focus()
  }
}
