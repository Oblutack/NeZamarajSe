# config/initializers/enrichment_quota.rb
#
# Hunter.io's free tier is small (~25 domain-search calls/month) against a
# company list that's already in the hundreds and growing daily via
# CompanyWallScraper/AI-fallback enrichment - EmailFinderService checks
# this before every Hunter call (see HunterLookup) and skips it once the
# month's count reaches this, rather than silently burning through (or
# exceeding) the real account's ceiling with no visibility.
Rails.application.config.hunter_monthly_quota =
  ENV.fetch("HUNTER_MONTHLY_QUOTA", "25").to_i
