# app/services/scrapers/cross_posting_recordable.rb
#
# Shared by UniversalJobScraper and ItKarijeraScraper: both dedupe a
# re-encountered listing the same way (exact url first, company+title as a
# fallback for aggregator sites that link through their own redirect url),
# and both should record every board a job is actually seen on rather than
# silently discarding the fact that it was cross-posted.
module Scrapers
  module CrossPostingRecordable
    private

    # Returns true if `title`+`company` already matches an existing Job (the
    # aggregator-style dedup fallback) - the existing job gets this board
    # recorded as one of its sources either way, so the caller should `next`
    # rather than create a duplicate Job row.
    def record_or_skip_duplicate?(company, title, source_name, job_url)
      existing_job = Job.find_by(company_id: company.id, title: title)
      return false unless existing_job

      record_job_source!(existing_job, source_name, job_url)
      true
    end

    # find_or_create_by (unique on job_id+source_name) makes re-scraping the
    # same board on a later day a no-op - only the first sighting per board
    # is what "posted on N boards" should count.
    def record_job_source!(job, source_name, job_url)
      job.job_sources.find_or_create_by!(source_name: source_name) do |source|
        source.url = job_url
      end
    end
  end
end
