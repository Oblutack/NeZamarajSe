import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // These tell Stimulus which HTML elements we want to interact with
  static targets = ["checkbox", "floatingBar", "countBadge"]

  connect() {
    this.toggleBar()
  }

  // Cards now move in and out of columns without a page reload (an optimistic
  // drag, the server's own stream, or a broadcast from another tab), and a
  // card leaving the wishlist column takes its checkbox with it. Recounting
  // whenever a checkbox enters or leaves the DOM covers all of those without
  // each one having to remember to announce itself.
  checkboxTargetConnected() {
    this.toggleBar()
  }

  checkboxTargetDisconnected() {
    this.toggleBar()
  }

  // This fires every time a user clicks a checkbox
  toggleBar() {
    // Count how many checkboxes are currently checked
    const selectedCount = this.checkboxTargets.filter(c => c.checked).length

    if (selectedCount > 0) {
      // Show the floating bar and update the number
      this.countBadgeTarget.innerText = selectedCount
      this.floatingBarTarget.classList.remove("translate-y-full")
      this.floatingBarTarget.classList.add("translate-y-0")
    } else {
      // Hide the floating bar
      this.floatingBarTarget.classList.remove("translate-y-0")
      this.floatingBarTarget.classList.add("translate-y-full")
    }
  }
}
