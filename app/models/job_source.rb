# app/models/job_source.rb
class JobSource < ApplicationRecord
  belongs_to :job

  validates :source_name, presence: true, uniqueness: { scope: :job_id }
end
