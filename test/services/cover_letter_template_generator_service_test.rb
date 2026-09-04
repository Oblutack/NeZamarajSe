require "test_helper"

class CoverLetterTemplateGeneratorServiceTest < ActiveSupport::TestCase
  def stub_ai_response(content)
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |*|
      { "choices" => [ { "message" => { "content" => content } } ] }
    end
    fake_client
  end

  def resume_blob
    ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("test/fixtures/files/sample_resume.pdf")),
      filename: "resume.pdf",
      content_type: "application/pdf"
    )
  end

  test "generates a reusable template and wraps it as real HTML paragraphs" do
    fake_client = stub_ai_response("Dear {{company_name}},\n\nI'd love to join.\n\nBest,\nCandidate")

    result = stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTemplateGeneratorService.call(resume_blob: resume_blob, language: "en")
    end

    assert_includes result, "<p>Dear {{company_name}},</p>"
    assert_includes result, "<p>I'd love to join.</p>"
  end

  test "asks for the requested language and the smart-tag placeholders in the prompt" do
    captured_prompt = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |args|
      captured_prompt = args[:parameters][:messages].first[:content]
      { "choices" => [ { "message" => { "content" => "Letter body." } } ] }
    end

    stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTemplateGeneratorService.call(resume_blob: resume_blob, language: "bs")
    end

    assert_includes captured_prompt, "TEMPLATE in Bosnian"
    assert_includes captured_prompt, "{{company_name}}"
    assert_includes captured_prompt, "{{job_title}}"
    assert_includes captured_prompt, "{{location}}"
  end

  test "defaults to English for an unsupported language code" do
    captured_prompt = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |args|
      captured_prompt = args[:parameters][:messages].first[:content]
      { "choices" => [ { "message" => { "content" => "Letter body." } } ] }
    end

    stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTemplateGeneratorService.call(resume_blob: resume_blob, language: "fr")
    end

    assert_includes captured_prompt, "TEMPLATE in English"
  end

  test "normalizes single-newline paragraphs into real separate <p> tags" do
    fake_client = stub_ai_response("Opening line.\nBody paragraph about experience.\nClosing paragraph.")

    result = stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTemplateGeneratorService.call(resume_blob: resume_blob, language: "en")
    end

    assert_includes result, "<p>Opening line.</p>"
    assert_includes result, "<p>Body paragraph about experience.</p>"
    assert_includes result, "<p>Closing paragraph.</p>"
    assert_not_includes result, "<br"
  end

  test "raises if Groq returns an empty response" do
    fake_client = stub_ai_response("")

    assert_raises(RuntimeError) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        CoverLetterTemplateGeneratorService.call(resume_blob: resume_blob, language: "en")
      end
    end
  end
end
