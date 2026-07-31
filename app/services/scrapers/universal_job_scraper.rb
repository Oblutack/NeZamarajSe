# app/services/scrapers/universal_job_scraper.rb
require "nokogiri"
require "open-uri"

module Scrapers
  class UniversalJobScraper
    def initialize(config)
      @config = config
    end

    def call
      puts "🕷️ Starting Universal Scraper for: #{@config.site_name}..."

      begin
        html = URI.open(@config.url, "User-Agent" => "Mozilla/5.0")
        doc = Nokogiri::HTML(html)

        job_cards = doc.css(@config.card_selector)
        puts "Found #{job_cards.count} jobs on #{@config.site_name}."

        job_cards.each do |card|
          title = extract_text(card, @config.title_selector)
          company_name = extract_text(card, @config.company_selector)
          relative_url = extract_link(card, @config.link_selector)

          next if title.blank? || company_name.blank? || relative_url.blank?

          # Clean up the URL (handles https://, http://, or relative paths like /job/123)
          base_url = URI.parse(@config.url)
          job_url = relative_url.start_with?("http") ? relative_url : "#{base_url.scheme}://#{base_url.host}#{relative_url}"

          # Insert into DB
          company = Company.find_or_create_by!(name: company_name)
          job = Job.find_or_initialize_by(url: job_url)
          job.title = title
          job.company = company
          job.description = "Scraped from #{@config.site_name}"

          if job.new_record?
            puts "✨ New Job: #{title} @ #{company.name}"
            job.save!

            # Send to the AI Pipeline!
            ::AnalyzeJob.perform_later(job.id)
          end

          sleep(rand(0.5..1.5))
        end
      rescue StandardError => e
        puts "❌ Scraping failed for #{@config.site_name}: #{e.message}"
      end
    end

    private

    def extract_text(card, selector)
      return nil if selector.blank?
      element = card.at_css(selector)
      element ? element.text.strip : nil
    end

    def extract_link(card, selector)
      return nil if selector.blank?
      # If the card ITSELF is the 'a' tag, we just grab its href attribute
      return card["href"] if selector == "self"

      # Otherwise, find the inner 'a' tag
      element = card.at_css(selector)
      element ? element["href"] : nil
    end
  end
end
