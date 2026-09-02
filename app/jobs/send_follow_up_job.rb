# app/jobs/send_follow_up_job.rb
class SendFollowUpJob < ApplicationJob
  queue_as :mailers

  def perform(application_id, template_id, resume_blob_id)
    application = Application.find(application_id)
    user = application.user
    job = application.job

    template = user.cover_letter_templates.find(template_id)
    resume = user.resumes.find { |r| r.blob_id == resume_blob_id.to_i }

    mail = JobApplicationMailer.follow_up(user, job, template, resume)
    raw_email = mail.message.to_s

    sender = GmailSenderService.new(user)
    sender.send_email(raw_email)

    # Doesn't touch `status` - a follow-up doesn't change where the
    # application sits on the board, just resets the follow-up clock (see
    # Application#needs_follow_up?) and leaves a record in the timeline.
    application.update!(last_followed_up_at: Time.current)
    application.application_events.create!(event_type: "follow_up_sent")
  rescue StandardError => e
    Rails.logger.error "Failed to send follow-up: #{e.message}"
    Honeybadger.notify(e, context: { application_id: application_id })
    raise e
  end
end
