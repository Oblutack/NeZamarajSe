# config/initializers/openai.rb
OpenAI.configure do |config|
  # We use our Groq key
  config.access_token = Rails.application.credentials.dig(:groq, :api_key)
  
  # MAGIC: We override the URI to point to Groq instead of OpenAI
  config.uri_base = "https://api.groq.com/openai"
  
  # Optional: Log requests in development so we can see the AI thinking
  config.log_errors = true 
end 