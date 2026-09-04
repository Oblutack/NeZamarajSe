# app/services/cover_letter_template_generator_service.rb

# Drafts a reusable cover letter TEMPLATE - not tied to one specific job,
# unlike CoverLetterGeneratorService. Grounded in the user's actual resume,
# but keeps {{company_name}}/{{job_title}}/{{location}} as literal
# placeholders (the model is told to write them verbatim) so
# CoverLetterTemplate#render_content can substitute them per-application
# later, the same as a hand-written template.
class CoverLetterTemplateGeneratorService
  include CoverLetterFormatting

  def self.call(resume_blob:, language:)
    new(resume_blob: resume_blob, language: language).call
  end

  def initialize(resume_blob:, language:)
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
      Write a reusable cover letter TEMPLATE in #{CoverLetterTemplate::LANGUAGES.fetch(@language)} that the candidate can send to many different job applications - not a letter for one specific job. Use only real details drawn from the candidate's resume below - never invent experience, skills, employers, or projects that aren't listed there. Keep it to roughly 250-350 words, professional but personable, no generic filler ("I am writing to express my interest...").

      Wherever the company name, job title, or location would go, use exactly these placeholder tokens instead of inventing a specific company or role - written verbatim, including the double curly braces: {{company_name}} for the company, {{job_title}} for the position, {{location}} for the location. Use each of the three at least once.

      Structure the letter as short, clearly separated paragraphs: an opening line, one or two paragraphs about relevant experience, a closing paragraph, then the sign-off on its own line. Separate every paragraph and the sign-off with a blank line (two newline characters) - never run them together as one block of text.

      Candidate's resume:
      #{resume_text}

      Output only the letter body text - no subject line, no markdown formatting, no explanation of what you wrote.
    PROMPT
  end

  def resume_text
    ResumeTextExtractor.call(@resume_blob)
  end
end
