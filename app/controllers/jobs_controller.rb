# app/controllers/jobs_controller.rb
class JobsController < ApplicationController
  before_action :authenticate_user!

  def index
    @saved_job_ids = current_user.applications.pluck(:job_id)
    preference = current_user.user_preference

    # Start with all jobs
    @jobs = Job.includes(:company).order(created_at: :desc)

    # If the user has keywords, apply the SQL filter
    if preference && preference.keyword_array.any?
      # This dynamically generates a SQL query like:
      # title ILIKE '%developer%' OR title ILIKE '%software%'
      conditions = preference.keyword_array.map { |kw| "title ILIKE ?" }.join(" OR ")
      values = preference.keyword_array.map { |kw| "%#{kw}%" }

      @jobs = @jobs.where(conditions, *values)
    end

    # TODO: In the future, we can add location filtering here too!
  end
end
