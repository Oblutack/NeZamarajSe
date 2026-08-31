# app/jobs/scrape_it_karijera_job.rb
class ScrapeItKarijeraJob < ApplicationJob
  queue_as :default

  def perform(*args)
    Scrapers::ItKarijeraScraper.new.call
  end
end
