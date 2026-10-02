# app/jobs/send_daily_radar_job.rb
class SendDailyRadarJob < ApplicationJob
  queue_as :default

  def perform
    # Only look at users who opted in
    users = User.joins(:user_preference).where(user_preferences: { receive_daily_alerts: true })

    users.each do |user|
      preference = user.user_preference
      next if preference.keyword_array.empty?

      # Find jobs scraped in the last 24 hours. Job.scraped, not Job: this is a
      # digest of new postings from the shared pool, and an unscoped query also
      # picked up jobs another user had typed in by hand (private to them - see
      # Job.visible_to), emailing their title and company to everyone whose
      # keywords happened to match. A user's own private entries aren't echoed
      # back either: they just added it, it isn't news.
      recent_jobs = Job.scraped.includes(:company).where("created_at >= ?", 24.hours.ago)

      # Filter them by the user's keywords
      conditions = preference.keyword_array.map { |kw| "title ILIKE ?" }.join(" OR ")
      values = preference.keyword_array.map { |kw| "%#{kw}%" }
      matched_jobs = recent_jobs.where(conditions, *values)

      # Only send the email if we actually found matches!
      if matched_jobs.any?
        # to_a, not the relation itself: deliver_later has to serialise its
        # arguments (records go over as GlobalIDs), and an ActiveRecord::Relation
        # isn't a supported argument type - it raised ActiveJob::SerializationError
        # for the first user with any match, which aborted the whole batch for
        # every user after them.
        RadarMailer.daily_summary(user, matched_jobs.to_a).deliver_later
      end
    end
  end
end
