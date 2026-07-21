# app/models/cover_letter_template.rb
class CoverLetterTemplate < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :body, presence: true

  # This is the "Architect" way to handle string interpolation safely later.
  # We'll call this method right before sending an email.
  def render_content(job)
    rendered = body.to_s.dup
    rendered.gsub!("{{company_name}}", job.company.name) if job.company
    rendered.gsub!("{{job_title}}", job.title)
    rendered.gsub!("{{location}}", job.location || "your office")
    rendered
  end
end
