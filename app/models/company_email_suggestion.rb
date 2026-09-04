# app/models/company_email_suggestion.rb
class CompanyEmailSuggestion < ApplicationRecord
  belongs_to :company
  belongs_to :user

  # Deliberately loose - plenty of legitimate small BH companies genuinely
  # use a free-mail address, and rejecting those to guard against a rare bad
  # submission would throw away good data. Just needs to look like an email.
  validates :email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, message: :invalid }

  # One suggestion per user per company - resubmitting updates it rather than
  # stacking a second row, so a single user can't fake "uncontested" by
  # posting several guesses under their own account.
  validates :user_id, uniqueness: { scope: :company_id }

  after_save_commit :promote_if_uncontested

  private

  # "Uncontested" means every suggestion on file for this company agrees -
  # trivially true the first time, no longer true the moment a second person
  # suggests something different. Only fills a blank: an email a scraper, the
  # job page itself, or Hunter already found is never touched (same
  # discipline as AiJobAnalyzerService's `hr_email.presence || ...`), and
  # once a suggestion has been promoted once, later disagreement doesn't
  # un-set it either - "never clobber" applies to suggestion-sourced data
  # too, not just machine-sourced.
  def promote_if_uncontested
    return if company.primary_email.present?

    suggested_emails = company.email_suggestions.distinct.pluck(:email)
    company.update!(primary_email: suggested_emails.first) if suggested_emails.one?
  end
end
