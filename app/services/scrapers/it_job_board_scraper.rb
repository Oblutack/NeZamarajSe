# app/services/scrapers/it_job_board_scraper.rb
require "nokogiri"
require "open-uri"

module Scrapers
  class ItJobBoardScraper
    def self.call
      new.call
    end

    def call
      # Target the specific IT category on dzobs (or whatever URL you were inspecting)
      url = "https://dzobs.com/poslovi/it-software"

      puts "🕷️ Starting Dzobs IT Scraper..."

      begin
        # Fetch HTML as a standard browser
        html = URI.open(url, "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        doc = Nokogiri::HTML(html)

        # CSS Attribute Selector: Find all 'a' tags where href starts with '/posao/'
        job_cards = doc.css("a[href^='/posao/']")
        puts "Found #{job_cards.count} jobs on the page."

        job_cards.each do |card|
          # Use at_css to find the FIRST matching element inside the card
          title_element = card.at_css("h4")
          company_element = card.at_css("p.text-sm")

          # Safely extract text (in case the HTML structure slightly changes on an ad)
          title = title_element&.text&.strip
          company_name = company_element&.text&.strip
          relative_url = card["href"] # Since the card IS the 'a' tag, we just ask for its href

          # Skip if vital data is missing
          next if title.blank? || company_name.blank? || relative_url.blank?

          job_url = relative_url.start_with?("http") ? relative_url : "https://dzobs.com#{relative_url}"

          # Database Insertion
          company = Company.find_or_create_by!(name: company_name)

          job = Job.find_or_initialize_by(url: job_url)
          job.title = title
          job.company = company
          job.description = "Scraped from Dzobs.com"

          if job.new_record?
            puts "✨ New Job: #{title} @ #{company.name}"
            job.save!
          end
          # This makes the bot look like a human reading the page
          sleep(rand(1.0..3.0))
        end

        puts "✅ Scraping complete!"
      rescue StandardError => e
        puts "❌ Scraping failed: #{e.message}"
      end
    end
  end
end
