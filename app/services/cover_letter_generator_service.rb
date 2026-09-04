# app/services/cover_letter_generator_service.rb

# Drafts a cover letter tailored to one specific job, grounded in the user's
# actual resume content - not a reusable {{smart_tag}} template, a one-off
# written for this application. Deliberately writes the real company/job
# name directly into the text rather than leaving {{company_name}}/
# {{job_title}} placeholders: CoverLetterTemplate#render_content's gsub
# calls are harmless no-ops when those tokens aren't present, so nothing
# downstream needs to change, and reusing this exact draft for a different
# job later would read wrong regardless - it was never meant to be reused
# the way a hand-written template is.
class CoverLetterGeneratorService
  include CoverLetterFormatting

  MAX_JOB_DESCRIPTION_CHARS = 3000

  def self.call(job:, resume_blob:, language:)
    new(job: job, resume_blob: resume_blob, language: language).call
  end

  def initialize(job:, resume_blob:, language:)
    @job = job
    @resume_blob = resume_blob
    @language = CoverLetterTemplate::LANGUAGES.key?(language) ? language : "en"
    @client = OpenAI::Client.new
  end

  def call
    response = @client.chat(
      parameters: {
        model: "openai/gpt-oss-20b",
        messages: [ { role: "user", content: prompt } ],
        temperature: 0.6
      }
    )

    text = response.dig("choices", 0, "message", "content").to_s.strip
    raise "Groq returned an empty cover letter" if text.blank?

    ApplicationController.helpers.simple_format(normalize_paragraphs(text))
  end

  private

  def prompt
    <<~PROMPT
      You are a professional cover letter writer. Write a genuine, specific cover letter in #{CoverLetterTemplate::LANGUAGES.fetch(@language)} for the job application below. Use only real details drawn from the candidate's resume - never invent experience, skills, employers, or projects that aren't listed there. Keep it to roughly 250-350 words, professional but personable, no generic filler ("I am writing to express my interest..."). Address it generically since the specific hiring contact isn't known. Sign off with the candidate's name if their resume names them.

      Structure the letter as short, clearly separated paragraphs: an opening line, one or two paragraphs about relevant experience, a closing paragraph, then the sign-off on its own line. Separate every paragraph and the sign-off with a blank line (two newline characters) - never run them together as one block of text.

      Job title: #{@job.title}
      Company: #{@job.company.name}

      Job description:
      #{job_description}

      Candidate's resume:
      #{resume_text}

      Output only the cover letter body text - no subject line, no markdown formatting, no explanation of what you wrote.
    PROMPT
  end

  def job_description
    ActionView::Base.full_sanitizer.sanitize(@job.description.to_s).strip.presence&.first(MAX_JOB_DESCRIPTION_CHARS) || @job.title
  end

  def resume_text
    ResumeTextExtractor.call(@resume_blob)
  end
end
