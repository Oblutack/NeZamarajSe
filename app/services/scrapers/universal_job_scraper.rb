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

      current_url = @config.url
      pages_scraped = 0
      max_pages = 5 # Safety limit

      while current_url.present? && pages_scraped < max_pages
        puts "📄 Scraping Page #{pages_scraped + 1}: #{current_url}"

        begin
          html = URI.open(current_url, "User-Agent" => "Mozilla/5.0")
          doc = Nokogiri::HTML(html)

          job_cards = doc.css(@config.card_selector)
          puts "   Found #{job_cards.count} jobs on this page."

          job_cards.each do |card|
            title = extract_text(card, @config.title_selector)
            company_name = extract_text(card, @config.company_selector)
            relative_url = extract_link(card, @config.link_selector)

            next if title.blank? || company_name.blank? || relative_url.blank?

            base_url = URI.parse(@config.url)
            job_url = relative_url.start_with?("http") ? relative_url : "#{base_url.scheme}://#{base_url.host}#{relative_url}"

            company = Company.find_or_create_by!(name: company_name)
            job = Job.find_or_initialize_by(url: job_url)
            job.title = title
            job.company = company
            job.description = "Scraped from #{@config.site_name}"

            if job.new_record?
              puts "   ✨ New Job: #{title} @ #{company.name}"
              job.save!
              ::AnalyzeJob.perform_later(job.id)
            end

            sleep(rand(0.5..1.5))
          end

          # PAGINATION LOGIC
          pages_scraped += 1

          if @config.next_page_selector.present?
            next_button = doc.at_css(@config.next_page_selector)
            if next_button && next_button["href"]
              current_url = next_button["href"].start_with?("http") ? next_button["href"] : "#{URI.parse(@config.url).scheme}://#{URI.parse(@config.url).host}#{next_button['href']}"
            else
              current_url = nil # No more pages found
            end
          else
            current_url = nil # Pagination not configured
          end

        rescue StandardError => e
          puts "❌ Scraping failed on page #{pages_scraped + 1}: #{e.message}"
          current_url = nil # Break the loop on failure
        end
      end

      puts "✅ Finished scraping #{@config.site_name}. Total pages: #{pages_scraped}"
    end

    private

    def extract_text(card, selector)
      return nil if selector.blank?
      element = card.at_css(selector)
      element ? element.text.strip : nil
    end

    def extract_link(card, selector)
      return nil if selector.blank?
      return card["href"] if selector == "self"
      element = card.at_css(selector)
      element ? element["href"] : nil
    end
  end
end
