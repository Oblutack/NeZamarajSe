require "test_helper"

class Scrapers::UniversalJobScraperTest < ActiveSupport::TestCase
  setup do
    @scraper = Scrapers::UniversalJobScraper.new(scraper_configs(:one))
  end

  def card(html)
    Nokogiri::HTML.fragment(html).at_css("div")
  end

  test "extract_expiry_date reads a <time datetime> attribute directly" do
    node = card(%(<div><time datetime="2026-09-04T21:59:59.000Z">04. 09. 2026.</time></div>))

    assert_equal Date.new(2026, 9, 4), @scraper.send(:extract_expiry_date, node, "time")
  end

  test "extract_expiry_date takes the last DD.MM.YYYY in a plain-text date range" do
    node = card(%(<div><span>02.09. – 02.10.2026</span></div>))

    assert_equal Date.new(2026, 10, 2), @scraper.send(:extract_expiry_date, node, "span")
  end

  test "extract_expiry_date returns nil for an unmatched selector" do
    node = card("<div><span>no date here</span></div>")

    assert_nil @scraper.send(:extract_expiry_date, node, ".missing")
  end

  test "extract_expiry_date returns nil rather than raising on an invalid date" do
    node = card(%(<div><span>31.02.2026</span></div>)) # February 31st doesn't exist

    assert_nil @scraper.send(:extract_expiry_date, node, "span")
  end

  test "extract_text reads the location out of a simple element" do
    node = card(%(<div><a href="/grad/sarajevo">Sarajevo</a></div>))

    assert_equal "Sarajevo", @scraper.send(:extract_text, node, "a")
  end
end
