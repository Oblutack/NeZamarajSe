require "test_helper"

class AiJobAnalyzerServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def stub_ai_response(content)
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |*|
      { "choices" => [ { "message" => { "content" => content } } ] }
    end
    fake_client
  end

  test "saves the hr_email and expiration date the AI extracts" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: "hr@vertex.example", expiration_date: "2026-09-01" }.to_json)

    stub_class_method(URI, :open, ->(*) { "<html><body>Job description</body></html>" }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    job.reload
    assert_equal "hr@vertex.example", job.hr_email
    assert_equal Date.parse("2026-09-01"), job.expires_at
  end

  test "enqueues a company email lookup when the AI finds no email and the company has none yet" do
    job = jobs(:one)
    job.company.update!(primary_email: nil)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    stub_class_method(URI, :open, ->(*) { "<html><body>No contact info here</body></html>" }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        assert_enqueued_with(job: FindCompanyEmailJob, args: [ job.company.id ]) do
          AiJobAnalyzerService.call(job)
        end
      end
    end
  end

  test "does not re-trigger a lookup when the company's email is already known" do
    job = jobs(:one)
    job.company.update!(primary_email: "hr@vertex.example")
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    stub_class_method(URI, :open, ->(*) { "<html><body>No contact info here</body></html>" }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        assert_no_enqueued_jobs(only: FindCompanyEmailJob) do
          AiJobAnalyzerService.call(job)
        end
      end
    end
  end

  test "does not blow up when the AI returns invalid JSON" do
    job = jobs(:one)
    fake_client = stub_ai_response("not json")

    stub_class_method(URI, :open, ->(*) { "<html><body>Job description</body></html>" }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        assert_nothing_raised { AiJobAnalyzerService.call(job) }
      end
    end

    assert_nil job.reload.hr_email
  end

  test "does not blow up when the job URL can't be fetched" do
    job = jobs(:one)

    stub_class_method(URI, :open, ->(*) { raise "connection refused" }) do
      assert_nothing_raised { AiJobAnalyzerService.call(job) }
    end
  end
end
