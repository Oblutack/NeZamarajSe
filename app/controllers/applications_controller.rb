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
      @applications.select { |app| app.status == status }.sort_by(&:deadline_sort_key)
    end
  end

  def create
    @job = Job.visible_to(current_user).find(params[:job_id])
    @application = current_user.applications.find_or_create_by(job: @job) do |app|
      app.status = "wishlist"
    end
    redirect_to jobs_path, notice: t("flash.applications.added_to_wishlist", job: @job.title)
  end

  def show
    @application = current_user.applications.includes(job: :company).find(params[:id])
  end

  # Two callers: the Kanban board (a drag or the card's "Move to…" menu, which
  # sends a status) and the detail page's own form (contact person, salary,
  # interview date, rejection reason - no status). The board gets Turbo Stream
  # actions back so the card moves without re-rendering the page; the detail
  # form keeps its plain redirect.
  def update
    @application = current_user.applications.find(params[:id])
    new_status = params[:application]&.[]("status")

    return update_details if new_status.blank?
    return unless allow_status_move?(new_status)

    from_status = @application.status

    if @application.update(application_params)
      render_status_change(from_status)
    else
      render_board_alert(@application.errors.full_messages.to_sentence)
    end
  end

  def interview_ics
    @application = current_user.applications.find(params[:id])

    if @application.interview_date.blank?
      redirect_to application_path(@application), alert: t("flash.applications.no_interview_date")
      return
    end

    send_data @application.interview_ics,
      filename: "interview-#{@application.job.company.name.parameterize}.ics",
      type: "text/calendar; charset=utf-8",
      disposition: "attachment"
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

  # Drafts a one-off cover letter for this specific application via
  # CoverLetterGeneratorService, then saves it as a real CoverLetterTemplate
  # (ai_generated: true) and redirects straight back into the normal compose
  # preview with it selected - reuses render_content, the preview, the
  # dispatch form, and sent-email history exactly as they already work for
  # a hand-written template. Nothing downstream needed to change.
  def generate_cover_letter
    @application = current_user.applications.find(params[:id])
    resume = current_user.resumes.find { |r| r.blob_id == params[:resume_blob_id].to_i }

    if resume.nil?
      redirect_to compose_application_path(@application), alert: t("flash.applications.select_a_resume_first")
      return
    end

    language = params[:language]
    body_html = CoverLetterGeneratorService.call(job: @application.job, resume_blob: resume.blob, language: language)

    template = current_user.cover_letter_templates.create!(
      name: CoverLetterTemplate.unique_ai_name(current_user, "AI: #{@application.job.title} (#{l(Time.current, format: '%b %-d, %H:%M:%S')})"),
      body: body_html,
      ai_generated: true,
      language: CoverLetterTemplate::LANGUAGES.key?(language) ? language : "en"
    )

    redirect_to compose_application_path(@application, template_id: template.id, resume_blob_id: resume.blob.id)
  rescue StandardError => e
    Honeybadger.notify(e, context: { application_id: params[:id] })
    redirect_to compose_application_path(@application), alert: t("flash.applications.generation_failed")
  end

  # Re-translates an AI-drafted template in place (see
  # CoverLetterTranslatorService) rather than creating a second draft -
  # editing a template's body later has always been safe, since a past
  # send's sent_body is captured independently onto the Application at send
  # time (SendApplicationJob), not read live from the template afterward.
  def translate_cover_letter
    @application = current_user.applications.find(params[:id])
    template = current_user.cover_letter_templates.find(params[:template_id])
    language = params[:language]

    translated_html = CoverLetterTranslatorService.call(plain_text: template.body.to_plain_text, target_language: language)
    template.update!(body: translated_html, language: CoverLetterTemplate::LANGUAGES.key?(language) ? language : "en")

    redirect_to compose_application_path(@application, template_id: template.id, resume_blob_id: params[:resume_blob_id])
  rescue StandardError => e
    Honeybadger.notify(e, context: { application_id: params[:id], template_id: params[:template_id] })
    redirect_to compose_application_path(@application), alert: t("flash.applications.translation_failed")
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

  # A queued send (single or, more importantly, a staggered bulk campaign -
  # up to 45 minutes between the first and last email) can be called back
  # right up until Gmail actually confirms it. SendApplicationJob re-checks
  # status before ever sending, so this is a real cancel, not just a UI
  # illusion. Reverting to "wishlist" mirrors the only status dispatch ever
  # starts from (see application_card's own "wishlist only" Apply button),
  # and clearing queued_at hands back the daily allowance it had reserved.
  def cancel
    @application = current_user.applications.find(params[:id])

    if @application.queued?
      @application.update!(status: "wishlist", queued_at: nil)
      redirect_back fallback_location: crm_path, notice: t("flash.applications.send_canceled")
    else
      redirect_back fallback_location: crm_path, alert: t("flash.applications.cancel_too_late")
    end
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

  def update_details
    if @application.update(application_params)
      redirect_to application_path(@application)
    else
      # There was no else branch here at all, so a failed update rendered no
      # template and 500'd on the app's most-used write endpoint.
      redirect_to application_path(@application), alert: @application.errors.full_messages.to_sentence
    end
  end

  # The moved card, its new slot, and both column counts - see
  # applications/_status_change_streams for why it's surgical rather than a
  # column re-render. The board's own JS has already moved the card
  # optimistically; this is the authoritative reconciliation on top of it.
  def render_status_change(from_status)
    render turbo_stream: render_to_string(
      partial: "applications/status_change_streams",
      locals: { app: @application, from_status: from_status, to_status: @application.status },
      formats: [ :turbo_stream ]
    )
  end

  # A refused move has to come back as an error status, not a redirect: the
  # board's drag controller keys its rollback off turbo:submit-end's success
  # flag, and a 302 would read as "the move worked" and leave the card sitting
  # in a column the server never accepted.
  def render_board_alert(message)
    flash.now[:alert] = message
    render turbo_stream: turbo_stream.update("flash", partial: "shared/flash"),
      status: :unprocessable_entity
  end

  # Guards the two ways a manual board move can put the record out of step
  # with reality. Returns false having already rendered.
  def allow_status_move?(new_status)
    # An unknown value raises ArgumentError straight out of the enum setter
    # (a 500, not a validation failure), so it has to be caught before the
    # assignment rather than rescued after it.
    unless Application.statuses.key?(new_status)
      render_board_alert(t("flash.applications.unknown_status"))
      return false
    end

    # Entering or leaving "Sending soon" by hand - see
    # Application::MACHINE_OWNED_STATUS for why that lane is off limits.
    if new_status == Application::MACHINE_OWNED_STATUS
      render_board_alert(t("flash.applications.use_apply_to_send"))
      return false
    end

    if @application.queued?
      render_board_alert(t("flash.applications.cancel_send_first"))
      return false
    end

    true
  end

  # dry_run_emails on means every send lands in the user's own inbox
  # regardless of whether we know a real contact - safe to try even with no
  # recipient. Only refuse for real, once that safety net is off.
  def sendable?(application)
    Rails.application.config.dry_run_emails || application.intended_recipient.present?
  end
end
