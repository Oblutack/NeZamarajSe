# app/controllers/applications_controller.rb
class ApplicationsController < ApplicationController
  before_action :authenticate_user!

  def index
    # 1. Fetch all applications and include the job/company to prevent N+1 queries
    @applications = current_user.applications.includes(job: :company)

    # 2. Group them by status. This creates a Hash: { "wishlist" => [...], "applied" => [...] }
    @grouped_applications = Application.statuses.keys.index_with do |status|
      @applications.select { |app| app.status == status }
    end
  end

  def create
    @job = Job.find(params[:job_id])
    @application = current_user.applications.find_or_create_by(job: @job) do |app|
      app.status = "wishlist"
    end
    redirect_to jobs_path, notice: "#{@job.title} added to your CRM Wishlist!"
  end

  def update
    @application = current_user.applications.find(params[:id])

    # Update the status (e.g., from 'wishlist' to 'applied')
    if @application.update(application_params)
      redirect_to crm_path
    end
  end

  def destroy
    @application = current_user.applications.find(params[:id])
    @application.destroy
    redirect_to crm_path, notice: "Removed from CRM.", status: :see_other
  end

  private

  def application_params
    params.require(:application).permit(:status)
  end
end
