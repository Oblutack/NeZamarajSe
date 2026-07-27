# app/jobs/analyze_job_job.rb
class AnalyzeJobJob < ApplicationJob
  # We use the default queue for data processing
  queue_as :default

  def perform(job_id)
    job = Job.find_by(id: job_id)
    return unless job

    # Call our AI Service!
    AiJobAnalyzerService.call(job)
  rescue StandardError => e
    Rails.logger.error "AI Analysis failed for Job #{job_id}: #{e.message}"
    raise e
  end
end
