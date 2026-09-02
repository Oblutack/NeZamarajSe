# app/models/application.rb
class Application < ApplicationRecord
  belongs_to :user
  belongs_to :job
  has_many :application_events, dependent: :destroy

  # The Rails 8 Way to handle state machines / CRM lanes
  enum :status, {
    wishlist: "wishlist",
    queued: "queued",
    applied: "applied",
    interviewing: "interviewing",
    rejected: "rejected",
    offered: "offered"
  }

  validates :user_id, uniqueness: { scope: :job_id, message: ->(_object, _data) { I18n.t("activerecord.errors.models.application.attributes.user_id.already_saved") } }

  after_update_commit -> { broadcast_status_update }, if: :saved_change_to_status?
  after_update_commit -> { record_status_change_event }, if: :saved_change_to_status?

  # The real target this application would go to - shared by the compose
  # preview and the mailer, so they can never say different things about who
  # this is "for". Independent of dry_run_emails: this is who it's *for*,
  # not necessarily where the bytes go (see JobApplicationMailer#apply).
  def intended_recipient
    job.hr_email.presence || job.company.primary_email.presence
  end

  # Flags a silent "applied" card so the CRM can nudge the user to check in -
  # the clock resets on each follow-up sent, not just the original send, so
  # this fires again N days after the *last* contact, not just the first.
  def needs_follow_up?
    return false unless applied?

    last_contact = last_followed_up_at || applied_at
    last_contact.present? && last_contact <= Rails.application.config.follow_up_after_days.days.ago
  end

  private

  def broadcast_status_update
    Turbo::StreamsChannel.broadcast_replace_to(
      [ user, :crm ],
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "applications/application_card",
      locals: { app: self }
    )
  end

  def record_status_change_event
    application_events.create!(
      event_type: "status_change",
      from_status: status_before_last_save,
      to_status: status
    )
  end
end
