# app/models/job.rb
class Job < ApplicationRecord
  belongs_to :company
  has_many :applications, dependent: :destroy
  has_many :job_sources, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true

  scope :expiring_soon, -> { where(expires_at: Date.current..14.days.from_now) }
end
