# app/jobs/analyze_job_job.rb
class AnalyzeJob < ApplicationJob
  queue_as :default

  def perform(job_id)
    job = Job.find_by(id: job_id)
    return unless job
    AiJobAnalyzerService.call(job)
  rescue StandardError => e
    Rails.logger.error "AI Analysis failed for Job #{job_id}: #{e.message}"
    raise e
  end
end
