# app/jobs/send_cold_outreach_job.rb
class SendColdOutreachJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, company_id, template_id, resume_blob_id, locale = I18n.default_locale.to_s)
    user = User.find(user_id)
    company = Company.find(company_id)
    # Same permanent-failure guard as SendApplicationJob - nothing to revert
    # here, since last_contacted_at is only written after Gmail confirms.
    template, resume = send_assets_for(user, template_id, resume_blob_id)

    if template.nil? || resume.nil?
      report_missing_send_assets("Cold outreach send", template, resume,
        user_id: user_id, company_id: company_id, template_id: template_id, resume_blob_id: resume_blob_id)
      return
    end

    mail = I18n.with_locale(locale) { JobApplicationMailer.cold_outreach(user, company, template, resume) }
    raw_email = mail.message.to_s

    sender = GmailSenderService.new(user)
    sender.send_email(raw_email)

    # Unlike Application, a Company can be recontacted over time, so we only
    # keep the most recent contact rather than a full send record - good
    # enough to show "last contacted" and to count against the daily cap
    # (see User#remaining_daily_sends). A full outreach history is Track D
    # territory, same as Application's own timeline.
    company.update!(last_contacted_at: Time.current, last_contacted_by: user)
  rescue StandardError => e
    Rails.logger.error "Failed to send cold outreach: #{e.message}"
    Honeybadger.notify(e, context: { company_id: company_id })
    raise e
  end
end
