require "test_helper"

class ScrapeJobBoardsJobTest < ActiveJob::TestCase
  test "scrapes every active ScraperConfig and skips inactive ones" do
    scraped_config_ids = []
    fake_scraper = Object.new
    fake_scraper.define_singleton_method(:call) { true }

    stub_class_method(Scrapers::UniversalJobScraper, :new, ->(config) {
      scraped_config_ids << config.id
      fake_scraper
    }) do
      ScrapeJobBoardsJob.perform_now
    end

    assert_equal [ scraper_configs(:one).id ], scraped_config_ids
  end
end
