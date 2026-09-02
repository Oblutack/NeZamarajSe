# app/controllers/companies_controller.rb
class CompaniesController < ApplicationController
  before_action :authenticate_user!

  def index
    @companies = Company.order(:name)

    if params[:has_email] == "1"
      @companies = @companies.where.not(primary_email: [ nil, "" ])
    elsif params[:has_email] == "0"
      @companies = @companies.where(primary_email: [ nil, "" ])
    end

    if params[:cold] == "1"
      @companies = @companies.where(is_cold_outreach: true)
    elsif params[:cold] == "0"
      @companies = @companies.where(is_cold_outreach: false)
    end

    @companies = @companies.where(industry_code: params[:industry_code]) if params[:industry_code].present?

    # The dedicated `city` column is never actually populated by either
    # scraper (CompanyWallScraper only fills in the freeform `address`
    # string, which is where the city name actually lives) - filter against
    # that instead of a column that's always blank.
    @companies = @companies.where("address ILIKE ?", "%#{params[:city]}%") if params[:city].present?

    # Paginate the plain filtered relation first (so Pagy's own .count call
    # gets a straightforward Integer back), then layer the jobs_count
    # annotation onto just that page - grouping the already limit/offset
    # relation directly would make Pagy try to .count a SELECT with a raw
    # SQL column in it, which Postgres rejects (see CompaniesController's
    # git history / ROADMAP.md Track C for the exact error this avoids).
    @pagy, companies_page = pagy(@companies)
    @companies = companies_page.left_joins(:jobs).select("companies.*, COUNT(jobs.id) AS jobs_count").group("companies.id").to_a

    @industry_codes = Company.distinct.where.not(industry_code: [ nil, "" ]).order(:industry_code).pluck(:industry_code)
  end

  def show
    @company = Company.find(params[:id])
    @jobs = @company.jobs.order(created_at: :desc)
  end

  def compose_outreach
    @company = Company.find(params[:id])
    @templates = current_user.cover_letter_templates
    @resumes = current_user.resumes

    @selected_template = @templates.find_by(id: params[:template_id])
    @selected_resume = @resumes.find { |r| r.blob_id == params[:resume_blob_id].to_i } if params[:resume_blob_id].present?
  end

  def dispatch_outreach
    @company = Company.find(params[:id])
    template_id = params[:template_id]
    resume_blob_id = params[:resume_blob_id]

    unless Rails.application.config.sending_enabled
      redirect_to compose_outreach_company_path(@company), alert: "Sending is currently disabled for the whole app - nothing was queued."
      return
    end

    if template_id.blank? || resume_blob_id.blank?
      redirect_to compose_outreach_company_path(@company), alert: "Please select both a template and a resume."
      return
    end

    unless sendable?(@company)
      redirect_to compose_outreach_company_path(@company),
        alert: "#{@company.name} has no known contact email, and dry-run mode is off - there's nowhere to send this."
      return
    end

    if current_user.remaining_daily_sends <= 0
      redirect_to compose_outreach_company_path(@company),
        alert: "You've hit today's limit of #{Rails.application.config.daily_send_cap} sends - try again tomorrow."
      return
    end

    SendColdOutreachJob.perform_later(current_user.id, @company.id, template_id, resume_blob_id)

    redirect_to company_path(@company), notice: "Outreach email to #{@company.name} is being sent in the background."
  end

  def refresh_email
    @company = Company.find(params[:id])
    FindCompanyEmailJob.perform_later(@company.id)
    redirect_to company_path(@company), notice: "Looking up a contact email for #{@company.name} - refresh in a moment."
  end

  private

  def sendable?(company)
    Rails.application.config.dry_run_emails || company.primary_email.present?
  end
end
