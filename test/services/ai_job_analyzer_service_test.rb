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

  test "records a DeadDomain failure on a fetch error" do
    job = jobs(:one)
    host = URI.parse(job.url).host

    stub_class_method(URI, :open, ->(*) { raise "connection refused" }) do
      AiJobAnalyzerService.call(job)
    end

    domain = DeadDomain.find_by(host: host)
    assert_not_nil domain
    assert_equal 1, domain.failure_count
  end

  test "skips fetching entirely once a host has hit the failure threshold" do
    job = jobs(:one)
    host = URI.parse(job.url).host
    DeadDomain.create!(host: host, failure_count: DeadDomain::THRESHOLD, last_failed_at: Time.current)

    stub_class_method(URI, :open, ->(*) { raise "should not be called - host is marked dead" }) do
      assert_nothing_raised { AiJobAnalyzerService.call(job) }
    end
  end

  test "a successful fetch resets a host's failure count" do
    job = jobs(:one)
    host = URI.parse(job.url).host
    DeadDomain.create!(host: host, failure_count: 2, last_failed_at: 1.day.ago)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    stub_class_method(URI, :open, ->(*) { "<html><body>Job description</body></html>" }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal 0, DeadDomain.find_by(host: host).failure_count
  end

  test "uses a mailto: link on the page instead of asking the AI" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: "wrong@example.com", expiration_date: nil }.to_json)

    html = '<html><body><a href="mailto:hr@realcompany.example?subject=Job">Apply</a></body></html>'
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "hr@realcompany.example", job.reload.hr_email
  end

  test "ignores a mailto: link in the page's nav/header/footer chrome" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    # A job board's own site-wide "contact us" link, printed on every
    # posting - not this specific job's HR address. Real bug caught while
    # testing against a live Klix posting: posao@klix.ba (the site's own
    # contact link, in its footer) was being saved as the job's hr_email.
    html = <<~HTML
      <html><body>
        <header><a href="mailto:contact@jobboard.example">Contact us</a></header>
        <main><p>Backend Developer role, apply on our careers page.</p></main>
        <footer><a href="mailto:contact@jobboard.example">Contact us</a></footer>
      </body></html>
    HTML
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_nil job.reload.hr_email
  end

  test "falls back to a plain-text email in the page when there's no mailto: link" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = "<html><body>Send your CV to posao@realcompany.example please.</body></html>"
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "posao@realcompany.example", job.reload.hr_email
  end

  test "does not let the AI overwrite an expires_at the scraper already set from the listing itself" do
    job = jobs(:one)
    job.update!(expires_at: Date.new(2026, 12, 25))
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: "2026-01-01" }.to_json)

    stub_class_method(URI, :open, ->(*) { "<html><body>Job description</body></html>" }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal Date.new(2026, 12, 25), job.reload.expires_at
  end

  test "persists the real page text as the job's description" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = "<html><body><script>ignored()</script><p>The actual job posting text.</p></body></html>"
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_includes job.reload.description, "The actual job posting text."
    assert_not_includes job.description, "ignored()"
  end
end
