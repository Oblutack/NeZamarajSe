# app/jobs/analyze_job_job.rb
class AnalyzeJob < ApplicationJob
  queue_as :default

  def perform(job_id, skip_email_lookup: false)
    job = Job.find_by(id: job_id)
    return unless job
    AiJobAnalyzerService.call(job, skip_email_lookup: skip_email_lookup)
  rescue StandardError => e
    Rails.logger.error "AI Analysis failed for Job #{job_id}: #{e.message}"
    Honeybadger.notify(e, context: { job_id: job_id })
    raise e
  end
end
