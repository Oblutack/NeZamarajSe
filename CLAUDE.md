# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NeZamarajSe is a Rails 8 job-hunting SaaS / personal CRM for the Bosnian IT market. It scrapes job boards, uses an AI service to extract HR emails and application deadlines, resolves corporate domains for cold outreach, lets users manage applications through a Hotwire Kanban CRM board, and sends staggered automated cover-letter emails natively through the user's own Gmail account via the Gmail API.

**Hard stack rule:** stick to "The Rails Way" (Hotwire + server-rendered views). Do not introduce React/Vue or other heavy frontend frameworks.

## Stack

- Rails 8.1 / Ruby 3.3.4, PostgreSQL, Active Record Encryption for OAuth tokens
- Hotwire (Turbo Drive/Streams/Frames) + Stimulus, Tailwind CSS (`tailwindcss-rails`), Propshaft, Importmap (no Node/bundler JS toolchain)
- Sidekiq + `sidekiq-cron` for background jobs and scheduling (see `config/initializers/sidekiq.rb` and `config/recurring.yml` — two overlapping scheduling mechanisms exist, see below)
- Devise + OmniAuth (`omniauth-google-oauth2`) for auth; Google OAuth also supplies the Gmail-send scope
- Scraping: Ferrum (headless Chrome) + Nokogiri
- AI: `ruby-openai` gem pointed at Groq's OpenAI-compatible endpoint (`config/initializers/openai.rb`), model `llama-3.1-8b-instant`
- Company/domain enrichment: Clearbit Autocomplete (free, no key) → Hunter.io (keyed) for HR email guesses
- Deploy: Kamal (`config/deploy.yml`, `.kamal/`)

## Commands

```bash
bin/setup                 # bundle install, db:prepare, clear logs/tmp, then starts bin/dev
bin/dev                   # foreman: rails server + tailwindcss:watch + sidekiq worker (Procfile.dev)
bin/rails test                       # full test suite
bin/rails test test/models/job_test.rb               # single file
bin/rails test test/models/job_test.rb:12             # single test at line 12
bin/rails db:seed:replant            # reset + reseed (seeds ScraperConfig rows, etc.)
bin/rubocop                          # style lint (rubocop-rails-omakase)
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error   # security static analysis
bin/bundler-audit                    # gem vulnerability audit
bin/importmap audit                  # JS dependency audit
bin/ci                               # runs the full pipeline above (see config/ci.rb) — this is the canonical CI/pre-merge check
```

Sidekiq's web UI is mounted at `/sidekiq` (auth-gated, any logged-in user). Sidekiq-cron schedule is visible there too.

**GitHub Actions CI (`.github/workflows/ci.yml`) has no `RAILS_MASTER_KEY` secret configured** (commented out in the `test`/`system-test` jobs), and `config/master.key` is correctly gitignored, so it isn't in the checkout either. Two initializers used to call `Rails.application.credentials.dig(...)` unguarded at boot (`config/initializers/openai.rb` and the Google OmniAuth setup in `config/initializers/devise.rb`) — with no key available anywhere, that raises `ActiveSupport::EncryptedFile::MissingKeyError` and the whole app fails to boot, which would silently fail every CI job that boots Rails (`test`, `system-test`, and `scan_js`'s `bin/importmap audit`; the static-analysis jobs `scan_ruby`/`lint` don't boot Rails so they were unaffected). Fixed by rescuing `MissingKeyError` and falling back to `nil` in both initializers — verified by actually moving `config/master.key` aside locally and re-running `bin/rails db:test:prepare test` and `bin/importmap audit`, both now pass with no key present. If you add a new initializer that reads `Rails.application.credentials`, use the same rescue pattern, or CI will silently break again.

**Tailwind CSS is not auto-rebuilt if you only run `bin/rails server`** (as opposed to `bin/dev`, which also runs `tailwindcss:watch` via Procfile.dev). If you edit Tailwind classes and the page renders unstyled, that's why — run `bin/rails tailwindcss:build` once to pick up the new classes. In at least one dev environment (WSL), `tailwindcss:watch` itself doesn't stay running as a background process (exits immediately, no persistent stdin/TTY), so a one-shot `tailwindcss:build` after each round of view edits is the reliable move there.

Database credentials/name are in `config/database.yml` (local Postgres, `ne_zamaraj_se_development` / `_test`).

## Architecture

### Data ingestion & enrichment pipeline
1. `ScraperConfig` rows (DB-driven, not hardcoded) define per-site CSS selectors (`card_selector`, `title_selector`, `company_selector`, `link_selector`, `next_page_selector`) and the seed URL. `Scrapers::UniversalJobScraper` reads a config, drives Ferrum headless Chrome, paginates up to 5 pages, and `find_or_create`s `Company`/`Job` rows. Four configs are seeded (`db/seeds.rb`): Dzobs IT, Dzobs Management, ITBase.ba, and MojPosao — MojPosao is seeded unfiltered (no category param) since it's the only general-industry source of the four; Dzobs and ITBase.ba are both IT-only by nature of the sites themselves. A mapped-but-disabled Jooble config is commented out in `db/seeds.rb`: `ba.jooble.org` serves headless Ferrum a Cloudflare challenge page it can't get past.
2. `ScrapeJobBoardsJob` is Sidekiq-cron-scheduled daily and loops over every `ScraperConfig.where(active: true)` row, calling `UniversalJobScraper` for each. **This is the only thing that makes ingestion run on a schedule — a `ScraperConfig` row with nothing calling it, or a job class calling the wrong scraper, silently does nothing.** (This job used to call a different, dead-end legacy scraper that ignored `ScraperConfig` entirely and referenced a nonexistent `AnalyzeJobJob` constant — fixed, but worth remembering as a class of bug: always confirm a Sidekiq-cron `"class"` entry actually points at current code, not just that the code you're editing looks right in isolation.)
3. New `Job` rows enqueue `AnalyzeJob` → `AiJobAnalyzerService`, which re-fetches the job's own URL, strips it to text, and asks Groq/Llama-3.1 for `hr_email` + `expiration_date` as strict JSON.
4. `EmailFinderService` resolves a company's real domain via Clearbit (stripping legal suffixes like "d.o.o." from the name first) and then queries Hunter.io's domain-search for an HR/career/recruit-style address. It's currently only invoked for cold-outreach companies (via `FindCompanyEmailJob`, below) — `AiJobAnalyzerService` does not call it as a fallback when AI enrichment misses an email, despite that being the originally documented intent. Wiring that up is still open.
5. `Scrapers::CompanyWallScraper` crawls business directories (companywall.ba, NACE code 62.01) to seed `Company` records (`is_cold_outreach: true`) independent of job postings. It's active (confirmed getting past Cloudflare) and scheduled weekly via `ScrapeCompanyWallJob` — weekly rather than daily to stay light on a Cloudflare-protected target. Each newly-found company enqueues `FindCompanyEmailJob` → `EmailFinderService` to resolve its contact email.

### CRM / campaign sending engine
- `Application` is the join model between `User` and `Job`, with a status enum (`wishlist → applied → interviewing/rejected/offered`) driving the Kanban board (`/crm`).
- Single dispatch: `ApplicationsController#dispatch_email` optimistically flips status to `applied` and enqueues `SendApplicationJob`.
- Bulk dispatch: `ApplicationsController#bulk_dispatch` enqueues one `SendApplicationJob` per selected application with a staggered delay (`index * 5.minutes`) specifically to avoid tripping Gmail/Google spam heuristics — do not remove this stagger.
- `SendApplicationJob` → `JobApplicationMailer` renders the `CoverLetterTemplate` (Liquid-style `{{smart_tags}}`, e.g. `{{company_name}}`) with the selected Active Storage resume PDF attached, then hands the raw MIME string to `GmailSenderService`, which sends it through the Gmail API using the user's own encrypted OAuth token (`User#access_token`/`refresh_token`, refreshed on demand) — not SMTP, so outbound mail carries no bot signature.
- Known gap (see ROADMAP.md): status is set to `applied` optimistically *before* Gmail confirms the send; there's a planned `queued` status to fix this race.

### Daily Radar
- `UserPreference` (1:1 with `User`) stores freeform `keywords` (comma-separated, parsed via `keyword_array`) and `receive_daily_alerts`. `Job#index` and the radar job both build the same `title ILIKE` OR-chain from `keyword_array` — if you change the matching logic, update both call sites (`JobsController#index` and `SendDailyRadarJob#perform`).
- `SendDailyRadarJob` runs daily (scheduled in `config/initializers/sidekiq.rb`'s `Sidekiq.configure_server` hash) and emails opted-in users a digest of jobs matching their keywords from the last 24h via `RadarMailer`.
- **Note:** `SendDailyRadarJob`'s source file lives at `app/views/jobs/send_daily_radar_job.rb` instead of `app/jobs/`. `app/views` is not an autoload path in a stock Rails app — if this job stops being resolvable (`NameError: uninitialized constant`), move the file to `app/jobs/send_daily_radar_job.rb`.

### Scheduling has two independent mechanisms
- `config/initializers/sidekiq.rb` loads a hash into `Sidekiq::Cron::Job` at boot (`scrape_job_boards_daily`, `send_radar_emails`, `scrape_company_wall_weekly`).
- `config/recurring.yml` is Solid Queue's own recurring-task config (currently only a production `clear_solid_queue_finished_jobs` cleanup).
These are separate systems (Sidekiq vs. Solid Queue) — check both when adding or debugging a scheduled task.

### Multi-tenancy
All CRM data is scoped through `current_user.applications` / `current_user.cover_letter_templates` / `current_user.resumes` in controllers — there is no soft global admin bypass. Jobs and Companies are shared/global (scraped once, visible to all users); Applications, CoverLetterTemplates, and Resumes are per-user.

## Known constraints from the Ferrum scraper

`Scrapers::UniversalJobScraper` and `Scrapers::CompanyWallScraper` wait on `browser.network.wait_for_idle` (not a blind `sleep`) after navigation — this fixed the blank-page/0-results failures ROADMAP.md Phase 1 originally flagged. `CompanyWallScraper` additionally sleeps ~3.5s first for Cloudflare's interstitial redirect timer, which fires with no network activity to wait on. Ferrum is launched with `no-sandbox`/`disable-dev-shm-usage` for headless Linux/WSL compatibility, plus `disable-blink-features: AutomationControlled` for `CompanyWallScraper` specifically — note that flag alone was not enough to get `ba.jooble.org` past its (harder) Cloudflare challenge, so don't assume it's a general fix.
