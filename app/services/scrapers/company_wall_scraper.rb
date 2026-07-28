# app/services/scrapers/company_wall_scraper.rb
require "nokogiri"
require "open-uri"

module Scrapers
  class CompanyWallScraper
    def initialize(page: 1)
      @page = page
      @url = "https://www.companywall.ba/pretraga?q=&djelatnost=62.01&page=#{@page}"

      # We must pass these headers so CompanyWall thinks we are a real human on Chrome
      @headers = {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36",
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.5"
      }
    end

    def call
      puts "🏢 Scraping CompanyWall Page #{@page}..."

      begin
        html = URI.open(@url, @headers)
        doc = Nokogiri::HTML(html)

        # Select all the company panels
        company_panels = doc.css("section.panel")
        puts "Found #{company_panels.count} companies on this page."

        company_panels.each do |panel|
          # Target the specific elements you found in the Inspector!
          name_element = panel.at_css("div.col-sm-11 a")
          address_element = panel.at_css("div.address-field")

          # Fallback just in case the 'a' tag is missing but the text is there
          name = name_element ? name_element.text.strip : panel.at_css("div.col-sm-11")&.text&.strip

          # The address usually has a newline (e.g. "Street 10 \n Sarajevo")
          raw_address = address_element ? address_element.text.strip.gsub(/\s+/, " ") : "Unknown"

          next if name.blank?

          # Find or initialize by name
          company = Company.find_or_initialize_by(name: name)
          company.industry_code = "62.01"
          company.address = raw_address
          company.is_cold_outreach = true

          if company.new_record?
            puts "🏢 New Target: #{name} | #{raw_address}"
            company.save!
          end

          # Be a polite bot
          sleep(rand(0.5..1.5))
        end

      rescue StandardError => e
        puts "❌ CompanyWall Scrape failed on page #{@page}: #{e.message}"
      end
    end
  end
end
