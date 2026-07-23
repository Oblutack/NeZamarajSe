# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  has_many :applications, dependent: :destroy
  has_many :jobs, through: :applications
  has_many_attached :resumes
  has_many :cover_letter_templates, dependent: :destroy

  # This method handles the OAuth payload
  def self.from_omniauth(auth)
    # Find the user, or initialize a new one if they don't exist yet
    user = where(provider: auth.provider, uid: auth.uid).first_or_initialize

    user.email = auth.info.email
    user.password = Devise.friendly_token[0, 20] if user.new_record?

    # ALWAYS update the access token
    user.access_token = auth.credentials.token

    # Google only sends a refresh_token when the user explicitly grants consent.
    # We only update it if Google actually sent a new one.
    if auth.credentials.refresh_token.present?
      user.refresh_token = auth.credentials.refresh_token
    end

    if auth.credentials.expires_at
      user.token_expires_at = Time.at(auth.credentials.expires_at)
    end

    user.save!
    user
  end
end
