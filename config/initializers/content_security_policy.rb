# Be sure to restart your server when you modify this file.

# This app renders scraped third-party job descriptions and ActionText rich
# text (cover letter bodies) - exactly the threat model CSP exists for, so
# this isn't optional hardening. See ROADMAP.md Track L for the audit that
# went into these directives; the two real gotchas were the dark-mode
# anti-flash inline <script> in the layout <head> (needs a nonce - see
# layouts/application.html.erb) and a handful of onchange="..." attributes
# on the compose screens' template/resume pickers (inline event-handler
# attributes can't be nonce'd, so those were moved to a small Stimulus
# controller - see auto_submit_controller.js - rather than loosened for).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.object_src  :none
    policy.base_uri    :self
    policy.frame_ancestors :none

    policy.script_src  :self
    # :unsafe_inline here only covers the `style="width: X%"` attributes on
    # the dashboard's two progress bars (a runtime-computed percentage isn't
    # a fixed Tailwind class) - inline style attributes can't be nonce'd,
    # and CSS injection is a far smaller practical risk than script
    # injection, which is why script-src above doesn't get the same
    # allowance. fonts.googleapis.com is the Geist font stylesheet link in
    # the layout <head>.
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src    :self, "https://fonts.gstatic.com"
    # :blob for Trix's local image preview while an attachment upload is
    # still in flight (see cover letter templates' rich-text body) - the
    # final, saved image is served same-origin via Active Storage.
    policy.img_src     :self, :data, :blob
    policy.connect_src :self
  end

  # A fresh random nonce per request (not the session id, which Rails'
  # own stock scaffolding suggests as a shortcut but which - since it's the
  # same value for every response in a session - is meaningfully weaker:
  # leak or predict it once and it's valid for every page the user loads
  # until they get a new session). `nonce_auto` covers
  # javascript_importmap_tags/javascript_tag output automatically; the one
  # hand-written <script> in the layout still needs
  # `nonce: content_security_policy_nonce` added explicitly since it isn't
  # rendered through either of those helpers.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
