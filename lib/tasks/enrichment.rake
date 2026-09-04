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
end
