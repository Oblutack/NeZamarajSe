# app/jobs/find_company_email_job.rb
class FindCompanyEmailJob < ApplicationJob
  queue_as :default

  def perform(company_id)
    company = Company.find_by(id: company_id)
    return unless company

    EmailFinderService.call(company)
  rescue StandardError => e
    Rails.logger.error "Email lookup failed for Company #{company_id}: #{e.message}"
    raise e
  end
end
