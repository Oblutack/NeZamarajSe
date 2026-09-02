// app/javascript/controllers/theme_controller.js
import { Controller } from "@hotwired/stimulus"

// The `dark` class itself is already set (or not) before this controller
// ever connects - see the inline script in layouts/application.html.erb.
// This only handles the toggle button's icon state and flipping it.
export default class extends Controller {
  static targets = ["sunIcon", "moonIcon"]

  connect() {
    this.updateIcons()
  }

  toggle() {
    const isDark = document.documentElement.classList.toggle("dark")
    localStorage.setItem("theme", isDark ? "dark" : "light")
    this.updateIcons()
  }

  updateIcons() {
    const isDark = document.documentElement.classList.contains("dark")
    this.sunIconTarget.classList.toggle("hidden", isDark)
    this.moonIconTarget.classList.toggle("hidden", !isDark)
  }
}
