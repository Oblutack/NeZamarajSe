# app/services/email_finder_service.rb
require "net/http"
require "json"
require "uri"

class EmailFinderService
  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
    @hunter_api_key = Rails.application.credentials.dig(:hunter, :api_key)
  end

  def call
    # 1. Resolve the EXACT domain using Clearbit
    domain = resolve_domain

    unless domain
      puts "❌ Could not resolve domain for #{@company.name}"
      return
    end

    if quota_exhausted?
      puts "⏸️ Hunter.io monthly quota (#{Rails.application.config.hunter_monthly_quota}) reached - skipping lookup for #{@company.name}"
      return
    end

    puts "🔍 Searching Hunter.io for verified domain: #{domain}..."

    # 2. Ask Hunter.io for the emails for that specific domain - record the
    # attempt regardless of what it returns, since a lookup that comes back
    # empty still spent one of Hunter's metered calls.
    HunterLookup.create!(company: @company)
    url = URI("https://api.hunter.io/v2/domain-search?domain=#{domain}&api_key=#{@hunter_api_key}")
    response = Net::HTTP.get(url)
    data = JSON.parse(response)

    # 3. Process the results
    if data["data"] && data["data"]["emails"]&.any?
      best_email = find_best_email(data["data"]["emails"])

      if best_email
        @company.update!(primary_email: best_email, domain: domain)
        puts "✅ Found Target Email: #{best_email} for #{@company.name} (#{domain})"
      else
        puts "⚠️ Found emails for #{domain}, but none matched HR criteria."
      end
    else
      puts "❌ Hunter.io found no emails for #{domain}"
    end
  end

  private

  def quota_exhausted?
    HunterLookup.where(created_at: Time.current.all_month).count >= Rails.application.config.hunter_monthly_quota
  end

  def resolve_domain
    if @company.website.present?
      url = @company.website.start_with?("http") ? @company.website : "https://#{@company.website}"
      return URI.parse(url).host&.sub(/^www\./, "") rescue nil
    end

    # ANTI-COLLISION & SANITIZATION:
    # 1. Remove quotes (e.g. "KLIX" -> KLIX)
    # 2. Remove legal suffixes (d.o.o., d.d., doo) ignoring case
    clean_name = @company.name.gsub(/["']/, "")
                              .gsub(/(?i)\b(d\.o\.o\.|d\.o\.o|d\.d\.|d\.d)\b/, "")
                              .strip

    puts "🌐 Asking Clearbit to resolve domain for: #{clean_name}..."

    query = URI.encode_www_form_component(clean_name)
    url = URI("https://autocomplete.clearbit.com/v1/companies/suggest?query=#{query}")

    begin
      response = Net::HTTP.get(url)
      results = JSON.parse(response)

      if results.any?
        found_domain = results.first["domain"]
        puts "   -> Clearbit says it is: #{found_domain}"
        return found_domain
      end
    rescue StandardError => e
      puts "   -> Clearbit API failed: #{e.message}"
      Honeybadger.notify(e, context: { company_id: @company.id, company_name: @company.name })
    end

    nil
  end

  def find_best_email(emails)
    keywords = [ "hr", "career", "job", "recruit", "info", "hello", "contact" ]

    target = emails.find do |email_data|
      local_part = email_data["value"].split("@").first.downcase
      keywords.any? { |kw| local_part.include?(kw) }
    end

    target ? target["value"] : emails.first["value"]
  end
end
