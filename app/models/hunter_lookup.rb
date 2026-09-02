# app/models/hunter_lookup.rb
#
# One row per Hunter.io domain-search call actually made (not per company,
# not per attempt at resolving a domain - only the calls that hit Hunter's
# metered API). EmailFinderService checks this month's count against
# Rails.application.config.hunter_monthly_quota before calling Hunter at
# all - see config/initializers/enrichment_quota.rb.
class HunterLookup < ApplicationRecord
  belongs_to :company
end
