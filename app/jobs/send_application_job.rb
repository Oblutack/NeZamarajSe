# app/jobs/send_application_job.rb
class SendApplicationJob < ApplicationJob
  # We use the 'mailers' queue so it doesn't block our scraping jobs
  queue_as :mailers

  def perform(application_id, template_id, resume_blob_id, locale = I18n.default_locale.to_s)
    application = Application.find(application_id)
    user = application.user
    job = application.job

    template = user.cover_letter_templates.find(template_id)

    # ActiveStorage lookup by blob ID
    resume = user.resumes.find { |r| r.blob_id == resume_blob_id.to_i }

    # Generate the raw email - locale scoped to whatever the user had active
    # when they hit send, so the subject line matches what they previewed
    # (a background job otherwise runs outside any request's session locale).
    mail = I18n.with_locale(locale) { JobApplicationMailer.apply(user, job, template, resume) }
    raw_email = mail.message.to_s

    # Send it via Google API
    sender = GmailSenderService.new(user)
    response = sender.send_email(raw_email)

    # Only now that Gmail has confirmed the send do we mark it applied - and
    # record what was actually sent. sent_recipient is the *intended* target
    # (application.intended_recipient), not necessarily mail.to: while
    # dry_run_emails is on, mail.to is the user's own inbox regardless, but
    # that's not the meaningful thing to show on the CRM card.
    application.update!(
      status: "applied",
      applied_at: Time.current,
      sent_recipient: application.intended_recipient,
      sent_subject: mail.subject,
      sent_body: template.render_content(job),
      gmail_message_id: response.id,
      gmail_thread_id: response.thread_id
    )

  rescue StandardError => e
    # If something fails (e.g., token revoked), log it so Sidekiq can retry
    Rails.logger.error "Failed to send application: #{e.message}"
    Honeybadger.notify(e, context: { application_id: application_id })
    raise e
  end
end
