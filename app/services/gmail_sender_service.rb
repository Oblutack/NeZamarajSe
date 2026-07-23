# app/services/gmail_sender_service.rb
require "google/apis/gmail_v1"
require "net/http"

class GmailSenderService
  def initialize(user)
    @user = user
    @gmail = Google::Apis::GmailV1::GmailService.new

    # Before we do anything, ensure the token is valid
    refresh_token_if_expired!
    @gmail.authorization = @user.access_token
  end

  def send_email(raw_message_string)
    # The Gmail API requires the raw email string to be wrapped in their Message object
    message_object = Google::Apis::GmailV1::Message.new(raw: raw_message_string)

    # 'me' tells Google to use the authenticated user's account
    @gmail.send_user_message("me", message_object)
  end

  private

  def refresh_token_if_expired!
    # If the token expires in the next 5 minutes (or is already expired), refresh it
    return unless @user.token_expires_at.nil? || @user.token_expires_at < 5.minutes.from_now

    puts "🔄 Refreshing Google OAuth Token..."

    url = URI("https://oauth2.googleapis.com/token")
    response = Net::HTTP.post_form(url, {
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      refresh_token: @user.refresh_token,
      grant_type: "refresh_token"
    })

    data = JSON.parse(response.body)

    if data["access_token"]
      @user.update(
        access_token: data["access_token"],
        token_expires_at: Time.now + data["expires_in"].to_i.seconds
      )
    else
      raise "Failed to refresh token: #{data}"
    end
  end
end
