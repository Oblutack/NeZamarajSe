require "test_helper"

class AiJobAnalyzerServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Every fixture HTML string in this file is deliberately short (well under
  # MIN_RENDERED_TEXT_LENGTH), which would otherwise trigger the real
  # headless-Chrome fallback on every single test in this file - slow, and a
  # real browser launch has no business happening in a unit test. Raising
  # here isn't a problem for those tests: fetch_rendered_doc's own
  # rescue => nil swallows it, exactly like a real headless failure would,
  # so the original short text is kept and those tests' assertions still
  # hold. Tests that actually want to exercise the fallback stub
  # Ferrum::Browser.new themselves (see below), which shadows this for the
  # duration of their own block.
  setup do
    Ferrum::Browser.define_singleton_method(:new) { |*| raise "Ferrum::Browser.new should be stubbed explicitly by any test exercising the headless fallback" }
  end

  teardown do
    Ferrum::Browser.singleton_class.send(:remove_method, :new)
  end

  def stub_ai_response(content)
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |*|
      { "choices" => [ { "message" => { "content" => content } } ] }
    end
    fake_client
  end

  # A minimal double for Ferrum::Browser - just enough surface
  # (#goto/#network/#body/#quit) for fetch_rendered_doc to drive it.
  def stub_headless_browser(rendered_html)
    network = Object.new
    network.define_singleton_method(:wait_for_idle) { |*| }

    browser = Object.new
    browser.define_singleton_method(:goto) { |*| }
    browser.define_singleton_method(:network) { network }
    browser.define_singleton_method(:body) { rendered_html }
    browser.define_singleton_method(:quit) { }
    browser
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

  test "skip_email_lookup suppresses the Hunter.io fallback even when both emails are blank" do
    job = jobs(:one)
    job.company.update!(primary_email: nil)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    stub_class_method(URI, :open, ->(*) { "<html><body>No contact info here</body></html>" }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        assert_no_enqueued_jobs(only: FindCompanyEmailJob) do
          AiJobAnalyzerService.call(job, skip_email_lookup: true)
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

  test "does not leak the page's <title> tag into the description" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = "<html><head><title>Backend Engineer | Acme - Some Job Board</title></head><body><p>The actual job posting text.</p></body></html>"
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "The actual job posting text.", job.reload.description
  end

  test "extracts only from a .prose content wrapper when the page has one, skipping surrounding chrome" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = <<~HTML
      <html><body>
        <div class="breadcrumb">
          <h1>Backend Engineer</h1>
          <p>Objavio , 01.09.2026. u 09:02. - Prijava do 27.09.2026.</p>
        </div>
        <main>
          <div class="prose">
            <p>The real job description starts here.</p>
            <p>Second paragraph.</p>
          </div>
        </main>
      </body></html>
    HTML
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "The real job description starts here.\nSecond paragraph.", job.reload.description
  end

  test "falls back to <main> when the page has no .prose wrapper" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = <<~HTML
      <html><body>
        <div class="sidebar"><p>Related jobs widget.</p></div>
        <main><p>The real job description.</p></main>
      </body></html>
    HTML
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "The real job description.", job.reload.description
  end

  test "strips breadcrumb/navigation links from the description but still extracts a mailto: email first" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = <<~HTML
      <html><body>
        <a href="/jobs">Home</a> <a href="/jobs">Listings</a> <a href="/jobs/1">Backend Engineer</a>
        <p>Apply to <a href="mailto:hr@realcompany.example">hr@realcompany.example</a> for this role.</p>
      </body></html>
    HTML
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    job.reload
    assert_equal "hr@realcompany.example", job.hr_email
    assert_equal "Apply to for this role.", job.description
    assert_not_includes job.description, "Home"
    assert_not_includes job.description, "Listings"
  end

  test "preserves paragraph breaks instead of collapsing the page into one line" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = "<html><body><p>About us: we build things.</p><p>We are looking for a developer.</p></body></html>"
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "About us: we build things.\nWe are looking for a developer.", job.reload.description
  end

  test "puts each list item on its own line" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = "<html><body><p>Requirements:</p><ul><li>Ruby</li><li>Rails</li></ul></body></html>"
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "Requirements:\nRuby\nRails", job.reload.description
  end

  test "turns <br> tags into line breaks" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = "<html><body><p>Line one<br>Line two</p></body></html>"
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "Line one\nLine two", job.reload.description
  end

  test "collapses repeated internal whitespace within a line without losing line breaks" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = "<html><body><p>Too    much     space.</p><p>Second line.</p></body></html>"
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "Too much space.\nSecond line.", job.reload.description
  end

  test "fetches the job page with full browser headers, not just a bare User-Agent" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)
    captured_options = nil

    stub_class_method(URI, :open, ->(_url, options) { captured_options = options; "<html><body>Job description</body></html>" }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal AiJobAnalyzerService::REQUEST_HEADERS["User-Agent"], captured_options["User-Agent"]
    assert_equal AiJobAnalyzerService::REQUEST_HEADERS["Accept"], captured_options["Accept"]
    assert_equal AiJobAnalyzerService::REQUEST_HEADERS["Accept-Language"], captured_options["Accept-Language"]
  end

  def fake_downloaded_image(content_type: "image/png")
    io = StringIO.new("fake image bytes")
    io.define_singleton_method(:content_type) { content_type }
    io
  end

  test "attaches a company logo from an og:image hosted on the company's own domain" do
    job = jobs(:one)
    job.company.update!(domain: "realcompany.example")
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = '<html><head><meta property="og:image" content="https://realcompany.example/assets/logo.png"></head><body>Job description</body></html>'
    fake_image = fake_downloaded_image

    stub_class_method(URI, :open, ->(url, *) { url.include?("logo.png") ? fake_image : html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert job.company.reload.logo.attached?
  end

  test "does not attach an og:image hosted on a different domain than the company's" do
    job = jobs(:one)
    job.company.update!(domain: "realcompany.example")
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = '<html><head><meta property="og:image" content="https://some-job-board.example/logo.png"></head><body>Job description</body></html>'

    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_not job.company.reload.logo.attached?
  end

  test "does not attempt a logo lookup when the company has no resolved domain" do
    job = jobs(:one)
    job.company.update!(domain: nil)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = '<html><head><meta property="og:image" content="https://realcompany.example/logo.png"></head><body>Job description</body></html>'

    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_not job.company.reload.logo.attached?
  end

  test "does not overwrite a company's existing logo" do
    job = jobs(:one)
    job.company.update!(domain: "realcompany.example")
    job.company.logo.attach(io: StringIO.new("existing logo"), filename: "existing.png", content_type: "image/png")
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = '<html><head><meta property="og:image" content="https://realcompany.example/new-logo.png"></head><body>Job description</body></html>'
    fake_image = fake_downloaded_image

    stub_class_method(URI, :open, ->(url, *) { url.include?("new-logo.png") ? fake_image : html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "existing.png", job.company.reload.logo.filename.to_s
  end

  test "falls back to headless rendering when the plain fetch yields too little text" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    shell_html = "<html><body>BambooHR</body></html>"
    rendered_html = "<html><body><p>#{'A real, fully client-side rendered job description. ' * 10}</p></body></html>"

    stub_class_method(URI, :open, ->(*) { shell_html }) do
      stub_class_method(Ferrum::Browser, :new, stub_headless_browser(rendered_html)) do
        stub_class_method(OpenAI::Client, :new, fake_client) do
          AiJobAnalyzerService.call(job)
        end
      end
    end

    assert_includes job.reload.description, "A real, fully client-side rendered job description."
    assert_not_equal "BambooHR", job.description
  end

  test "does not fall back to headless rendering when the plain fetch already has enough text" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = "<html><body><p>#{'A perfectly normal, plenty-long job description sentence. ' * 10}</p></body></html>"

    # No Ferrum::Browser stub here - the file-wide setup stub raises if it's
    # ever called, so this test also proves the fallback stays untriggered.
    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        assert_nothing_raised { AiJobAnalyzerService.call(job) }
      end
    end

    assert_includes job.reload.description, "A perfectly normal, plenty-long job description sentence."
  end

  test "keeps the plain fetch's text when the headless fallback also comes back short" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    shell_html = "<html><body>Short but real text.</body></html>"
    still_short_rendered_html = "<html><body>Nothing.</body></html>"

    stub_class_method(URI, :open, ->(*) { shell_html }) do
      stub_class_method(Ferrum::Browser, :new, stub_headless_browser(still_short_rendered_html)) do
        stub_class_method(OpenAI::Client, :new, fake_client) do
          AiJobAnalyzerService.call(job)
        end
      end
    end

    assert_equal "Short but real text.", job.reload.description
  end

  test "does not blow up when the headless fallback itself fails" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    shell_html = "<html><body>BambooHR</body></html>"

    stub_class_method(URI, :open, ->(*) { shell_html }) do
      stub_class_method(Ferrum::Browser, :new, ->(*) { raise "Chrome crashed" }) do
        stub_class_method(OpenAI::Client, :new, fake_client) do
          assert_nothing_raised { AiJobAnalyzerService.call(job) }
        end
      end
    end

    assert_equal "BambooHR", job.reload.description
  end

  def nuxt_data_html(job_object_json, *values)
    payload = [ JSON.parse(job_object_json), *values ].to_json
    %(<html><body><p>Rendered page shell - not the real content.</p><script id="__NUXT_DATA__" type="application/json">#{payload}</script></body></html>)
  end

  test "reads the description straight out of a Nuxt SSR page's embedded __NUXT_DATA__ payload" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = nuxt_data_html(
      %({"title": 1, "slug": 2, "html": 3, "description": 4}),
      "Job Title", "job-slug",
      "<p>Real description paragraph one.</p><p>Real description paragraph two.</p>",
      ""
    )

    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "Real description paragraph one.\nReal description paragraph two.", job.reload.description
    assert_not_includes job.description, "Rendered page shell"
  end

  test "does not mistake an inline <script>'s Sentry DSN for the page's HR email on a Nuxt SSR page" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    payload = [ { "title" => 1, "slug" => 2, "html" => 3, "description" => 4 }, "Job Title", "job-slug",
                "<p>Real description paragraph one.</p><p>Real description paragraph two.</p>", "" ].to_json
    html = <<~HTML
      <html><body>
        <script>Sentry.init({dsn: "https://a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4@o4506224253796352.ingest.sentry.io/1"});</script>
        <p>Rendered page shell - not the real content.</p>
        <script id="__NUXT_DATA__" type="application/json">#{payload}</script>
      </body></html>
    HTML

    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_nil job.reload.hr_email
  end

  test "falls back to the payload's description field when html is blank" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = nuxt_data_html(
      %({"title": 1, "slug": 2, "html": 3, "description": 4}),
      "Job Title", "job-slug",
      "",
      "Plain-text description from the description field."
    )

    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_equal "Plain-text description from the description field.", job.reload.description
  end

  test "ignores a __NUXT_DATA__ payload with no job-shaped object in it" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = %(<html><body><p>#{'A perfectly ordinary server-rendered description. ' * 10}</p><script id="__NUXT_DATA__" type="application/json">[{"unrelated":"stuff"}]</script></body></html>)

    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        AiJobAnalyzerService.call(job)
      end
    end

    assert_includes job.reload.description, "A perfectly ordinary server-rendered description."
  end

  test "does not blow up on a malformed __NUXT_DATA__ payload" do
    job = jobs(:one)
    fake_client = stub_ai_response({ hr_email: nil, expiration_date: nil }.to_json)

    html = %(<html><body><p>#{'Fallback page content that is plenty long enough. ' * 10}</p><script id="__NUXT_DATA__" type="application/json">{not valid json</script></body></html>)

    stub_class_method(URI, :open, ->(*) { html }) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        assert_nothing_raised { AiJobAnalyzerService.call(job) }
      end
    end

    assert_includes job.reload.description, "Fallback page content that is plenty long enough."
  end
end
