# app/models/cover_letter_template.rb
class CoverLetterTemplate < ApplicationRecord
  belongs_to :user
  has_rich_text :body

  # Set only once Gmail actually confirms the send (SendApplicationJob),
  # alongside sent_subject/sent_body - so every row here really was sent
  # with this template, not just queued with it selected. nullify (not
  # destroy) on template deletion: an application's own send history
  # shouldn't disappear because the template that produced it did.
  has_many :applications, dependent: :nullify

  # Shared by CoverLetterGeneratorService, CoverLetterTranslatorService, and
  # the compose page's language picker - one place naming which languages
  # the AI cover letter feature supports.
  LANGUAGES = { "en" => "English", "bs" => "Bosnian" }.freeze

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :body, presence: true
  validates :language, inclusion: { in: LANGUAGES.keys }, allow_nil: true

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

  # Cold outreach has no specific job posting behind it, so {{job_title}}
  # and {{location}} are blanked rather than left as literal unsubstituted
  # tags - write cold-outreach templates that only lean on {{company_name}}.
  def render_content_for_company(company)
    rendered = body.to_plain_text.dup
    rendered.gsub!("{{company_name}}", company.name)
    rendered.gsub!("{{job_title}}", "")
    rendered.gsub!("{{location}}", "")
    rendered
  end

  # How many applications were actually sent with this template, and how
  # many of those got a reply - computed from data already in the database
  # (application_events' reply_detected rows), no new tracking needed
  # beyond the applications.cover_letter_template_id column itself.
  # Deliberately keyed off the reply_detected *event*, not current status -
  # since the Kanban board's "Move to..." menu lets a card reach
  # "Interviewing" by hand now too, status alone stopped being a reliable
  # signal that a real reply happened.
  def sent_count
    applications.count
  end

  def reply_count
    applications.joins(:application_events)
      .where(application_events: { event_type: "reply_detected" })
      .distinct.count
  end
end
