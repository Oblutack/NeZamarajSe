# app/controllers/applications_controller.rb
class ApplicationsController < ApplicationController
  before_action :authenticate_user!

  def index
    # 1. Fetch all applications and include the job/company to prevent N+1 queries
    @applications = current_user.applications.includes(job: :company)

    # 2. Group them by status, each column sorted so the most urgent deadline
    # bubbles to the top instead of arbitrary/insertion order - a job with no
    # known deadline sorts last, not first (nil isn't more urgent than a
    # real date). This creates a Hash: { "wishlist" => [...], "applied" => [...] }
    @grouped_applications = Application.statuses.keys.index_with do |status|
      @applications.select { |app| app.status == status }
        .sort_by { |app| app.job.expires_at || Date.new(9999, 12, 31) }
    end
  end

  def create
    @job = Job.find(params[:job_id])
    @application = current_user.applications.find_or_create_by(job: @job) do |app|
      app.status = "wishlist"
    end
    redirect_to jobs_path, notice: t("flash.applications.added_to_wishlist", job: @job.title)
  end

  def show
    @application = current_user.applications.includes(job: :company).find(params[:id])
  end

  def update
    @application = current_user.applications.find(params[:id])
    redirect_target = params[:application]&.key?("status") ? crm_path : application_path(@application)

    # Update the status (e.g., from 'wishlist' to 'applied') or, from the
    # detail page's own form, the CRM-depth fields (contact person, salary,
    # interview date, rejection reason) - same action either way, just a
    # different subset of application_params depending on which form posted.
    if @application.update(application_params)
      redirect_to redirect_target
    end
  end

  def add_note
    @application = current_user.applications.find(params[:id])
    body = params[:body].to_s.strip

    if body.present?
      @application.application_events.create!(event_type: "note", body: body)
    end

    redirect_to application_path(@application)
  end

  def destroy
    @application = current_user.applications.find(params[:id])
    @application.destroy
    redirect_to crm_path, notice: t("flash.applications.removed_from_crm"), status: :see_other
  end

  def compose
    @application = current_user.applications.find(params[:id])
    @templates = current_user.cover_letter_templates
    @resumes = current_user.resumes

    # Drives the live preview (see the compose view's turbo_frame) - nil
    # until the visitor has picked both, same as a fresh page load.
    @selected_template = @templates.find_by(id: params[:template_id])
    @selected_resume = @resumes.find { |r| r.blob_id == params[:resume_blob_id].to_i } if params[:resume_blob_id].present?
  end

  def dispatch_email
    @application = current_user.applications.find(params[:id])
    template_id = params[:template_id]
    resume_blob_id = params[:resume_blob_id]

    unless Rails.application.config.sending_enabled
      redirect_to compose_application_path(@application), alert: t("flash.applications.sending_disabled")
      return
    end

    if template_id.blank? || resume_blob_id.blank?
      redirect_to compose_application_path(@application), alert: t("flash.applications.select_template_and_resume")
      return
    end

    unless sendable?(@application)
      redirect_to compose_application_path(@application),
        alert: t("flash.applications.no_contact_email", job: @application.job.title)
      return
    end

    if current_user.remaining_daily_sends <= 0
      redirect_to compose_application_path(@application),
        alert: t("flash.applications.daily_limit_reached", cap: Rails.application.config.daily_send_cap)
      return
    end

    # 1. Move it to queued immediately so the UI feels instant; SendApplicationJob
    # flips it to "applied" only once Gmail actually confirms the send.
    @application.update!(status: "queued", queued_at: Time.current)

    # 2. Fire off the background job!
    SendApplicationJob.perform_later(@application.id, template_id, resume_blob_id, I18n.locale.to_s)

    redirect_to crm_path, notice: t("flash.applications.queued")
  end

  def compose_follow_up
    @application = current_user.applications.find(params[:id])
    @templates = current_user.cover_letter_templates
    @resumes = current_user.resumes

    @selected_template = @templates.find_by(id: params[:template_id])
    @selected_resume = @resumes.find { |r| r.blob_id == params[:resume_blob_id].to_i } if params[:resume_blob_id].present?
  end

  def dispatch_follow_up
    @application = current_user.applications.find(params[:id])
    template_id = params[:template_id]
    resume_blob_id = params[:resume_blob_id]

    unless Rails.application.config.sending_enabled
      redirect_to compose_follow_up_application_path(@application), alert: t("flash.applications.sending_disabled")
      return
    end

    if template_id.blank? || resume_blob_id.blank?
      redirect_to compose_follow_up_application_path(@application), alert: t("flash.applications.select_template_and_resume")
      return
    end

    unless sendable?(@application)
      redirect_to compose_follow_up_application_path(@application),
        alert: t("flash.applications.no_contact_email", job: @application.job.title)
      return
    end

    if current_user.remaining_daily_sends <= 0
      redirect_to compose_follow_up_application_path(@application),
        alert: t("flash.applications.follow_up_daily_limit_reached", cap: Rails.application.config.daily_send_cap)
      return
    end

    SendFollowUpJob.perform_later(@application.id, template_id, resume_blob_id, I18n.locale.to_s)

    redirect_to application_path(@application), notice: t("flash.applications.follow_up_queued")
  end

  def bulk_compose
    # params[:application_ids] comes in as an array of strings: ["1", "4", "5"]
    @applications = current_user.applications.where(id: params[:application_ids])

    if @applications.empty?
      redirect_to crm_path, alert: t("flash.applications.no_applications_selected")
      return
    end

    @templates = current_user.cover_letter_templates
    @resumes = current_user.resumes
  end

  def bulk_dispatch
    @applications = current_user.applications.where(id: params[:application_ids])
    template_id = params[:template_id]
    resume_blob_id = params[:resume_blob_id]

    unless Rails.application.config.sending_enabled
      redirect_to crm_path, alert: t("flash.applications.sending_disabled")
      return
    end

    if template_id.blank? || resume_blob_id.blank?
      redirect_to crm_path, alert: t("flash.applications.campaign_failed_select")
      return
    end

    sendable, unsendable = @applications.partition { |application| sendable?(application) }

    # The cap applies to the whole campaign, not just this action - truncate
    # rather than reject outright, so a big batch still sends as much of
    # itself as today's allowance covers instead of sending nothing.
    allowance = current_user.remaining_daily_sends
    over_cap = sendable.drop(allowance)
    sendable = sendable.first(allowance)

    sendable.each_with_index do |application, index|
      # 1. Move it to queued immediately; SendApplicationJob flips it to "applied"
      # only once Gmail actually confirms the send.
      application.update!(status: "queued", queued_at: Time.current)

      # 2. THE ANTI-SPAM DELAY ENGINE
      # App 0 -> waits 0 minutes (sends now)
      # App 1 -> waits 5 minutes
      # App 2 -> waits 10 minutes
      delay_time = (index * 5).minutes

      SendApplicationJob.set(wait: delay_time).perform_later(
        application.id,
        template_id,
        resume_blob_id,
        I18n.locale.to_s
      )
    end

    notice = t("flash.applications.campaign_launched", count: sendable.count)
    notice += " " + t("flash.applications.skipped_no_email", count: unsendable.count) if unsendable.any?
    notice += " " + t("flash.applications.skipped_over_limit", count: over_cap.count, cap: Rails.application.config.daily_send_cap) if over_cap.any?
    redirect_to crm_path, notice: notice
  end

  private

  def application_params
    params.require(:application).permit(:status, :contact_person, :salary, :interview_date, :rejection_reason)
  end

  # dry_run_emails on means every send lands in the user's own inbox
  # regardless of whether we know a real contact - safe to try even with no
  # recipient. Only refuse for real, once that safety net is off.
  def sendable?(application)
    Rails.application.config.dry_run_emails || application.intended_recipient.present?
  end
end
