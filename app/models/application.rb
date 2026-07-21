# app/models/application.rb
class Application < ApplicationRecord
  belongs_to :user
  belongs_to :job

  # The Rails Way to handle state machines / CRM lanes
  enum status: {
    wishlist: "wishlist",
    applied: "applied",
    interviewing: "interviewing",
    rejected: "rejected",
    offered: "offered"
  }

  validates :user_id, uniqueness: { scope: :job_id, message: "has already saved this job" }
end
