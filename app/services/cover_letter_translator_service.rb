# app/services/cover_letter_translator_service.rb

# Re-translates an already-generated cover letter into the other supported
# language, rather than regenerating from scratch - same letter, same
# structure, just re-worded. Takes plain text in, not HTML: translating raw
# markup risks an LLM mangling tags it wasn't asked to preserve, so the
# caller passes CoverLetterTemplate#body.to_plain_text and this returns the
# same sanitized-paragraph HTML shape CoverLetterGeneratorService produces.
class CoverLetterTranslatorService
  include CoverLetterFormatting

  def self.call(plain_text:, target_language:)
    new(plain_text: plain_text, target_language: target_language).call
  end

  def initialize(plain_text:, target_language:)
    @plain_text = plain_text
    @target_language = CoverLetterTemplate::LANGUAGES.key?(target_language) ? target_language : "en"
    @client = OpenAI::Client.new
  end

  def call
    return @plain_text if @plain_text.blank?

    response = @client.chat(
      parameters: {
        model: "openai/gpt-oss-20b",
        messages: [ { role: "user", content: prompt } ],
        temperature: 0.3
      }
    )

    text = response.dig("choices", 0, "message", "content").to_s.strip
    raise "Groq returned an empty translation" if text.blank?

    ApplicationController.helpers.simple_format(normalize_paragraphs(text))
  end

  private

  def prompt
    <<~PROMPT
      Translate the following cover letter into #{CoverLetterTemplate::LANGUAGES.fetch(@target_language)}. Preserve the paragraph structure, tone, and meaning exactly - this is a professional job application letter, not casual text. If the text contains placeholder tokens like {{company_name}}, {{job_title}}, or {{location}}, leave them exactly as written, do not translate or alter them.

      #{@plain_text}

      Output only the translated letter text - no commentary, no markdown formatting.
    PROMPT
  end
end
