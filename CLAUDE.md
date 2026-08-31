# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NeZamarajSe is a Rails 8 job-hunting SaaS / personal CRM for the Bosnian IT market. It scrapes job boards, uses an AI service to extract HR emails and application deadlines, resolves corporate domains for cold outreach, lets users manage applications through a Hotwire Kanban CRM board, and sends staggered automated cover-letter emails natively through the user's own Gmail account via the Gmail API. See `README.md` for the user-facing pitch and setup instructions — this file covers what that doesn't: architecture detail and gotchas relevant to making changes.

**Hard stack rule:** stick to "The Rails Way" (Hotwire + server-rendered views). Do not introduce React/Vue or other heavy frontend frameworks.

## Stack

- Rails 8.1 / Ruby 3.3.4, PostgreSQL, Active Record Encryption for OAuth tokens
- Hotwire (Turbo Drive/Streams/Frames) + Stimulus, Tailwind CSS v4 (`tailwindcss-rails`), Propshaft, Importmap (no Node/bundler JS toolchain)
- Sidekiq + `sidekiq-cron` for background jobs and scheduling (see `config/initializers/sidekiq.rb` and `config/recurring.yml` — two overlapping scheduling mechanisms exist, see below)
- Devise + OmniAuth (`omniauth-google-oauth2`) for auth; Google OAuth also supplies the Gmail-send scope
- Scraping: Ferrum (headless Chrome) + Nokogiri
- AI: `ruby-openai` gem pointed at Groq's OpenAI-compatible endpoint (`config/initializers/openai.rb`), model `llama-3.1-8b-instant`
- Company/domain enrichment: Clearbit Autocomplete (free, no key) → Hunter.io (keyed) for HR email guesses
- Error tracking: Honeybadger — every background job rescues, calls `Honeybadger.notify` with job-specific context, then re-raises so Sidekiq still retries. Follow this pattern in any new job.
- Deploy: Kamal (`config/deploy.yml`, `.kamal/`)

## Commands

```bash
bin/setup                 # bundle install, db:prepare, clear logs/tmp, then starts bin/dev
bin/dev                   # foreman: rails server + tailwindcss:watch + sidekiq worker (Procfile.dev)
bin/rails test                       # full test suite
bin/rails test test/models/job_test.rb               # single file
bin/rails test test/models/job_test.rb:12             # single test at line 12
bin/rails test:system                # system tests (test/system/) — Capybara + Selenium, real Chrome
bin/rails db:seed:replant            # reset + reseed (seeds ScraperConfig rows, etc.)
bin/rubocop                          # style lint (rubocop-rails-omakase)
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error   # security static analysis
bin/bundler-audit                    # gem vulnerability audit
bin/importmap audit                  # JS dependency audit
bin/ci                               # runs the full pipeline above (see config/ci.rb) — this is the canonical CI/pre-merge check
```

Sidekiq's web UI is mounted at `/sidekiq` (auth-gated, any logged-in user). Sidekiq-cron schedule is visible there too.

CI (`.github/workflows/ci.yml`) pins a specific Chrome + chromedriver version for the `system-test` job — if `bin/rails test:system` starts failing only in CI (not locally), a Chrome/driver version mismatch there is the first thing to check, not the test itself.

Database credentials/name are in `config/database.yml` (local Postgres, `ne_zamaraj_se_development` / `_test`). None of the external credentials (`groq`, `google`, `hunter`) are required to boot the app or run the test suite — each integration degrades to "unconfigured" rather than raising.

## Architecture

### Data ingestion & enrichment pipeline
1. `ScraperConfig` rows (DB-driven, not hardcoded) define per-site CSS selectors (`card_selector`, `title_selector`, `company_selector`, `link_selector`, `next_page_selector`) and the seed URL. `Scrapers::UniversalJobScraper` reads a config, drives Ferrum headless Chrome, paginates up to 5 pages, and `find_or_create`s `Company`/`Job` rows. `db/seeds.rb` seeds four active configs (Dzobs IT, Dzobs Management, MojPosao — unfiltered, the only general-industry source of the four — and ITBase.ba) plus a Jooble config that's mapped but left commented out: `ba.jooble.org` serves headless Ferrum a Cloudflare challenge it can't get past (same wall `CompanyWallScraper` hits, see below). Posao.ba and HelloIT.ba (original roadmap targets) are dead domains; substitutes were checked and rejected as unreliable — see the comments at the bottom of `db/seeds.rb` before re-investigating either.
2. `ScrapeJobBoardsJob` is Sidekiq-cron-scheduled daily and loops over every `ScraperConfig.where(active: true)` row, calling `UniversalJobScraper` for each. **This is the only thing that makes ingestion run on a schedule** — a `ScraperConfig` row with nothing calling it does nothing.
3. New `Job` rows enqueue `AnalyzeJob` → `AiJobAnalyzerService`, which re-fetches the job's own URL, strips it to text, and asks Groq/Llama-3.1 for `hr_email` + `expiration_date` as strict JSON. If the AI comes back with no email and the job's company doesn't have one resolved yet, it enqueues `FindCompanyEmailJob` as a fallback (guarded by `company.primary_email.blank?` so a company with many job postings doesn't trigger a repeat Hunter.io lookup per job).
4. `FindCompanyEmailJob` → `EmailFinderService` resolves a company's real domain via Clearbit (stripping legal suffixes like "d.o.o." from the name first) and then queries Hunter.io's domain-search for an HR/career/recruit-style address. It's the shared enrichment path for both the AI fallback above and cold-outreach companies below.
5. `Scrapers::CompanyWallScraper` crawls business directories (companywall.ba, NACE code 62.01) to seed `Company` records (`is_cold_outreach: true`) independent of job postings, each triggering its own `FindCompanyEmailJob`. It's scheduled weekly (not daily, to stay light on a Cloudflare-protected target) via `ScrapeCompanyWallJob`.

### CRM / campaign sending engine
- `Application` is the join model between `User` and `Job`, with a status enum (`wishlist → queued → applied → interviewing/rejected/offered`) driving the Kanban board (`/crm`). Status changes broadcast live over Turbo Streams (`after_update_commit -> { broadcast_status_update }` in the model) so other open tabs/board views update without a refresh.
- Single dispatch: `ApplicationsController#dispatch_email` moves the application to `queued` (not `applied`) and enqueues `SendApplicationJob`.
- Job Market cards (`/jobs`) swap their "Save to Wishlist" button for a "Saved in CRM" badge once the current user has an `Application` for that job — check `@saved_job_ids` in `JobsController#index` before adding a second entry point for the same action.
- Bulk dispatch: `ApplicationsController#bulk_dispatch` enqueues one `SendApplicationJob` per selected application with a staggered delay (`index * 5.minutes`) specifically to avoid tripping Gmail/Google spam heuristics — do not remove this stagger.
- `SendApplicationJob` → `JobApplicationMailer` renders the `CoverLetterTemplate` (Liquid-style `{{smart_tags}}`, e.g. `{{company_name}}`) with the selected Active Storage resume PDF attached, then hands the raw MIME string to `GmailSenderService`, which sends it through the Gmail API using the user's own encrypted OAuth token (`User#access_token`/`refresh_token`, refreshed on demand) — not SMTP, so outbound mail carries no bot signature. **Only after Gmail confirms the send** does the job flip the application to `applied` and set `applied_at`; a failed send leaves it at `queued` and re-raises so Sidekiq retries. Don't move the `applied` transition earlier in the flow — that race (marking it sent before it actually was) is exactly what the `queued` status exists to prevent.

### Daily Radar
- `UserPreference` (1:1 with `User`) stores freeform `keywords` (comma-separated, parsed via `keyword_array`) and `receive_daily_alerts`. `Job#index` and the radar job both build the same `title ILIKE` OR-chain from `keyword_array` — if you change the matching logic, update both call sites (`JobsController#index` and `SendDailyRadarJob#perform`).
- `SendDailyRadarJob` (`app/jobs/send_daily_radar_job.rb`) runs daily (scheduled in `config/initializers/sidekiq.rb`'s `Sidekiq.configure_server` hash) and emails opted-in users a digest of jobs matching their keywords from the last 24h via `RadarMailer`.

### Scheduling has two independent mechanisms
- `config/initializers/sidekiq.rb` loads a hash into `Sidekiq::Cron::Job` at boot (`scrape_job_boards_daily`, `send_radar_emails`, `scrape_company_wall_weekly`).
- `config/recurring.yml` is Solid Queue's own recurring-task config (currently only a production `clear_solid_queue_finished_jobs` cleanup).
These are separate systems (Sidekiq vs. Solid Queue) — check both when adding or debugging a scheduled task.

### Multi-tenancy
All CRM data is scoped through `current_user.applications` / `current_user.cover_letter_templates` / `current_user.resumes` in controllers — there is no soft global admin bypass. Jobs and Companies are shared/global (scraped once, visible to all users); Applications, CoverLetterTemplates, and Resumes are per-user.

## Known constraints from the Ferrum scraper

Both `Scrapers::UniversalJobScraper` and `Scrapers::CompanyWallScraper` wait on `browser.network.wait_for_idle` (not a blind `sleep`) after navigation, which is what makes them reliable against JS-rendered pages. `CompanyWallScraper` additionally sleeps ~3.5s first for Cloudflare's interstitial redirect timer, which fires with no network activity to wait on. Ferrum is launched with `no-sandbox`/`disable-dev-shm-usage` for headless Linux/WSL compatibility, plus `disable-blink-features: AutomationControlled` for `CompanyWallScraper` specifically — note that flag alone was not enough to get `ba.jooble.org` past its (harder) Cloudflare challenge, so don't assume it's a general fix. `UniversalJobScraper` dedupes new jobs first by exact `url`, then falls back to `company_id` + `title` — aggregator sites (e.g. Jooble, if ever enabled) link through their own redirect URL rather than the original posting, so URL-only dedup would let the same job back in under a different URL.
