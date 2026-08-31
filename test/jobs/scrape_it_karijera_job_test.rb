require "test_helper"

class ScrapeItKarijeraJobTest < ActiveJob::TestCase
  test "runs the IT Karijera scraper" do
    called = false
    fake_scraper = Object.new
    fake_scraper.define_singleton_method(:call) { called = true }

    stub_class_method(Scrapers::ItKarijeraScraper, :new, fake_scraper) do
      ScrapeItKarijeraJob.perform_now
    end

    assert called
  end
end
