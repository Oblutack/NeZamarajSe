# app/models/application.rb
class Application < ApplicationRecord
  belongs_to :user
  belongs_to :job

  # The Rails 8 Way to handle state machines / CRM lanes
  enum :status, {
    wishlist: "wishlist",
    queued: "queued",
    applied: "applied",
    interviewing: "interviewing",
    rejected: "rejected",
    offered: "offered"
  }

  validates :user_id, uniqueness: { scope: :job_id, message: "has already saved this job" }

  after_update_commit -> { broadcast_status_update }, if: :saved_change_to_status?

  # The real target this application would go to - shared by the compose
  # preview and the mailer, so they can never say different things about who
  # this is "for". Independent of dry_run_emails: this is who it's *for*,
  # not necessarily where the bytes go (see JobApplicationMailer#apply).
  def intended_recipient
    job.hr_email.presence || job.company.primary_email.presence
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
end
