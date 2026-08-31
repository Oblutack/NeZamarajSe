# db/seeds.rb
puts "🌱 Seeding Scraper Configurations..."

ScraperConfig.destroy_all # Clear old configs to avoid duplicates

# 1. Dzobs IT Jobs
ScraperConfig.create!(
  site_name: "Dzobs IT",
  url: "https://dzobs.com/poslovi/it-software",
  card_selector: "a[href^='/posao/']",
  title_selector: "h4",
  company_selector: "p.text-sm",
  link_selector: "self",
  next_page_selector: "a[rel='next']" # Assuming this is their standard next button
)

# 2. Dzobs Management/Marketing Jobs
ScraperConfig.create!(
  site_name: "Dzobs Management",
  url: "https://dzobs.com/poslovi/menadzment-upravljanje",
  card_selector: "a[href^='/posao/']",
  title_selector: "h4",
  company_selector: "p.text-sm",
  link_selector: "self",
  next_page_selector: "a[rel='next']"
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
ScraperConfig.create!(
  site_name: "MojPosao",
  url: "https://www.mojposao.ba/pretraga-poslova",
  card_selector: ".search-results-ad-type .job-card",
  title_selector: "[data-test='job-card-content-title']",
  company_selector: ".mp-text__default--semibold, .logo-container__image",
  link_selector: "a",
  next_page_selector: nil
)

# 4. ITBase.ba - niche Bosnian IT-only board, real <a rel="next"> pagination.
ScraperConfig.create!(
  site_name: "ITBase.ba",
  url: "https://itbase.ba/poslovi",
  card_selector: ".flex.items-center.bg-white",
  title_selector: "h3",
  company_selector: "h4",
  link_selector: "a",
  next_page_selector: "a[rel='next']"
)

# 5. Jooble (aggregator) - selectors mapped and verified against the live DOM, but
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
# boljiposao.com (loads blank - broken frontend). None were reliable enough to seed.

puts "✅ Seeding complete!"
