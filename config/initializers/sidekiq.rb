# config/initializers/sidekiq.rb

# We define a hash of our scheduled jobs
schedule = {
  "scrape_job_boards_daily" => {
    # Run every day at 3:00 AM (Cron syntax)
    "cron"  => "0 3 * * *",
    "class" => "ScrapeJobBoardsJob",
    "queue" => "default"
  },
  "send_radar_emails" => {
    "cron"  => "0 8 * * *", # 8:00 AM Server Time
    "class" => "SendDailyRadarJob",
    "queue" => "default"
  },
  "scrape_company_wall_weekly" => {
    # Cold-outreach company discovery - weekly, not daily, to stay light on a
    # Cloudflare-protected target (see CompanyWallScraper).
    "cron"  => "0 4 * * 1", # Monday 4:00 AM
    "class" => "ScrapeCompanyWallJob",
    "queue" => "default"
  },
  "scrape_it_karijera_daily" => {
    # IT Karijera's own JSON API, not a ScraperConfig row - see ItKarijeraScraper.
    "cron"  => "30 3 * * *", # 3:30 AM Server Time
    "class" => "ScrapeItKarijeraJob",
    "queue" => "default"
  },
  "check_for_replies" => {
    # Every 4 hours, not more often - reply detection isn't urgent, and this
    # is one Gmail API call per "applied" application with a known thread.
    "cron"  => "0 */4 * * *",
    "class" => "CheckForRepliesJob",
    "queue" => "default"
  }
}

# Load the schedule into Sidekiq-Cron when the server starts
Sidekiq.configure_server do |config|
  Sidekiq::Cron::Job.load_from_hash(schedule)
end
