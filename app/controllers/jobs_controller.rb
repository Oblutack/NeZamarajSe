# app/controllers/jobs_controller.rb
class JobsController < ApplicationController
  before_action :authenticate_user!

  def index
    @saved_job_ids = current_user.applications.pluck(:job_id)
    @query = params[:q].to_s.strip
    preference = current_user.user_preference

    # Start with all jobs
    @jobs = Job.includes(:company).order(created_at: :desc)

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

    # TODO: In the future, we can add location filtering here too!
  end
end
