# app/services/scrapers/it_karijera_scraper.rb
require "net/http"
require "json"
require "uri"

module Scrapers
  # IT Karijera (itkarijera.ba) is BIT Alliance's (the Bosnian IT industry
  # association) own IT-only job board. Unlike the other sources it's not
  # scraped as HTML: the site is an Angular SPA whose job cards navigate via
  # client-side router-link clicks rather than <a href> tags and never render
  # a company name as text (only a logo image) - not a good fit for
  # UniversalJobScraper's CSS-selector model. It's backed by a clean, public,
  # unauthenticated JSON API instead (found via the network tab while the SPA
  # loaded), which is both easier and more reliable to read directly.
  class ItKarijeraScraper
    API_URL = "https://api.itkarijera.ba/api/industry/CompanyJob/getlistbyquery"
    PAGE_SIZE = 40

    def call
      puts "🕷️ Starting IT Karijera API Scraper..."
      page = 0
      total_count = nil

      loop do
        uri = URI("#{API_URL}?page=#{page}&pageSize=#{PAGE_SIZE}")
        response = Net::HTTP.get(uri)
        data = JSON.parse(response)
        total_count ||= data["totalCount"].to_i
        items = data["items"] || []
        break if items.empty?

        puts "📄 Page #{page + 1}: #{items.count} jobs"

        items.each do |item|
          title = item["title"]&.strip
          company_name = item["companyName"]&.strip
          # signUpLink is the company's own posting/apply page, not an
          # itkarijera.ba URL - AnalyzeJob will read it directly, same as it
          # would for a job scraped from any other source.
          job_url = item["signUpLink"].presence

          next if title.blank? || company_name.blank? || job_url.blank?

          company = Company.find_or_create_by!(name: company_name)

          # Same aggregator-style dedup fallback UniversalJobScraper uses -
          # a company reposting the same title shouldn't create a duplicate.
          next if Job.exists?(company_id: company.id, title: title)

          job = Job.find_or_initialize_by(url: job_url)
          job.title = title
          job.company = company
          job.description = "Scraped via IT Karijera API"

          if job.new_record?
            puts "   ✨ New Job: #{title} @ #{company.name}"
            job.save!
            ::AnalyzeJob.perform_later(job.id)
          end
        end

        page += 1
        break if page * PAGE_SIZE >= total_count
        sleep(rand(0.5..1.5))
      end

      puts "✅ Finished scraping IT Karijera."
    rescue StandardError => e
      puts "❌ IT Karijera scraper failed: #{e.message}"
    end
  end
end
