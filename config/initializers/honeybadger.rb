# config/initializers/honeybadger.rb
Honeybadger.configure do |config|
  # Same defensive pattern as config/initializers/openai.rb: rescue
  # MissingKeyError so a boot without RAILS_MASTER_KEY/config/master.key
  # (e.g. CI without the secret configured, or before the key is added
  # locally) doesn't crash the app - Honeybadger just won't report without
  # a key, same as it already skips reporting in dev/test by default.
  config.api_key = begin
    Rails.application.credentials.dig(:honeybadger, :api_key)
  rescue ActiveSupport::EncryptedFile::MissingKeyError
    nil
  end
end
