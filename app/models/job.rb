# app/models/job.rb
class Job < ApplicationRecord
  belongs_to :company
  has_many :applications, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true
end
