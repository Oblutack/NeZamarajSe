# app/models/cover_letter_template.rb
class CoverLetterTemplate < ApplicationRecord
  belongs_to :user
  has_rich_text :body

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :body, presence: true

  # This is the "Architect" way to handle string interpolation safely later.
  # We'll call this method right before sending an email.
  #
  # Substituting on the plain-text rendering (not the raw HTML) means a smart
  # tag split across Trix's own markup can't half-match, and the mailer -
  # which only sends a text/plain body (see apply.text.erb) - gets exactly
  # the string it needs with no HTML to strip itself.
  def render_content(job)
    rendered = body.to_plain_text.dup
    rendered.gsub!("{{company_name}}", job.company.name) if job.company
    rendered.gsub!("{{job_title}}", job.title)
    rendered.gsub!("{{location}}", job.location || "your office")
    rendered
  end
end
