# app/jobs/send_radar_digest_job.rb
#
# One user's daily radar digest, sent through their own Gmail account - the same
# transport as every other mail this app sends (see GmailSenderService). Queued
# per user by SendDailyRadarJob rather than looping inside it, so one revoked
# token or one Gmail hiccup can't take down everyone else's digest.
#
# RadarMailer is only used to *render* here (`.message`), never to deliver: the
# app has no ActionMailer delivery method configured in production, and the
# digest used to go through `deliver_later`, which has nowhere to send to.
class SendRadarDigestJob < ApplicationJob
  queue_as :mailers

  # A digest is today's news, so unlike the application sends - which have to
  # go out eventually and are left to Sidekiq's three-week retry schedule - it
  # gets a few quick retries and is then dropped. Re-sending a stale "new jobs"
  # mail days later would be wrong, and a revoked token will never recover on
  # its own, so 25 retries would only be noise. Giving a block means the final
  # failure is *not* re-raised back to Sidekiq (which would retry it all again).
  retry_on StandardError, wait: 15.minutes, attempts: 3 do |job, error|
    Rails.logger.error "Radar digest for user #{job.arguments.first} abandoned after 3 attempts: #{error.message}"
  end

  def perform(user_id, job_ids)
    user = User.find_by(id: user_id)
    # Gone, or disconnected from Google, since the fan-out ran - nothing to do.
    return unless user&.gmail_connected?

    # Re-read through Job.scraped even though the fan-out already did: ids are
    # all this job is handed, and the digest must never carry a job another user
    # typed in by hand (see Job.visible_to).
    jobs = Job.scraped.includes(:company).where(id: job_ids).order(created_at: :desc).to_a
    return if jobs.empty?

    mail = RadarMailer.daily_summary(user, jobs).message
    GmailSenderService.new(user).send_email(mail.to_s)
  rescue StandardError => e
    Rails.logger.error "Failed to send radar digest: #{e.message}"
    Honeybadger.notify(e, context: { user_id: user_id, job_ids: job_ids })
    raise e
  end
end
