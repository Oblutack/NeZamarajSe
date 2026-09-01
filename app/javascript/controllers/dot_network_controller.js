// app/javascript/controllers/dot_network_controller.js
//
// A quiet, monochrome "constellation" background: a handful of slowly
// drifting dots, faintly connected by lines when close together. Purely
// decorative - sits behind page content on a <canvas>, never intercepts
// clicks, and does nothing at all if the visitor has asked for reduced
// motion.
import { Controller } from "@hotwired/stimulus"

const DOT_COLOR = "113, 113, 122" // zinc-500
const LINE_COLOR = "161, 161, 170" // zinc-400
const MAX_LINE_DISTANCE = 120
const DOT_RADIUS = 1.5
const DOT_AREA_DIVISOR = 9000 // ~1 dot per 9000px^2 of canvas
const MAX_DOTS = 70
const SPEED = 0.15

export default class extends Controller {
  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.ctx = this.element.getContext("2d")
    this.boundTick = this.tick.bind(this)
    this.boundResize = this.handleResize.bind(this)

    this.handleResize()
    window.addEventListener("resize", this.boundResize)
    this.frame = requestAnimationFrame(this.boundTick)
  }

  disconnect() {
    if (this.frame) cancelAnimationFrame(this.frame)
    window.removeEventListener("resize", this.boundResize)
  }

  handleResize() {
    const rect = this.element.getBoundingClientRect()
    this.width = rect.width
    this.height = rect.height

    const ratio = window.devicePixelRatio || 1
    this.element.width = this.width * ratio
    this.element.height = this.height * ratio
    this.ctx.setTransform(ratio, 0, 0, ratio, 0, 0)

    this.dots = this.buildDots()
  }

  buildDots() {
    const count = Math.min(MAX_DOTS, Math.floor((this.width * this.height) / DOT_AREA_DIVISOR))
    return Array.from({ length: count }, () => ({
      x: Math.random() * this.width,
      y: Math.random() * this.height,
      vx: (Math.random() - 0.5) * SPEED,
      vy: (Math.random() - 0.5) * SPEED
    }))
  }

  tick() {
    const ctx = this.ctx
    ctx.clearRect(0, 0, this.width, this.height)

    for (const dot of this.dots) {
      dot.x += dot.vx
      dot.y += dot.vy
      if (dot.x < 0 || dot.x > this.width) dot.vx *= -1
      if (dot.y < 0 || dot.y > this.height) dot.vy *= -1
    }

    ctx.lineWidth = 1
    for (let i = 0; i < this.dots.length; i++) {
      for (let j = i + 1; j < this.dots.length; j++) {
        const a = this.dots[i]
        const b = this.dots[j]
        const dist = Math.hypot(a.x - b.x, a.y - b.y)
        if (dist < MAX_LINE_DISTANCE) {
          ctx.strokeStyle = `rgba(${LINE_COLOR}, ${0.15 * (1 - dist / MAX_LINE_DISTANCE)})`
          ctx.beginPath()
          ctx.moveTo(a.x, a.y)
          ctx.lineTo(b.x, b.y)
          ctx.stroke()
        }
      }
    }

    ctx.fillStyle = `rgba(${DOT_COLOR}, 0.4)`
    for (const dot of this.dots) {
      ctx.beginPath()
      ctx.arc(dot.x, dot.y, DOT_RADIUS, 0, Math.PI * 2)
      ctx.fill()
    }

    this.frame = requestAnimationFrame(this.boundTick)
  }
}
