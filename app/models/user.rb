# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  has_many :applications, dependent: :destroy
  has_many :jobs, through: :applications
  has_many_attached :resumes
  
  # This method handles the OAuth payload
  def self.from_omniauth(auth)
    # Find the user by their Google UID, or create them if they don't exist
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      # Devise requires a password, so we generate a random secure one for OAuth users
      user.password = Devise.friendly_token[0, 20]

      # Save the tokens for our Sidekiq background workers later
      user.access_token = auth.credentials.token
      user.refresh_token = auth.credentials.refresh_token

      if auth.credentials.expires_at
        user.token_expires_at = Time.at(auth.credentials.expires_at)
      end
    end
  end
end
