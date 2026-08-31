require "test_helper"

class ScraperConfigTest < ActiveSupport::TestCase
  test "only active configs are picked up for scraping" do
    active_configs = ScraperConfig.where(active: true)

    assert_includes active_configs, scraper_configs(:one)
    assert_not_includes active_configs, scraper_configs(:two)
  end
end
