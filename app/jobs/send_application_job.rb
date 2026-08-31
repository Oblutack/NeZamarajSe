# app/jobs/send_application_job.rb
class SendApplicationJob < ApplicationJob
  # We use the 'mailers' queue so it doesn't block our scraping jobs
  queue_as :mailers

  def perform(application_id, template_id, resume_blob_id)
    application = Application.find(application_id)
    user = application.user
    job = application.job

    template = user.cover_letter_templates.find(template_id)

    # ActiveStorage lookup by blob ID
    resume = user.resumes.find { |r| r.blob_id == resume_blob_id.to_i }

    # Generate the raw email
    raw_email = JobApplicationMailer.apply(user, job, template, resume).message.to_s

    # Send it via Google API
    sender = GmailSenderService.new(user)
    sender.send_email(raw_email)

    # Only now that Gmail has confirmed the send do we mark it applied.
    application.update!(status: "applied", applied_at: Time.current)

  rescue StandardError => e
    # If something fails (e.g., token revoked), log it so Sidekiq can retry
    Rails.logger.error "Failed to send application: #{e.message}"
    Honeybadger.notify(e, context: { application_id: application_id })
    raise e
  end
end
