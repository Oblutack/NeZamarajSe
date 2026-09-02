# config/initializers/i18n.rb
Rails.application.config.i18n.available_locales = [ :en, :bs ]
Rails.application.config.i18n.default_locale = :en

# Any Bosnian key this app itself doesn't define yet falls back to English
# rather than rendering "translation missing" - rails-i18n/devise-i18n's own
# bundled bs.yml files (date/number formats, Devise's flashes and
# validation messages) still apply on top of this for their own keys.
Rails.application.config.i18n.fallbacks = true
