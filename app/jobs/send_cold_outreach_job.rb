# app/jobs/send_cold_outreach_job.rb
class SendColdOutreachJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, company_id, template_id, resume_blob_id)
    user = User.find(user_id)
    company = Company.find(company_id)
    template = user.cover_letter_templates.find(template_id)
    resume = user.resumes.find { |r| r.blob_id == resume_blob_id.to_i }

    mail = JobApplicationMailer.cold_outreach(user, company, template, resume)
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
