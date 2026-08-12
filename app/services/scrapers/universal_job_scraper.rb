# app/services/scrapers/universal_job_scraper.rb
require "nokogiri"
require "ferrum"

module Scrapers
  class UniversalJobScraper
    def initialize(config)
      @config = config
    end

    def call
      puts "🕷️ Starting Headless Universal Scraper for: #{@config.site_name}..."

      # 1. Boot up with a generous timeout and a fake human User-Agent
      browser = Ferrum::Browser.new(
        timeout: 30, # Give it plenty of time
        window_size: [ 1920, 1080 ],
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil,
          'disable-gpu': nil,
          'user-agent': "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
      )

      current_url = @config.url
      pages_scraped = 0
      max_pages = 5

      begin
        while current_url.present? && pages_scraped < max_pages
          puts "📄 Scraping Page #{pages_scraped + 1}: #{current_url}"

          # 2. Go to the URL (Ferrum will wait for the basic HTML to load)
          browser.goto(current_url)

          # 3. Wait 4 full seconds to guarantee React has painted the DOM
          sleep(4.0)

          # 4. Extract HTML
          doc = Nokogiri::HTML(browser.body)

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
            job = Job.find_or_initialize_by(url: job_url)‚‚‚‚
            job.title = title
            job.company = company
            job.description = "Scraped via Headless Chrome from #{@config.site_name}"

            if job.new_record?
              puts "   ✨ New Job: #{title} @ #{company.name}"
              job.save!
              ::AnalyzeJob.perform_later(job.id)
            end
          end

          # PAGINATION
          pages_scraped += 1

          if @config.next_page_selector.present?
            next_button = doc.at_css(@config.next_page_selector)
            if next_button && next_button["href"]
              current_url = next_button["href"].start_with?("http") ? next_button["href"] : "#{URI.parse(@config.url).scheme}://#{URI.parse(@config.url).host}#{next_button['href']}"
            else
              current_url = nil
            end
          else
            current_url = nil
          end

          sleep(rand(1.0..3.0))
        end

        puts "✅ Finished scraping #{@config.site_name}. Total pages: #{pages_scraped}"
      rescue StandardError => e
        puts "❌ Scraping failed: #{e.message}"
      ensure
        puts "🧹 Shutting down headless browser..."
        browser.quit
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
      return card["href"] if selector == "self"
      element = card.at_css(selector)
      element ? element["href"] : nil
    end
  end
end
