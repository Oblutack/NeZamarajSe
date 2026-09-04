# app/services/ai_job_analyzer_service.rb
require "open-uri"
require "nokogiri"
require "ferrum"

class AiJobAnalyzerService
  # A handful of jobs link to domains that are dead/very slow (e.g. a defunct
  # regional job-aggregator redirect) and were eating a full 60s each - the
  # default Net::HTTP open/read timeout - before failing. 8s to connect, 12s
  # to read is generous for a job posting page and keeps a bad link from
  # stalling the whole enrichment queue behind it. DeadDomain (see #call)
  # goes further for a host that keeps failing - after 3 recent failures it
  # skips the fetch entirely rather than paying even this reduced timeout
  # again on the next job from the same dead source.
  OPEN_TIMEOUT = 8
  READ_TIMEOUT = 12

  # A bare User-Agent isn't enough for every site - itbase.ba's own job pages
  # are just 301 redirects to onecontact.com.mk (a defunct regional
  # aggregator, already flagged as troublesome in CLAUDE.md), and that
  # destination outright 406s a request with no Accept/Accept-Language
  # header, real browser or not. Confirmed live: the identical request
  # succeeds with these two headers added and nothing else changed -
  # accounted for 80 of ~183 backlog jobs stuck on their scrape-time
  # placeholder description. A full browser UA string plus Accept/
  # Accept-Language is cheap insurance against the same bot-filter
  # elsewhere.
  REQUEST_HEADERS = {
    "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
    "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language" => "en-US,en;q=0.9"
  }.freeze

  # Matches a plain-text email as a fallback for pages that print the address
  # as text rather than an <a href="mailto:"> link.
  EMAIL_REGEX = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/

  # Block-level tags that get a newline inserted after them in
  # #extract_readable_text, so a stored description keeps its paragraph/list
  # structure instead of collapsing into one run-on line.
  BLOCK_TAGS = %w[p div li h1 h2 h3 h4 h5 h6 tr].freeze

  # What survives into the stored description as real markup - enough to
  # give a posting actual visual hierarchy (headings, bold, bullet lists)
  # instead of a flat wall of text, nothing that can carry a link, an
  # attribute, or a script. Rendered through Tailwind Typography's `.prose`
  # styling (see jobs/show.html.erb) and re-sanitized with this exact same
  # allowlist at render time too - this is the only layer that needs to
  # hold for storage, but belt-and-suspenders costs nothing.
  ALLOWED_DESCRIPTION_TAGS = %w[p br ul ol li h1 h2 h3 h4 h5 h6 strong b em i].freeze

  # Some itbase.ba postings link to a specific job on a third-party ATS
  # (BambooHR, Workday, ...) that has since closed or moved - the ATS
  # doesn't 404 in that case, it redirects to its own generic "see our
  # current openings" landing page instead, which fetches (and even
  # headless-renders) just fine but has no job-specific content at all.
  # Matched by exact, directly-observed phrasing rather than length - a
  # short-but-genuine posting is common enough in this dataset (plenty of
  # real Bosnian ads run under MIN_RENDERED_TEXT_LENGTH) that a length-only
  # rule would wrongly blank those out too.
  DEAD_END_LANDING_PAGE_PHRASES = [
    "Thanks for checking out our job openings",
    "Workday, Inc. All rights reserved"
  ].freeze

  # Bare platform-branding strings seen when a page's JS never even finishes
  # hydrating past its own logo/title - matched as the *entire* stripped
  # result, not a substring, since these particular words are short enough
  # that they could plausibly appear inside real prose.
  DEAD_END_LANDING_PAGE_EXACT_MATCHES = [ "BambooHR", "IT Karijera" ].freeze

  # A real job posting runs into the hundreds of characters at minimum -
  # confirmed live, some itbase.ba postings redirect to ATS pages (e.g.
  # BambooHR) that render the actual listing client-side via JS, so the
  # plain HTTP fetch below only sees a near-empty page shell ("BambooHR", 8
  # characters, was one real result). Text shorter than this after a normal
  # fetch triggers a headless-Chrome retry (see #fetch_rendered_doc) instead
  # of silently saving the shell text as if it were the real description.
  MIN_RENDERED_TEXT_LENGTH = 300

  def self.call(job, skip_email_lookup: false)
    new(job, skip_email_lookup: skip_email_lookup).call
  end

  # skip_email_lookup exists for the enrichment-backlog drain rake task
  # (lib/tasks/enrichment.rake) - running hundreds of jobs through this
  # service back to back would otherwise enqueue a Hunter.io lookup for
  # every company still missing an email, blowing through the ~25/month free
  # quota in one run. Normal per-job analysis (the AnalyzeJob callback after
  # a fresh scrape) always leaves this false.
  def initialize(job, skip_email_lookup: false)
    @job = job
    @skip_email_lookup = skip_email_lookup
    @client = OpenAI::Client.new
  end

  def call
    puts "🤖 AI analyzing job: #{@job.title}..."

    host = begin
      URI.parse(@job.url).host
    rescue URI::InvalidURIError
      nil
    end

    if DeadDomain.dead?(host)
      puts "⏭️ Skipping #{@job.url} - #{host} has failed #{DeadDomain::THRESHOLD}+ times recently"
      return
    end

    # 1. Fetch the actual job posting page
    begin
      html = URI.open(@job.url, REQUEST_HEADERS.merge(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT))
      DeadDomain.record_success!(host)
      doc = Nokogiri::HTML(html)

      # Best-effort, and deliberately before the chrome-stripping/extraction
      # below - a failure in here must never affect the more important
      # email/description work that follows. og:image lives in <head>, so
      # it's unaffected either way regardless of ordering.
      extract_and_attach_company_logo(doc)

      # MojPosao (a Nuxt SSR app) never renders its job description into the
      # DOM at all, even after full JS hydration - confirmed live, headless
      # rendering came back with nothing. But the plain fetch already has
      # everything: Nuxt embeds its page's full state as JSON in a
      # <script id="__NUXT_DATA__"> tag for client-side hydration, and the
      # job's real description lives right there as an HTML string,
      # untouched by any of the page's own chrome. Must run before
      # extract_email_and_content below, which strips every <script> tag
      # (including this one) as part of its normal chrome-stripping.
      nuxt_html = extract_nuxt_payload_html(doc)

      # Always run the normal DOM-based extraction first - email extraction
      # in particular needs the script-stripping this does, having caught a
      # real false positive live: an un-stripped inline <script> on MojPosao
      # embeds a Sentry error-tracking DSN
      # (a1b2c3@oXXXXXX.ingest.sentry.io) that happens to be shaped exactly
      # like an email address, and extract_email's plain-text regex
      # fallback matched it as if it were the page's HR contact.
      #
      # description_html and raw_text describe the *same* content in two
      # shapes the whole way through this method: raw_text (plain) drives
      # every length comparison/threshold below and feeds the AI prompt,
      # while description_html (sanitized markup) is what actually gets
      # saved - keeping both in lockstep means whichever source wins a
      # comparison, its real structure (headings/bullets/bold) is what
      # ends up stored, not just its word count.
      email_from_page, description_html, raw_text = extract_email_and_content(doc)

      # Only the content gets a second opinion from the Nuxt payload, and
      # only if it's actually better than what the DOM gave us - same
      # longer-wins comparison as the headless fallback below.
      if nuxt_html.present?
        nuxt_content_html, nuxt_text = extract_readable_content(Nokogiri::HTML.fragment(nuxt_html))
        if nuxt_text.length > raw_text.length
          description_html = nuxt_content_html
          raw_text = nuxt_text
        end
      end

      # Some sites (and some itbase.ba redirect targets) render their actual
      # posting text client-side via JS with no server-embedded state to
      # fall back on - the plain fetch above only sees the pre-hydration
      # page shell in that case, which yields suspiciously little text.
      # Retry once with the same headless-Chrome approach the scrapers
      # already use at listing-scrape time rather than silently saving that
      # shell text as if it were the real description.
      if raw_text.length < MIN_RENDERED_TEXT_LENGTH
        rendered_doc = fetch_rendered_doc(@job.url)
        if rendered_doc
          rendered_email, rendered_html, rendered_text = extract_email_and_content(rendered_doc)
          if rendered_text.length > raw_text.length
            description_html = rendered_html
            raw_text = rendered_text
            email_from_page = email_from_page.presence || rendered_email
          end
        end
      end

      # Truncate to ~4000 characters just to be safe with token limits - only
      # affects the plain-text copy fed to the AI prompt below; the stored
      # HTML is saved in full (no risk of slicing through the middle of a
      # tag, and real postings don't run long enough for DB bloat to matter).
      text_to_analyze = raw_text[0..4000]

      # The placeholder set at scrape time ("Scraped via ...") gets replaced
      # with the real posting text now that we've actually fetched it - even
      # if the AI call below fails, this part of the job was still worth doing.
      # Except when the "real posting text" is actually a dead-end ATS
      # landing page (see DEAD_END_LANDING_PAGE_*) - leaving the honest
      # placeholder in place is strictly better than replacing it with
      # boilerplate that looks like a successful analysis but isn't.
      if text_to_analyze.present? && !dead_end_landing_page?(text_to_analyze)
        @job.update!(description: description_html.presence || text_to_analyze)
      end
    rescue StandardError => e
      DeadDomain.record_failure!(host)
      puts "❌ Failed to fetch inner job URL: #{e.message}"
      Honeybadger.notify(e, context: { job_id: @job.id, url: @job.url })
      return
    end

    # If we already found a real email on the page, save it now regardless
    # of what the AI call below does or doesn't find.
    @job.update!(hr_email: email_from_page) if email_from_page.present?

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

      # 4. Parse the JSON and save - but never clobber a value that's already
      # reliable: hr_email may already be set above from the page itself, and
      # expires_at may already be set by the scraper from the listing's own
      # source data (see UniversalJobScraper/ItKarijeraScraper) - both are
      # more trustworthy than an LLM guess over prose.
      result_json = response.dig("choices", 0, "message", "content")
      result = JSON.parse(result_json)

      @job.update!(
        hr_email: @job.hr_email.presence || result["hr_email"],
        expires_at: @job.expires_at.presence || result["expiration_date"]
      )

      puts "✅ AI Extracted -> Email: #{@job.hr_email || 'None'}, Expires: #{@job.expires_at || 'None'}"

      # The AI often can't find an HR email on the posting itself - fall back
      # to the same Clearbit->Hunter.io domain lookup cold outreach uses,
      # scoped to this job's company (guarded so an already-resolved company
      # doesn't trigger a repeat Hunter.io lookup for every job it posts).
      if @job.hr_email.blank? && @job.company.primary_email.blank? && !@skip_email_lookup
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

  private

  def dead_end_landing_page?(text)
    return true if DEAD_END_LANDING_PAGE_EXACT_MATCHES.include?(text.strip)
    DEAD_END_LANDING_PAGE_PHRASES.any? { |phrase| text.include?(phrase) }
  end

  # Nuxt 3's SSR mode serializes the whole page's reactive state as a flat
  # JSON array in <script id="__NUXT_DATA__"> - objects reference other
  # values by their index in that array (so it stays valid, parseable JSON
  # despite the shared-reference structure) rather than duplicating data
  # inline. Confirmed live against MojPosao: the job detail object in that
  # array always carries "title"/"slug"/"html" keys pointing at other
  # indices, and index the "html" one points to is the full posting body
  # as an HTML string - complete, with none of the page's own chrome mixed
  # in, since it's the same content the server used to prerender the page
  # in the first place. Matched by object shape, not by host/URL, so this
  # applies to any other Nuxt SSR job board with the same data shape, not
  # just MojPosao specifically.
  def extract_nuxt_payload_html(doc)
    script = doc.at_css("script#__NUXT_DATA__")
    return nil unless script

    payload = JSON.parse(script.text)
    return nil unless payload.is_a?(Array)

    job_object = payload.find do |el|
      el.is_a?(Hash) && el["html"].is_a?(Integer) && el["title"].is_a?(Integer) && el["slug"].is_a?(Integer)
    end
    return nil unless job_object

    description_index = job_object["description"]
    candidates = [ payload[job_object["html"]] ]
    candidates << payload[description_index] if description_index.is_a?(Integer)

    candidates.select { |value| value.is_a?(String) }.max_by(&:length).presence
  rescue JSON::ParserError
    nil
  end

  # Strips chrome and pulls the [email, description_html, readable_text]
  # triple out of a parsed page - shared between the plain-fetch doc and the
  # headless-rendered fallback doc so both go through identical extraction
  # logic.
  def extract_email_and_content(doc)
    # Strip noisy HTML tags so we don't confuse the AI (and save tokens) -
    # and so a job board's own generic "contact us" mailto: link in its nav
    # or footer (site-wide, printed on every posting) isn't mistaken for
    # this specific listing's HR address. Do this before extracting the
    # email, not after: a site like Klix prints its own posao@klix.ba
    # contact link in the page chrome on every single job page.
    doc.search("script, style, nav, footer, header").remove

    # A mailto: link or a bare email address printed in the remaining page
    # text is a sure thing - Bosnian job ads print the HR address plainly
    # very often. Try this before ever spending an AI call on it.
    email = extract_email(doc)

    # Strip remaining links (breadcrumbs, "back to listings", pagination,
    # share buttons) now that mailto: extraction above is done with them -
    # real job-posting prose is essentially never itself a hyperlink, but
    # site chrome almost always is. Confirmed live against a Klix posting:
    # its breadcrumb ("Početna Oglasi <title>") isn't inside <nav>/
    # <header> at all, just a plain <a> in the main content area - no
    # tag-name-based strip catches it, but this does. Whatever a link
    # pointed at (company name, "X other locations") is already captured
    # in Job#company/#location from the scrape itself, so losing that text
    # here isn't a real data loss.
    doc.css("a").remove

    html, text = extract_readable_content(doc)
    [ email, html, text ]
  end

  # Same headless-Chrome approach and launch flags as
  # Scrapers::UniversalJobScraper/CompanyWallScraper - reused here as a
  # fallback, not the default path, since launching a real browser per job
  # is meaningfully slower/heavier than the plain HTTP fetch that covers
  # most sites. Returns nil (rather than raising) on any failure - this is
  # already a fallback for the fallback's sake, so a site that defeats even
  # headless rendering should just fall through to keeping whatever the
  # plain fetch got, not blow up the whole analysis.
  def fetch_rendered_doc(url)
    browser = Ferrum::Browser.new(
      timeout: 20,
      window_size: [ 1920, 1080 ],
      browser_options: {
        "no-sandbox": nil,
        "disable-dev-shm-usage": nil,
        "disable-gpu": nil,
        "user-agent": REQUEST_HEADERS["User-Agent"]
      }
    )
    browser.goto(url)
    # Same two-step wait as the scrapers (UniversalJobScraper/
    # CompanyWallScraper): network idle alone isn't always enough - a widget
    # that renders its content just after its last network call still needs
    # a beat to actually paint into the DOM. Confirmed live: without this,
    # a BambooHR careers page's job list still read as empty immediately
    # after wait_for_idle, but was fully populated 0.5s later.
    browser.network.wait_for_idle(timeout: 10)
    sleep(0.5)
    Nokogiri::HTML(browser.body)
  rescue StandardError => e
    Honeybadger.notify(e, context: { job_id: @job.id, url: url, phase: "headless_fallback" })
    nil
  ensure
    browser&.quit
  end

  # Resolves the actual content root of a parsed page/fragment, shared by
  # both the HTML- and plain-text-producing extractors below. Prefer a
  # page's own content wrapper when it has a reliable one, rather than the
  # whole document. `.prose` is Tailwind Typography's actual class name for
  # "this element is rendered article/description body" - a real
  # convention, not a Klix-specific guess - and confirmed live on Klix to
  # contain exactly the posting text with nothing else: no repeated title
  # heading, no breadcrumb, no "Objavio ... " publication line (all of
  # which live in sibling elements outside it, and which duplicate data
  # already shown elsewhere in the UI - job.title, job.created_at,
  # job.company, job.location). Falls back to <main>, then <body>, then the
  # whole document/fragment for pages with none of these landmarks, so this
  # only narrows extraction when there's an actual signal to do so, never
  # guesses.
  def content_root(doc)
    doc.at_css(".prose") || doc.at_css("main") || doc.at_css("body") || doc
  end

  # Produces the [html, text] pair actually stored/analyzed: html is a
  # sanitized fragment (ALLOWED_DESCRIPTION_TAGS only, no attributes at
  # all - so no link, no inline style, no event handler survives) giving
  # the posting real visual structure once rendered through Tailwind
  # Typography; text is the exact same content flattened to plain lines,
  # derived from that same sanitized html (not computed separately) so the
  # two can never describe different content. Real job-posting prose is
  # never mangled by the round-trip through sanitize - it only ever drops
  # tags/attributes this app doesn't want kept anyway.
  def extract_readable_content(doc)
    root = content_root(doc)
    html = Rails::Html::SafeListSanitizer.new.sanitize(root.inner_html, tags: ALLOWED_DESCRIPTION_TAGS, attributes: [])
    [ html, extract_readable_text(Nokogiri::HTML.fragment(html)) ]
  end

  # doc.text alone concatenates every text node with no separation - a
  # posting laid out as <p>About us</p><p>We build...</p><li>Ruby</li>
  # <li>Rails</li> used to collapse into one unreadable run-on line
  # ("About usWe build...RubyRails") once the old code's blanket
  # `gsub(/\s+/, " ")` also erased the handful of real newlines that had
  # survived. Inserting a newline after every block-level element (and
  # turning <br> into one directly) before extracting text keeps each
  # paragraph/list item/heading on its own line - used for the AI prompt and
  # for every length comparison in #call, not for what's actually stored
  # (see #extract_readable_content for that).
  def extract_readable_text(doc)
    root = content_root(doc)

    root.css("br").each { |node| node.replace("\n") }
    root.css(BLOCK_TAGS.join(", ")).each { |node| node.add_child(Nokogiri::XML::Text.new("\n", doc)) }

    root.text
      .split("\n")
      .map { |line| line.gsub(/[ \t]+/, " ").strip }
      .reject(&:blank?)
      .join("\n")
  end

  def extract_email(doc)
    mailto = doc.at_css("a[href^='mailto:']")
    return mailto["href"].sub(/^mailto:/, "").split("?").first.strip if mailto

    doc.text[EMAIL_REGEX]
  end

  # Only fills in a logo the company doesn't already have, and only from an
  # image actually hosted on the company's own resolved domain - a job
  # board's own og:image (its own logo) shows up on every single posting on
  # that board, exactly the same trap as Klix's sitewide "contact us"
  # mailto: link that Track A already learned to check for. No resolved
  # domain (Company#domain, set by EmailFinderService) means no match is
  # even possible, so this just skips rather than guessing.
  def extract_and_attach_company_logo(doc)
    return if @job.company.logo.attached?

    domain = @job.company.domain
    return if domain.blank?

    og_image = doc.at_css('meta[property="og:image"]')&.[]("content")
    return if og_image.blank?

    image_host = URI.parse(og_image).host
    return if image_host.blank?
    return unless image_host.include?(domain) || domain.include?(image_host)

    downloaded = URI.open(og_image, REQUEST_HEADERS.merge(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT))
    filename = File.basename(URI.parse(og_image).path.to_s)
    filename = "logo.jpg" if filename.blank? || !filename.include?(".")

    @job.company.update!(logo: { io: downloaded, filename: filename, content_type: downloaded.content_type })
  rescue StandardError => e
    Honeybadger.notify(e, context: { job_id: @job.id, company_id: @job.company.id, og_image: og_image })
  end
end
