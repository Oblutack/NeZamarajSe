require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module NeZamarajSe
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.middleware.use Rack::Attack

    # `encrypts :access_token, :refresh_token` (User) was added after some
    # users already had plaintext tokens saved from before encryption
    # existed. Without this, ActiveRecord::Encryption tries to decrypt that
    # old plaintext for dirty-checking on save (e.g. every OAuth re-login)
    # and raises ActiveRecord::Encryption::Errors::Decryption. This makes it
    # fall back to treating anything that isn't valid ciphertext as legacy
    # plaintext instead of raising - the standard Rails-recommended setting
    # for rolling out encryption onto a column that already has data. Every
    # write still gets properly encrypted; this only affects reading old
    # unencrypted values.
    config.active_record.encryption.support_unencrypted_data = true
  end
end
