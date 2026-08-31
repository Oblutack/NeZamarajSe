# app/jobs/scrape_company_wall_job.rb
class ScrapeCompanyWallJob < ApplicationJob
  queue_as :default

  def perform(*args)
    Scrapers::CompanyWallScraper.new.call
  end
end
