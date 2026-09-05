// app/javascript/controllers/drag_controller.js
import { Controller } from "@hotwired/stimulus"

// Sorts a column by deadline, soonest first, with no-deadline cards last -
// the client-side mirror of Application#deadline_sort_key, so an optimistic
// move drops the card exactly where the server's own stream will confirm it.
const NO_DEADLINE = Number.MAX_SAFE_INTEGER

function deadlineOf(card) {
  const raw = card.dataset.deadline
  if (!raw) return NO_DEADLINE
  const parsed = Date.parse(raw)
  return Number.isNaN(parsed) ? NO_DEADLINE : parsed
}

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
  //
  // Not bound on the "Sending soon" column at all (see the note in
  // applications/index.html.erb), so the browser refuses drops there itself.
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

    const card = document.getElementById(`application_${applicationId}`)
    const destination = document.getElementById(`crm_list_${newStatus}`)

    // Dropping a card back where it came from is a no-op, not a round trip.
    if (card && destination && card.parentElement === destination) return

    // Move it now rather than waiting on the server. Without this the card
    // snaps back to the column it came from and sits there until the
    // response lands - the one gesture in the app that has to feel direct
    // was the one that felt slowest. `undo` puts it all back if the server
    // refuses (a send in flight, say) or the request never arrives.
    const undo = this.moveOptimistically(card, destination)

    form.action = `/applications/${applicationId}`
    form.querySelector(".status-input").value = newStatus

    if (undo) {
      form.addEventListener("turbo:submit-end", (event) => {
        if (!event.detail.success) undo()
      }, { once: true })
    }

    form.requestSubmit()
  }

  // Returns a function that restores the card, the counts, and any empty
  // state exactly as they were - or null when there was nothing to move.
  moveOptimistically(card, destination) {
    if (!card || !destination) return null

    const origin = card.parentElement
    const originNextSibling = card.nextElementSibling
    const originStatus = origin?.id.replace("crm_list_", "")
    const destinationStatus = destination.id.replace("crm_list_", "")

    // A column showing its empty state can't also show a card.
    const emptyState = destination.querySelector(`#crm_empty_${destinationStatus}`)
    emptyState?.remove()

    this.insertInDeadlineOrder(card, destination)
    this.bumpCount(originStatus, -1)
    this.bumpCount(destinationStatus, +1)

    return () => {
      origin?.insertBefore(card, originNextSibling)
      if (emptyState) destination.appendChild(emptyState)
      this.bumpCount(originStatus, +1)
      this.bumpCount(destinationStatus, -1)
    }
  }

  // Columns are ordered by deadline, not insertion - appending would drop an
  // urgent card at the bottom until the next full page load.
  insertInDeadlineOrder(card, destination) {
    const deadline = deadlineOf(card)
    const nextCard = Array.from(destination.children).find((sibling) => (
      sibling !== card && sibling.dataset.deadline !== undefined && deadlineOf(sibling) > deadline
    ))

    destination.insertBefore(card, nextCard || null)
  }

  bumpCount(status, delta) {
    const badge = document.getElementById(`crm_count_${status}`)
    if (!badge) return

    const current = parseInt(badge.textContent.trim(), 10)
    if (Number.isNaN(current)) return

    badge.textContent = Math.max(0, current + delta)
  }
}
