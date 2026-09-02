# app/services/ai_job_analyzer_service.rb
require "open-uri"
require "nokogiri"

class AiJobAnalyzerService
  # A handful of jobs link to domains that are dead/very slow (e.g. a defunct
  # regional job-aggregator redirect) and were eating a full 60s each - the
  # default Net::HTTP open/read timeout - before failing. 8s to connect, 12s
  # to read is generous for a job posting page and keeps a bad link from
  # stalling the whole enrichment queue behind it.
  OPEN_TIMEOUT = 8
  READ_TIMEOUT = 12

  # Matches a plain-text email as a fallback for pages that print the address
  # as text rather than an <a href="mailto:"> link.
  EMAIL_REGEX = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/

  def self.call(job)
    new(job).call
  end

  def initialize(job)
    @job = job
    @client = OpenAI::Client.new
  end

  def call
    puts "🤖 AI analyzing job: #{@job.title}..."

    # 1. Fetch the actual job posting page
    begin
      html = URI.open(@job.url, "User-Agent" => "Mozilla/5.0", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      doc = Nokogiri::HTML(html)

      # Strip noisy HTML tags so we don't confuse the AI (and save tokens) -
      # and so a job board's own generic "contact us" mailto: link in its nav
      # or footer (site-wide, printed on every posting) isn't mistaken for
      # this specific listing's HR address. Do this before extracting the
      # email, not after: a site like Klix prints its own posao@klix.ba
      # contact link in the page chrome on every single job page.
      doc.search("script, style, nav, footer, header").remove

      # A mailto: link or a bare email address printed in the remaining page
      # text is a sure thing - Bosnian job ads print the HR address plainly
      # very often. Try this before ever spending an AI call on it.
      email_from_page = extract_email(doc)

      # Convert the DOM to raw text, removing excessive whitespace
      raw_text = doc.text.gsub(/\s+/, " ").strip

      # Truncate to ~4000 characters just to be safe with token limits
      text_to_analyze = raw_text[0..4000]

      # The placeholder set at scrape time ("Scraped via ...") gets replaced
      # with the real posting text now that we've actually fetched it - even
      # if the AI call below fails, this part of the job was still worth doing.
      @job.update!(description: text_to_analyze) if text_to_analyze.present?
    rescue StandardError => e
      puts "❌ Failed to fetch inner job URL: #{e.message}"
      Honeybadger.notify(e, context: { job_id: @job.id, url: @job.url })
      return
    end

    # If we already found a real email on the page, save it now regardless
    # of what the AI call below does or doesn't find.
    @job.update!(hr_email: email_from_page) if email_from_page.present?

    # 2. Construct the AI Prompt
    prompt = <<~PROMPT
      You are an expert HR data extractor. Read the following job description and extract the HR contact email (if any) and the application deadline/expiration date.
      Return ONLY a valid JSON object. Do not include markdown formatting or explanations.
      Keys required:
      - "hr_email": The email address to send applications to (or null if none found).
      - "expiration_date": The deadline date in YYYY-MM-DD format (or null if none found).

      Job Description:
      #{text_to_analyze}
    PROMPT

    # 3. Ask Groq
    begin
      response = @client.chat(
        parameters: {
          # llama-3.1-8b-instant was retired from Groq's catalog (calls started
          # failing with a 404 model_not_found) - gpt-oss-20b is the current
          # small/fast equivalent and was verified against this exact
          # response_format: json_object usage before switching.
          model: "openai/gpt-oss-20b",
          messages: [ { role: "user", content: prompt } ],
          temperature: 0.1,
          response_format: { type: "json_object" }
        }
      )

      # 4. Parse the JSON and save - but never clobber a value that's already
      # reliable: hr_email may already be set above from the page itself, and
      # expires_at may already be set by the scraper from the listing's own
      # source data (see UniversalJobScraper/ItKarijeraScraper) - both are
      # more trustworthy than an LLM guess over prose.
      result_json = response.dig("choices", 0, "message", "content")
      result = JSON.parse(result_json)

      @job.update!(
        hr_email: @job.hr_email.presence || result["hr_email"],
        expires_at: @job.expires_at.presence || result["expiration_date"]
      )

      puts "✅ AI Extracted -> Email: #{@job.hr_email || 'None'}, Expires: #{@job.expires_at || 'None'}"

      # The AI often can't find an HR email on the posting itself - fall back
      # to the same Clearbit->Hunter.io domain lookup cold outreach uses,
      # scoped to this job's company (guarded so an already-resolved company
      # doesn't trigger a repeat Hunter.io lookup for every job it posts).
      if @job.hr_email.blank? && @job.company.primary_email.blank?
        FindCompanyEmailJob.perform_later(@job.company.id)
      end
    rescue JSON::ParserError => e
      puts "❌ AI returned invalid JSON."
      Honeybadger.notify(e, context: { job_id: @job.id })
    rescue StandardError => e
      puts "❌ AI API Error: #{e.message}"
      Honeybadger.notify(e, context: { job_id: @job.id })
    end
  end

  private

  def extract_email(doc)
    mailto = doc.at_css("a[href^='mailto:']")
    return mailto["href"].sub(/^mailto:/, "").split("?").first.strip if mailto

    doc.text[EMAIL_REGEX]
  end
end
