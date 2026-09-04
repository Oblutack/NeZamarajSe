# app/models/company.rb
class Company < ApplicationRecord
  has_many :jobs, dependent: :destroy
  has_many :email_suggestions, class_name: "CompanyEmailSuggestion", dependent: :destroy
  belongs_to :last_contacted_by, class_name: "User", optional: true

  validates :name, presence: true, uniqueness: true

  # Reply detection is the free validator for a crowdsourced (or scraped, or
  # Hunter-found) email - an address that produced a real reply demonstrably
  # works. Counts distinct applications, across every job this company has
  # posted, that were sent to the current primary_email and later got a
  # reply_detected event.
  def reply_confirmed_send_count
    return 0 if primary_email.blank?

    Application.where(sent_recipient: primary_email, job_id: jobs.select(:id))
      .joins(:application_events)
      .where(application_events: { event_type: "reply_detected" })
      .distinct.count
  end
end
