require "test_helper"

class CoverLetterGeneratorServiceTest < ActiveSupport::TestCase
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

  test "generates a cover letter and wraps it as real HTML paragraphs" do
    job = jobs(:one)
    fake_client = stub_ai_response("Dear Hiring Team,\n\nI would love to join.\n\nBest,\nCandidate")

    result = stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterGeneratorService.call(job: job, resume_blob: resume_blob, language: "en")
    end

    assert_includes result, "<p>Dear Hiring Team,</p>"
    assert_includes result, "<p>I would love to join.</p>"
    assert_includes result, "<p>Best,\n<br />Candidate</p>"
  end

  test "asks for the requested language by name in the prompt" do
    job = jobs(:one)
    captured_prompt = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |args|
      captured_prompt = args[:parameters][:messages].first[:content]
      { "choices" => [ { "message" => { "content" => "Letter body." } } ] }
    end

    stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterGeneratorService.call(job: job, resume_blob: resume_blob, language: "bs")
    end

    assert_includes captured_prompt, "cover letter in Bosnian"
  end

  test "defaults to English for an unsupported language code" do
    job = jobs(:one)
    captured_prompt = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |args|
      captured_prompt = args[:parameters][:messages].first[:content]
      { "choices" => [ { "message" => { "content" => "Letter body." } } ] }
    end

    stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterGeneratorService.call(job: job, resume_blob: resume_blob, language: "fr")
    end

    assert_includes captured_prompt, "cover letter in English"
  end

  test "includes the job title, company, and description in the prompt" do
    job = jobs(:one)
    job.update!(description: "<p>We need a backend engineer.</p>")
    captured_prompt = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |args|
      captured_prompt = args[:parameters][:messages].first[:content]
      { "choices" => [ { "message" => { "content" => "Letter body." } } ] }
    end

    stub_class_method(OpenAI::Client, :new, fake_client) do
      CoverLetterGeneratorService.call(job: job, resume_blob: resume_blob, language: "en")
    end

    assert_includes captured_prompt, job.title
    assert_includes captured_prompt, job.company.name
    assert_includes captured_prompt, "We need a backend engineer."
  end

  test "raises if Groq returns an empty response" do
    job = jobs(:one)
    fake_client = stub_ai_response("")

    assert_raises(RuntimeError) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        CoverLetterGeneratorService.call(job: job, resume_blob: resume_blob, language: "en")
      end
    end
  end
end
