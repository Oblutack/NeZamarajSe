# config/initializers/sidekiq.rb

# We define a hash of our scheduled jobs
schedule = {
  "scrape_dzobs_daily" => {
    # Run every day at 3:00 AM (Cron syntax)
    "cron"  => "0 3 * * *",
    "class" => "ScrapeDzobsJob",
    "queue" => "default"
  },
  "send_radar_emails" => {
    "cron"  => "0 8 * * *", # 8:00 AM Server Time
    "class" => "SendDailyRadarJob",
    "queue" => "default"
  }
}

# Load the schedule into Sidekiq-Cron when the server starts
Sidekiq.configure_server do |config|
  Sidekiq::Cron::Job.load_from_hash(schedule)
end
