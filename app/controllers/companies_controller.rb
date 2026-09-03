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

    # A plain left_joins(:jobs) would count every job under the company,
    # including another user's private manually-added one (see Job.visible_to)
    # - the count itself is a much smaller leak than showing the job outright,
    # but "private" should mean private everywhere, not just on the job's own
    # page. Same NULLS-still-a-match LEFT JOIN condition as Job.visible_to,
    # written as raw SQL since a parameterized association scope can't be
    # used inside a join/select like this.
    jobs_join = ActiveRecord::Base.sanitize_sql_array([
      "LEFT JOIN jobs ON jobs.company_id = companies.id AND (jobs.added_by_id IS NULL OR jobs.added_by_id = ?)",
      current_user.id
    ])
    @companies = companies_page.joins(jobs_join).select("companies.*, COUNT(jobs.id) AS jobs_count").group("companies.id").to_a

    @industry_codes = Company.distinct.where.not(industry_code: [ nil, "" ]).order(:industry_code).pluck(:industry_code)
  end

  def show
    @company = Company.find(params[:id])
    @jobs = @company.jobs.visible_to(current_user).order(created_at: :desc)
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
      redirect_to compose_outreach_company_path(@company), alert: t("flash.applications.sending_disabled")
      return
    end

    if template_id.blank? || resume_blob_id.blank?
      redirect_to compose_outreach_company_path(@company), alert: t("flash.applications.select_template_and_resume")
      return
    end

    unless sendable?(@company)
      redirect_to compose_outreach_company_path(@company),
        alert: t("flash.companies.no_contact_email", company: @company.name)
      return
    end

    if current_user.remaining_daily_sends <= 0
      redirect_to compose_outreach_company_path(@company),
        alert: t("flash.applications.follow_up_daily_limit_reached", cap: Rails.application.config.daily_send_cap)
      return
    end

    SendColdOutreachJob.perform_later(current_user.id, @company.id, template_id, resume_blob_id, I18n.locale.to_s)

    redirect_to company_path(@company), notice: t("flash.companies.outreach_sending", company: @company.name)
  end

  def refresh_email
    @company = Company.find(params[:id])
    FindCompanyEmailJob.perform_later(@company.id)
    redirect_to company_path(@company), notice: t("flash.companies.looking_up_email", company: @company.name)
  end

  private

  def sendable?(company)
    Rails.application.config.dry_run_emails || company.primary_email.present?
  end
end
