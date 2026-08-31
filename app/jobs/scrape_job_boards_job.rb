# app/jobs/scrape_job_boards_job.rb
class ScrapeJobBoardsJob < ApplicationJob
  queue_as :default

  def perform(*args)
    ScraperConfig.where(active: true).find_each do |config|
      Scrapers::UniversalJobScraper.new(config).call
    end
  end
end
