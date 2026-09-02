class ApplicationController < ActionController::Base
  include Pagy::Backend

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :switch_locale

  private

  # Session-based, not URL-prefixed (no /bs/... route scoping) - this app
  # has no public multi-language marketing surface that would benefit from
  # locale-specific URLs/SEO, so the simpler choice wins. LocalesController
  # sets session[:locale]; signed-out visitors get it too (e.g. on the
  # sign-in page), since nothing here is gated behind auth.
  def switch_locale(&action)
    locale = session[:locale].presence_in(I18n.available_locales.map(&:to_s)) || I18n.default_locale
    I18n.with_locale(locale, &action)
  end
end
