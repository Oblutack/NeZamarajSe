# app/jobs/check_for_replies_job.rb
class CheckForRepliesJob < ApplicationJob
  queue_as :default

  def perform
    Application.applied.where.not(gmail_thread_id: nil).find_each do |application|
      check(application)
    rescue StandardError => e
      # One user's stale token (they haven't re-granted the gmail.metadata
      # scope yet) or one bad thread shouldn't stop the rest of the batch
      # from being checked - log and move on instead of re-raising, unlike
      # every other job in this app (see CLAUDE.md).
      Rails.logger.error "Reply check failed for Application #{application.id}: #{e.message}"
      Honeybadger.notify(e, context: { application_id: application.id })
    end
  end

  private

  def check(application)
    sender = GmailSenderService.new(application.user)
    return unless sender.thread_has_reply?(application.gmail_thread_id)

    application.update!(status: "interviewing")
    application.application_events.create!(event_type: "reply_detected")
  end
end
