# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  has_many :applications, dependent: :destroy
  has_many :jobs, through: :applications
  has_many_attached :resumes
  validates :resumes,
            content_type: { in: "application/pdf", message: ->(_object, _data) { I18n.t("activerecord.errors.models.user.attributes.resumes.content_type_invalid") } },
            size: { less_than: 5.megabytes, message: ->(_object, _data) { I18n.t("activerecord.errors.models.user.attributes.resumes.file_too_large") } }

  # --- SECURITY: ENCRYPT OAUTH TOKENS IN THE DB ---
  encrypts :access_token, :refresh_token
  has_many :cover_letter_templates, dependent: :destroy

  # NEW: A user has exactly ONE preference profile
  has_one :user_preference, dependent: :destroy

  has_many :contacted_companies, class_name: "Company", foreign_key: :last_contacted_by_id, dependent: :nullify
  has_many :company_email_suggestions, dependent: :destroy

  # NEW: Automatically create preferences after Google OAuth
  after_create :create_default_preferences

  # Shared by both job-application sends (ApplicationsController) and
  # cold-outreach sends (CompaniesController) - both draw down the same
  # daily allowance since they go out through the same Gmail account and
  # carry the same spam-heuristic risk.
  def remaining_daily_sends
    today = Time.current.all_day
    sent_today = applications.where(queued_at: today).count +
      applications.where(last_followed_up_at: today).count +
      contacted_companies.where(last_contacted_at: today).count
    [ Rails.application.config.daily_send_cap - sent_today, 0 ].max
  end

  private

  def create_default_preferences
    create_user_preference(
      keywords: "Developer, Software, IT",
      location: "Bosnia",
      receive_daily_alerts: true
    )
  end

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
