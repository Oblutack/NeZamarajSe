# app/services/email_finder_service.rb
require "net/http"
require "json"

class EmailFinderService
  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
    @api_key = Rails.application.credentials.dig(:hunter, :api_key)
  end

  def call
    # We need a domain to search. If we only have a URL, we parse it.
    # Example: "https://klika.ba/jobs" -> "klika.ba"
    domain = extract_domain(@company.domain || @company.website || guess_domain_from_name)
    return unless domain

    puts "🔍 Searching Hunter.io for domain: #{domain}..."

    url = URI("https://api.hunter.io/v2/domain-search?domain=#{domain}&api_key=#{@api_key}")
    response = Net::HTTP.get(url)
    data = JSON.parse(response)

    if data["data"] && data["data"]["emails"].any?
      # Find emails that belong to HR, recruiting, or general info
      best_email = find_best_email(data["data"]["emails"])

      if best_email
        @company.update!(primary_email: best_email)
        puts "✅ Found Target Email: #{best_email} for #{@company.name}"
      else
        puts "⚠️ Found emails, but none matched HR/Info criteria for #{@company.name}"
      end
    else
      puts "❌ Hunter.io found no emails for #{domain}"
    end
  end

  private

  def extract_domain(raw_string)
    return nil if raw_string.blank?

    # If the string doesn't have http://, add it so URI parser understands it's a website!
    url = raw_string.start_with?("http") ? raw_string : "https://#{raw_string}"

    begin
      URI.parse(url).host&.sub(/^www\./, "")
    rescue URI::InvalidURIError
      nil
    end
  end

  def guess_domain_from_name
    # If we don't have a website, guess the domain (e.g., "Symphony" -> "symphony.ba")
    "#{@company.name.downcase.gsub(/[^a-z0-9]/, '')}.ba"
  end

  def find_best_email(emails)
    # We prioritize HR, careers, jobs, or info emails.
    keywords = [ "hr", "career", "job", "recruit", "info", "hello", "contact" ]

    target = emails.find do |email_data|
      local_part = email_data["value"].split("@").first.downcase
      keywords.any? { |kw| local_part.include?(kw) }
    end

    # If we found an HR email, return it. Otherwise, just return the first email Hunter found.
    target ? target["value"] : emails.first["value"]
  end
end
