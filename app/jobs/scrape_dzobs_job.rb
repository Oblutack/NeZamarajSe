# app/jobs/scrape_dzobs_job.rb
class ScrapeDzobsJob < ApplicationJob
  queue_as :default

  def perform(*args)
    # This is where we call our Service Object!
    Scrapers::ItJobBoardScraper.call
  end
end