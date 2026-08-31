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

  def compose
    @application = current_user.applications.find(params[:id])
    @templates = current_user.cover_letter_templates
    @resumes = current_user.resumes
  end

  def dispatch_email
    @application = current_user.applications.find(params[:id])
    template_id = params[:template_id]
    resume_blob_id = params[:resume_blob_id]

    if template_id.present? && resume_blob_id.present?
      # 1. Move it to queued immediately so the UI feels instant; SendApplicationJob
      # flips it to "applied" only once Gmail actually confirms the send.
      @application.update!(status: "queued")

      # 2. Fire off the background job!
      SendApplicationJob.perform_later(@application.id, template_id, resume_blob_id)

      redirect_to crm_path, notice: "Application queued! The email is being sent in the background."
    else
      redirect_to compose_application_path(@application), alert: "Please select both a template and a resume."
    end
  end

  def bulk_compose
    # params[:application_ids] comes in as an array of strings: ["1", "4", "5"]
    @applications = current_user.applications.where(id: params[:application_ids])

    if @applications.empty?
      redirect_to crm_path, alert: "No applications selected."
      return
    end

    @templates = current_user.cover_letter_templates
    @resumes = current_user.resumes
  end

  def bulk_dispatch
    @applications = current_user.applications.where(id: params[:application_ids])
    template_id = params[:template_id]
    resume_blob_id = params[:resume_blob_id]

    if template_id.present? && resume_blob_id.present?

      @applications.each_with_index do |application, index|
        # 1. Move it to queued immediately; SendApplicationJob flips it to "applied"
        # only once Gmail actually confirms the send.
        application.update!(status: "queued")

        # 2. THE ANTI-SPAM DELAY ENGINE
        # App 0 -> waits 0 minutes (sends now)
        # App 1 -> waits 5 minutes
        # App 2 -> waits 10 minutes
        delay_time = (index * 5).minutes

        SendApplicationJob.set(wait: delay_time).perform_later(
          application.id,
          template_id,
          resume_blob_id
        )
      end

      redirect_to crm_path, notice: "Campaign Launched! 🚀 #{@applications.count} applications are securely queued."
    else
      redirect_to crm_path, alert: "Campaign failed: Please select a template and resume."
    end
  end

  private

  def application_params
    params.require(:application).permit(:status)
  end
end
