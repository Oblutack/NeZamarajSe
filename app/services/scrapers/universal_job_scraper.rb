# app/services/scrapers/universal_job_scraper.rb
require "nokogiri"
require "ferrum"

module Scrapers
  class UniversalJobScraper
    include CrossPostingRecordable

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

          # 3. Wait for network activity (XHR/fetch calls that hydrate the page) to settle,
          # rather than guessing a fixed delay that's too short for slow SPAs and wastes
          # time on fast ones.
          browser.network.wait_for_idle(timeout: 10)
          sleep(0.5)

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

            # Aggregators (e.g. Jooble) link to their own redirect URL rather than the
            # original posting, so the same job re-appears under a different job_url.
            # Exact-URL dedup above can't catch that - fall back to title+company.
            next if record_or_skip_duplicate?(company, title, @config.site_name, job_url)

            job = Job.find_or_initialize_by(url: job_url)
            job.title = title
            job.company = company
            job.description = "Scraped via Headless Chrome from #{@config.site_name}"
            job.location = extract_text(card, @config.location_selector)

            # The listing itself is the source of truth for its own deadline -
            # more reliable than AiJobAnalyzerService guessing from prose, and
            # free. Re-set on every scrape (not just job.new_record?) so an
            # extended deadline on a re-encountered listing stays current;
            # harmless no-op when the date hasn't changed.
            expiry = extract_expiry_date(card, @config.date_selector)
            job.expires_at = expiry if expiry.present?

            if job.new_record?
              puts "   ✨ New Job: #{title} @ #{company.name}"
              job.save!
              ::AnalyzeJob.perform_later(job.id)
            elsif job.changed?
              job.save!
            end

            record_job_source!(job, @config.site_name, job_url)
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
      return nil unless element

      # Some sites (e.g. MojPosao's featured cards) only carry the company name as
      # an <img alt="..."> logo rather than visible text.
      return element["alt"]&.strip if element.name == "img"

      text = element.text.strip
      text.presence || element["alt"]&.strip
    end

    def extract_link(card, selector)
      return nil if selector.blank?
      return card["href"] if selector == "self"
      element = card.at_css(selector)
      element ? element["href"] : nil
    end

    # Two formats seen in the wild: a <time datetime="2026-09-04T21:59:59Z">
    # element (MojPosao - machine-readable, just parse the attribute), or a
    # plain-text date range like Klix's "02.09. – 02.10.2026" (take the
    # *last* DD.MM.YYYY in the text - the range's end, i.e. the deadline).
    def extract_expiry_date(card, selector)
      return nil if selector.blank?
      element = card.at_css(selector)
      return nil unless element

      if element.name == "time" && element["datetime"].present?
        return Date.parse(element["datetime"])
      end

      match = element.text.scan(/(\d{2})\.(\d{2})\.(\d{4})/).last
      return nil unless match

      day, month, year = match
      Date.new(year.to_i, month.to_i, day.to_i)
    rescue ArgumentError
      nil
    end
  end
end
