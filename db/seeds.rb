# db/seeds.rb
puts "🌱 Seeding Scraper Configurations..."

ScraperConfig.destroy_all # Clear old configs to avoid duplicates

# 1. Dzobs IT Jobs
# location_selector: each card's location pin+text sits in the first
# span.flex.items-center.gap-1 within the .text-xs.text-gray-500 meta row
# (a second such span holds the job-type badge, but is never first). No
# deadline shown on the card itself, so date_selector stays unset - AI
# enrichment is still the only source of expires_at for this site.
ScraperConfig.create!(
  site_name: "Dzobs IT",
  url: "https://dzobs.com/poslovi/it-software",
  card_selector: "a[href^='/posao/']",
  title_selector: "h4",
  company_selector: "p.text-sm",
  link_selector: "self",
  next_page_selector: "a[rel='next']", # Assuming this is their standard next button
  location_selector: ".text-xs.text-gray-500 span"
)

# 2. Dzobs Management/Marketing Jobs
ScraperConfig.create!(
  site_name: "Dzobs Management",
  url: "https://dzobs.com/poslovi/menadzment-upravljanje",
  card_selector: "a[href^='/posao/']",
  title_selector: "h4",
  company_selector: "p.text-sm",
  link_selector: "self",
  next_page_selector: "a[rel='next']",
  location_selector: ".text-xs.text-gray-500 span"
)

# 3. MojPosao.ba - unfiltered, all industries. This is the general-market source:
# Dzobs and ITBase are both IT-only by nature of the site, so this is the one
# config responsible for non-IT jobs existing at all. Per-user keyword matching
# (UserPreference#keyword_array, used by JobsController#index and
# SendDailyRadarJob) is what actually narrows this down for each user - it
# already supports arbitrary keywords, it just had nothing but IT jobs to match
# against before. Single page (~70 jobs, no pagination control found on this
# endpoint); card_selector is scoped to the results wrapper since on a narrower
# filtered search MojPosao backfills exhausted results with unrelated
# "recommended" jobs sharing the exact same .job-card markup.
# location_selector/date_selector: each card's `.content__info` row holds two
# `.info__child` spans - location first, then a second one (with the extra
# class .info__end-date) wrapping a `<time datetime="...">` for the deadline.
# `.info__child .mp-text` resolves to the *first* such span in document order
# (location); extract_expiry_date special-cases a matched <time> element and
# reads its datetime attribute directly rather than trying to parse the
# "Prijava do DD. MM. YYYY." prose around it - MojPosao is the one source
# where the deadline is already machine-readable, no guessing needed.
ScraperConfig.create!(
  site_name: "MojPosao",
  url: "https://www.mojposao.ba/pretraga-poslova",
  card_selector: ".search-results-ad-type .job-card",
  title_selector: "[data-test='job-card-content-title']",
  company_selector: ".mp-text__default--semibold, .logo-container__image",
  link_selector: "a",
  next_page_selector: nil,
  location_selector: ".info__child .mp-text",
  date_selector: ".info__end-date time"
)

# 4. ITBase.ba - niche Bosnian IT-only board, real <a rel="next"> pagination.
# location_selector: the location pin+text sits in the card's own
# .col-span-5.text-right column, opposite the company name's .col-span-7. No
# deadline shown on the card.
ScraperConfig.create!(
  site_name: "ITBase.ba",
  url: "https://itbase.ba/poslovi",
  card_selector: ".flex.items-center.bg-white",
  title_selector: "h3",
  company_selector: "h4",
  link_selector: "a",
  next_page_selector: "a[rel='next']",
  location_selector: ".col-span-5 span"
)

# 5. Klix Posao - job board run by Klix.ba, BiH's most-visited news site. General
# market like MojPosao (not IT-specific), server-rendered with clean pagination.
# The "next page" link's classes are shared with the "previous" link (both reuse
# the same Tailwind utility chain) and with every numbered page link too, so a
# plain CSS class selector would grab the wrong one depending on which page
# you're on - matched on visible text instead via Nokogiri's :contains()
# extension, which is stable across the whole listing (228+ live postings as
# of testing) and correctly returns nothing on the last page.
# location_selector targets the visible "grad" link rather than the
# favorite-btn's data-job-location attribute - simpler, since extract_text
# only reads element text/alt, not arbitrary data attributes, and the link
# text is exactly the same value. date_selector (".mb-3", unique within a
# card) holds a plain-text range like "02.09. – 02.10.2026" -
# extract_expiry_date takes the *last* date in it (the deadline, not the
# posting date).
ScraperConfig.create!(
  site_name: "Klix Posao",
  url: "https://posao.klix.ba/oglasi",
  card_selector: ".job-card",
  title_selector: "h4 a",
  company_selector: ".text-sm.text-gray-500.font-light.min-w-0.truncate a",
  link_selector: "h4 a",
  next_page_selector: "a:contains('Sljedeća')",
  location_selector: "a[href*='/grad/']",
  date_selector: ".mb-3"
)

# 6. Jooble (aggregator) - selectors mapped and verified against the live DOM, but
# NOT enabled: ba.jooble.org serves a Cloudflare "Just a moment..." challenge to
# our headless Ferrum browser (confirmed - neither disable-blink-features nor a
# longer wait gets past it), so this would silently find 0 jobs on every cron
# run. Leaving this here, commented out, for whoever solves the Cloudflare bypass
# (see ROADMAP.md Phase 3, which hits the same wall with CompanyWallScraper).
# Also note: Jooble links to its own redirect URL rather than the original
# posting, so it can't be deduped by URL alone once it is enabled - see the
# title+company fallback check in UniversalJobScraper. Results load via infinite
# scroll with no crawlable "next" link, so even once enabled this only gets
# page 1. Card markup uses hashed/minified CSS class names that will likely
# change on Jooble's next frontend deploy and need re-mapping.
# ScraperConfig.create!(
#   site_name: "Jooble IT",
#   url: "https://ba.jooble.org/SearchResult?ukw=IT",
#   card_selector: ".rHG1ci",
#   title_selector: "h2",
#   company_selector: "p.z6WlhX",
#   link_selector: "a.job_card_link",
#   next_page_selector: nil
# )

# NOTE: Posao.ba (dead domain, now redirects to an unrelated site) and HelloIT.ba
# (DNS no longer resolves) from the original roadmap targets are gone. Substitutes
# checked and rejected: job.ba (abandoned, ~2 listings site-wide), poslovnioglasi.ba
# (its job-search listing returns 0 results sitewide - broken, not just filtered),
# boljiposao.com (loads blank - broken frontend), poslovi.ba (no working "all
# jobs" browse page - /jobs just re-renders the homepage's small hot-jobs
# carousel; its 12 categories are industrial/blue-collar only - elektrotehnika,
# mašinstvo, građevina, transport, turizam, etc - with no IT/general category,
# so it wouldn't meaningfully add coverage even if scraped per-category). None
# were reliable enough to seed.

puts "✅ Seeding complete!"
