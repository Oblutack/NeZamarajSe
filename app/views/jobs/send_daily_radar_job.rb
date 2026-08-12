# app/jobs/send_daily_radar_job.rb
class SendDailyRadarJob < ApplicationJob
  queue_as :default

  def perform
    # Only look at users who opted in
    users = User.joins(:user_preference).where(user_preferences: { receive_daily_alerts: true })

    users.each do |user|
      preference = user.user_preference
      next if preference.keyword_array.empty?

      # Find jobs scraped in the last 24 hours
      recent_jobs = Job.includes(:company).where("created_at >= ?", 24.hours.ago)

      # Filter them by the user's keywords
      conditions = preference.keyword_array.map { |kw| "title ILIKE ?" }.join(" OR ")
      values = preference.keyword_array.map { |kw| "%#{kw}%" }
      matched_jobs = recent_jobs.where(conditions, *values)

      # Only send the email if we actually found matches!
      if matched_jobs.any?
        RadarMailer.daily_summary(user, matched_jobs).deliver_later
      end
    end
  end
end