# app/controllers/jobs_controller.rb
class JobsController < ApplicationController
  # We want users to log in to see the job market
  before_action :authenticate_user!

  def index
    # Fetch all jobs, include the company data to prevent N+1 queries, order by newest
    @jobs = Job.includes(:company).order(created_at: :desc)

    # We also want to know which jobs the user has ALREADY saved, so we can hide the "Save" button
    @saved_job_ids = current_user.applications.pluck(:job_id)
  end
end
