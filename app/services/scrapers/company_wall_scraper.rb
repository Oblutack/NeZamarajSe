# app/services/scrapers/company_wall_scraper.rb
require "nokogiri"
require "ferrum"

module Scrapers
  class CompanyWallScraper
    # We default to 3 pages for testing, but you can pass (max_pages: 50) later!
    def initialize(max_pages: 3)
      @max_pages = max_pages
      @base_url = "https://www.companywall.ba/pretraga?q=&djelatnost=62.01&page="
    end

    def call
      puts "🏢 Starting Headless CompanyWall Scraper..."

      browser = Ferrum::Browser.new(
        timeout: 30,
        window_size: [ 1920, 1080 ],
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil,
          'disable-gpu': nil,
          'disable-blink-features': "AutomationControlled", # Sneak past basic bot-checks
          'user-agent': "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
      )

      begin
        (1..@max_pages).each do |page|
          url = "#{@base_url}#{page}"
          puts "📄 Scraping Page #{page}: #{url}"

          browser.goto(url)

          # Cloudflare's interstitial redirects after a short client-side timer (no
          # network activity to wait on yet), then the real page loads behind it -
          # wait for that timer, then wait for the real page's network activity to
          # settle instead of guessing how long that takes.
          sleep(3.5)
          browser.network.wait_for_idle(timeout: 15)

          doc = Nokogiri::HTML(browser.body)
          company_panels = doc.css("section.panel")

          if company_panels.empty?
            screenshot_path = Rails.root.join("tmp", "companywall_blocked.png")
            puts "⚠️ Found 0 companies. We might be blocked by a Captcha. Taking screenshot at #{screenshot_path}..."
            browser.screenshot(path: screenshot_path.to_s)
            break # Stop the loop so we don't get our IP banned
          end

          puts "   Found #{company_panels.count} companies on this page."

          company_panels.each do |panel|
            name_element = panel.at_css("div.col-sm-11 a")
            address_element = panel.at_css("div.address-field")

            name = name_element ? name_element.text.strip : panel.at_css("div.col-sm-11")&.text&.strip
            raw_address = address_element ? address_element.text.strip.gsub(/\s+/, " ") : "Unknown"

            next if name.blank?

            company = Company.find_or_initialize_by(name: name)
            company.industry_code = "62.01"
            company.address = raw_address
            company.is_cold_outreach = true

            if company.new_record?
              puts "   🏢 New Target: #{name} | #{raw_address}"
              company.save!
            end
          end

          # Be very polite to CompanyWall's servers before clicking Next Page
          sleep(rand(2.0..4.0))
        end

        puts "✅ Finished scraping CompanyWall."
      rescue StandardError => e
        puts "❌ Scraper crashed: #{e.message}"
      ensure
        puts "🧹 Shutting down headless browser..."
        browser.quit
      end
    end
  end
end
