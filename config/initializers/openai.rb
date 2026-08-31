# config/initializers/openai.rb
OpenAI.configure do |config|
  # We use our Groq key. Rescue MissingKeyError so a boot without
  # RAILS_MASTER_KEY/config/master.key (e.g. CI without the secret configured)
  # doesn't crash the whole app over an optional credential - AiJobAnalyzerService
  # will just fail gracefully at call time instead.
  config.access_token = begin
    Rails.application.credentials.dig(:groq, :api_key)
  rescue ActiveSupport::EncryptedFile::MissingKeyError
    nil
  end

  # MAGIC: We override the URI to point to Groq instead of OpenAI
  config.uri_base = "https://api.groq.com/openai"

  # Optional: Log requests in development so we can see the AI thinking
  config.log_errors = true
end
