# app/controllers/jobs_controller.rb
class JobsController < ApplicationController
  before_action :authenticate_user!

  POSTED_WITHIN_DAYS = { "1" => 1, "3" => 3, "7" => 7, "30" => 30 }.freeze

  def index
    @saved_job_ids = current_user.applications.pluck(:job_id)
    @query = params[:q].to_s.strip
    preference = current_user.user_preference

    @jobs = Job.visible_to(current_user).includes(:company, :job_sources)

    if @query.present?
      # A one-off search overrides the radar's keyword filter for this
      # request only - it's meant to look beyond your saved keywords, not
      # narrow further within them.
      @jobs = @jobs.left_joins(:company).where(
        "jobs.title ILIKE :q OR companies.name ILIKE :q", q: "%#{@query}%"
      )
    elsif preference && preference.keyword_array.any?
      # This dynamically generates a SQL query like:
      # title ILIKE '%developer%' OR title ILIKE '%software%'
      conditions = preference.keyword_array.map { |kw| "title ILIKE ?" }.join(" OR ")
      values = preference.keyword_array.map { |kw| "%#{kw}%" }

      @jobs = @jobs.where(conditions, *values)
    end

    @jobs = @jobs.where(location: params[:location]) if params[:location].present?

    # A subquery (not a join) so it composes cleanly with the company-name
    # sort's own join below without needing DISTINCT (which Postgres would
    # then require every ORDER BY column to appear in the SELECT list for).
    if params[:source].present?
      @jobs = @jobs.where(id: JobSource.where(source_name: params[:source]).select(:job_id))
    end

    @jobs = @jobs.where.not(hr_email: [ nil, "" ]) if params[:has_contact] == "1"

    if POSTED_WITHIN_DAYS.key?(params[:posted_within])
      @jobs = @jobs.where(created_at: POSTED_WITHIN_DAYS[params[:posted_within]].days.ago..)
    end

    @jobs = @jobs.merge(Job.expiring_soon) if params[:expiring_soon] == "1"

    @jobs = sort_jobs(@jobs, params[:sort])

    @pagy, @jobs = pagy(@jobs, items: 24)

    @locations = Job.visible_to(current_user).distinct.where.not(location: [ nil, "" ]).order(:location).pluck(:location)
    @sources = JobSource.distinct.order(:source_name).pluck(:source_name)
    @radar_keywords = preference&.keyword_array
  end

  def show
    @job = Job.visible_to(current_user).includes(:company, job_sources: []).find(params[:id])
    @saved = current_user.applications.exists?(job_id: @job.id)
    @radar_keywords = current_user.user_preference&.keyword_array
  end

  def new
    @job = Job.new
  end

  def create
    attrs = job_params
    company_logo = attrs[:company_logo]

    @job = Job.new(attrs.except(:company_logo))
    @job.url = @job.url.presence
    @job.apply_url = @job.apply_url.presence
    @job.added_by = current_user

    if @job.company_name.blank?
      @job.errors.add(:company_name, :blank)
      render :new, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      @job.company = Company.find_or_create_by!(name: @job.company_name.strip)
      @job.company.update!(logo: company_logo) if company_logo.present?
      @job.save!
    end

    # Straight onto the user's own board, wishlist status - the whole point
    # of adding it by hand is to track it, same as saving a scraped one.
    current_user.applications.find_or_create_by(job: @job) { |a| a.status = "wishlist" }

    # Reuse the existing AI enrichment pipeline when there's a URL to fetch -
    # but only if the user left the description blank. AiJobAnalyzerService
    # unconditionally overwrites `description` with whatever it scrapes off
    # the page (that's correct for a scraper's own placeholder text, but
    # would silently clobber something the user deliberately typed here).
    # It's also the same pass that tries to pick up a company logo from the
    # page's og:image, if none was uploaded directly here.
    AnalyzeJob.perform_later(@job.id) if @job.url.present? && @job.description.blank?

    redirect_to crm_path, notice: t("flash.applications.added_to_wishlist", job: @job.title)
  rescue ActiveRecord::RecordInvalid => e
    # Could be @job itself or @job.company (a bad logo upload, most likely)
    # - either way, surface it through the same @job.errors the form
    # already renders from, rather than needing two separate error boxes.
    @job.errors.merge!(e.record.errors) unless e.record.equal?(@job)
    render :new, status: :unprocessable_entity
  end

  # Anyone who can see the job can share it (same Job.visible_to rule as
  # everywhere else) - a scraped job is already public, and sharing your
  # own manual find with someone who has no account is the actual point.
  def share
    @job = Job.visible_to(current_user).find(params[:id])
    @job.share!
    redirect_to job_path(@job), notice: t("flash.jobs.shared")
  end

  def unshare
    @job = Job.visible_to(current_user).find(params[:id])
    @job.unshare!
    redirect_to job_path(@job), notice: t("flash.jobs.unshared")
  end

  private

  def job_params
    params.require(:job).permit(
      :title, :company_name, :company_logo, :url, :apply_url, :location, :hr_email,
      :description, :expires_at, :employment_type, :work_mode, :salary_range
    )
  end

  def sort_jobs(scope, sort)
    case sort
    when "deadline"
      # Jobs with no known deadline sort last either way - they're not more
      # urgent than one that's actually expiring soon.
      scope.order(Arel.sql("expires_at ASC NULLS LAST"))
    when "company"
      scope.left_joins(:company).order("companies.name ASC")
    else
      scope.order(created_at: :desc)
    end
  end
end
