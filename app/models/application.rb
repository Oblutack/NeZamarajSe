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
