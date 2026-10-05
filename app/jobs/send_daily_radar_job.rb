# app/jobs/send_daily_radar_job.rb
#
# The scheduled half of the daily digest (sidekiq-cron, 08:00): works out which
# new jobs match each opted-in user's keywords and queues a SendRadarDigestJob
# for each. It sends nothing itself - see SendRadarDigestJob for why per user.
class SendDailyRadarJob < ApplicationJob
  queue_as :default

  def perform
    # The global kill switch covers every outbound mail, not only application
    # sends: the digest also leaves through the user's own Gmail account.
    unless Rails.application.config.sending_enabled
      Rails.logger.info "SendDailyRadarJob skipped - sending is disabled (SENDING_ENABLED)"
      return
    end

    # Only look at users who opted in
    users = User.joins(:user_preference).where(user_preferences: { receive_daily_alerts: true })

    users.find_each do |user|
      preference = user.user_preference
      next if preference.keyword_array.empty?

      # The digest goes out through the user's own Gmail, so someone who signed
      # up with email + password has no way to receive it.
      next unless user.gmail_connected?

      # Jobs scraped in the last 24 hours. Job.scraped, not Job: this is a
      # digest of new postings from the shared pool, and an unscoped query also
      # picked up jobs another user had typed in by hand (private to them - see
      # Job.visible_to), emailing their title and company to everyone whose
      # keywords happened to match. A user's own private entries aren't echoed
      # back either: they just added it, it isn't news.
      recent_jobs = Job.scraped.where("created_at >= ?", 24.hours.ago)

      # Filter them by the user's keywords
      conditions = preference.keyword_array.map { |kw| "title ILIKE ?" }.join(" OR ")
      values = preference.keyword_array.map { |kw| "%#{kw}%" }
      job_ids = recent_jobs.where(conditions, *values).order(created_at: :desc).pluck(:id)

      # Only send the email if we actually found matches!
      SendRadarDigestJob.perform_later(user.id, job_ids) if job_ids.any?
    end
  end
end
