# app/controllers/jobs_controller.rb
class JobsController < ApplicationController
  before_action :authenticate_user!

  POSTED_WITHIN_DAYS = { "1" => 1, "3" => 3, "7" => 7, "30" => 30 }.freeze

  def index
    @saved_job_ids = current_user.applications.pluck(:job_id)
    @query = params[:q].to_s.strip
    preference = current_user.user_preference

    @jobs = Job.includes(:company, :job_sources)

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

    @locations = Job.distinct.where.not(location: [ nil, "" ]).order(:location).pluck(:location)
    @sources = JobSource.distinct.order(:source_name).pluck(:source_name)
  end

  def show
    @job = Job.includes(:company, job_sources: []).find(params[:id])
    @saved = current_user.applications.exists?(job_id: @job.id)
  end

  private

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
