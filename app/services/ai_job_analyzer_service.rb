# app/services/ai_job_analyzer_service.rb
require "open-uri"
require "nokogiri"

class AiJobAnalyzerService
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
      html = URI.open(@job.url, "User-Agent" => "Mozilla/5.0")
      doc = Nokogiri::HTML(html)

      # Strip noisy HTML tags so we don't confuse the AI (and save tokens)
      doc.search("script, style, nav, footer, header").remove

      # Convert the DOM to raw text, removing excessive whitespace
      raw_text = doc.text.gsub(/\s+/, " ").strip

      # Truncate to ~4000 characters just to be safe with token limits
      text_to_analyze = raw_text[0..4000]
    rescue StandardError => e
      puts "❌ Failed to fetch inner job URL: #{e.message}"
      Honeybadger.notify(e, context: { job_id: @job.id, url: @job.url })
      return
    end

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

      # 4. Parse the JSON and Save to Postgres
      result_json = response.dig("choices", 0, "message", "content")
      result = JSON.parse(result_json)

      @job.update!(
        hr_email: result["hr_email"],
        expires_at: result["expiration_date"]
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
end
