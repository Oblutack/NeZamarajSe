require "test_helper"

class CoverLetterTranslatorServiceTest < ActiveSupport::TestCase
  def stub_ai_response(content)
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |*|
      { "choices" => [ { "message" => { "content" => content } } ] }
    end
    fake_client
  end

  test "translates the given text and wraps it as HTML paragraphs" do
    fake_client = stub_ai_response("Poštovani,\n\nRado bih se pridružio timu.")

    result = stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTranslatorService.call(plain_text: "Dear Hiring Team,\n\nI would love to join the team.", target_language: "bs")
    end

    assert_includes result, "<p>Poštovani,</p>"
    assert_includes result, "<p>Rado bih se pridružio timu.</p>"
  end

  test "asks for the target language by name and to preserve smart tags" do
    captured_prompt = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |args|
      captured_prompt = args[:parameters][:messages].first[:content]
      { "choices" => [ { "message" => { "content" => "Translated." } } ] }
    end

    stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTranslatorService.call(plain_text: "Hello {{company_name}}.", target_language: "bs")
    end

    assert_includes captured_prompt, "into Bosnian"
    assert_includes captured_prompt, "{{company_name}}"
    assert_includes captured_prompt, "leave them exactly as written"
  end

  test "defaults to English for an unsupported language code" do
    captured_prompt = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |args|
      captured_prompt = args[:parameters][:messages].first[:content]
      { "choices" => [ { "message" => { "content" => "Translated." } } ] }
    end

    stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTranslatorService.call(plain_text: "Hello.", target_language: "de")
    end

    assert_includes captured_prompt, "into English"
  end

  test "normalizes single-newline paragraphs into real separate <p> tags" do
    fake_client = stub_ai_response("Opening line.\nBody paragraph.\nClosing paragraph.")

    result = stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTranslatorService.call(plain_text: "Some source text.", target_language: "bs")
    end

    assert_includes result, "<p>Opening line.</p>"
    assert_includes result, "<p>Body paragraph.</p>"
    assert_includes result, "<p>Closing paragraph.</p>"
    assert_not_includes result, "<br"
  end

  test "returns blank input as-is rather than calling the AI" do
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) { |*| raise "should not be called for blank input" }

    result = stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterTranslatorService.call(plain_text: "", target_language: "bs")
    end

    assert_equal "", result
  end

  test "raises if Groq returns an empty translation" do
    fake_client = stub_ai_response("")

    assert_raises(RuntimeError) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        CoverLetterTranslatorService.call(plain_text: "Hello.", target_language: "bs")
      end
    end
  end
end
