// app/javascript/controllers/auto_submit_controller.js
import { Controller } from "@hotwired/stimulus"

// Submits the element's own <form> on change - replaces a raw inline
// onchange="this.form.requestSubmit()" HTML attribute (used on the
// template/resume pickers on every compose screen). Needed once CSP is on
// (see config/initializers/content_security_policy.rb): inline
// event-handler attributes can't be nonce'd like a <script> tag can, so
// script-src without 'unsafe-inline' blocks them outright - a Stimulus
// action is the CSP-compatible equivalent, and matches how every other
// interaction in this app is already wired up.
export default class extends Controller {
  submit() {
    this.element.form.requestSubmit()
  }
}
