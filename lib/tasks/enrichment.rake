# lib/tasks/enrichment.rake
namespace :enrichment do
  desc "Enqueue AnalyzeJob for every job still carrying its scrape-time placeholder description, skipping the Hunter.io fallback (see ROADMAP.md Track A's backlog note)"
  task drain_backlog: :environment do
    jobs = Job.where("description LIKE ?", "Scraped via %")
    count = jobs.count

    puts "Enqueuing #{count} job(s) for analysis (Hunter.io fallback skipped - page-scraped/AI-extracted emails only)..."

    jobs.find_each do |job|
      AnalyzeJob.perform_later(job.id, skip_email_lookup: true)
    end

    puts "Done. Enqueued #{count} AnalyzeJob(s)."
  end

  desc "Re-fetch and re-analyze every job with a URL, skipping the Hunter.io fallback - used to reformat descriptions that were already fetched before a formatting fix to AiJobAnalyzerService (e.g. paragraph/list structure, anchor-tag chrome stripping)"
  task reformat_descriptions: :environment do
    jobs = Job.where.not(url: nil)
    count = jobs.count

    puts "Re-enqueuing #{count} job(s) for analysis (Hunter.io fallback skipped)..."

    jobs.find_each do |job|
      AnalyzeJob.perform_later(job.id, skip_email_lookup: true)
    end

    puts "Done. Enqueued #{count} AnalyzeJob(s)."
  end
end
