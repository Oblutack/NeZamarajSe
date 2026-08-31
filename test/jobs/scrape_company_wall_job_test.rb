require "test_helper"

class ScrapeCompanyWallJobTest < ActiveJob::TestCase
  test "runs the CompanyWall scraper" do
    called = false
    fake_scraper = Object.new
    fake_scraper.define_singleton_method(:call) { called = true }

    stub_class_method(Scrapers::CompanyWallScraper, :new, fake_scraper) do
      ScrapeCompanyWallJob.perform_now
    end

    assert called
  end
end
