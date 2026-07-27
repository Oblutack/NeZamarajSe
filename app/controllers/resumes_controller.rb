# app/controllers/resumes_controller.rb
class ResumesController < ApplicationController
  # Devise Magic: Forces the user to be logged in to access ANY action in this controller
  before_action :authenticate_user!

  def index
    # Fetch all resumes attached to the current user, newest first
    @resumes = current_user.resumes.order(created_at: :desc)
  end

  def create
    # Check if a file was actually submitted
    if params[:resume].present?
      # Active Storage Magic: .attach saves the file to disk and creates the DB records
      current_user.resumes.attach(params[:resume])
      redirect_to resumes_path, notice: "Resume uploaded successfully!"
    else
      redirect_to resumes_path, alert: "Please select a PDF to upload."
    end
  end

  def destroy
    @resume = current_user.resumes.find(params[:id])
    # Active Storage Magic: .purge deletes the file from disk AND removes the database record
    @resume.purge

    # In Rails 7/Hotwire, redirects after a DELETE request must include status: :see_other (303)
    redirect_to resumes_path, notice: "Resume deleted.", status: :see_other
  end
end
