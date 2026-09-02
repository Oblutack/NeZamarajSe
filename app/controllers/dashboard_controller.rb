# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    applications = current_user.applications

    @jobs_saved_count = applications.count
    @applications_sent_this_month_count = applications.where(applied_at: Time.current.all_month).count

    @warm_company_count = Company.where(is_cold_outreach: false).count
    @cold_company_count = Company.where(is_cold_outreach: true).count
    total = @warm_company_count + @cold_company_count
    @warm_company_percent = total.zero? ? 0 : (@warm_company_count * 100.0 / total).round
    @cold_company_percent = 100 - @warm_company_percent

    # The ratio bar above says how the pipeline is split; these say what to
    # actually go do about it - the three cold-outreach states that matter.
    cold = Company.where(is_cold_outreach: true)
    @cold_needs_email_count = cold.where(primary_email: [ nil, "" ]).count
    @cold_ready_to_contact_count = cold.where.not(primary_email: [ nil, "" ]).where(last_contacted_at: nil).count
    @cold_contacted_count = cold.where.not(last_contacted_at: nil).count

    @hunter_lookups_this_month = HunterLookup.where(created_at: Time.current.all_month).count
    @hunter_monthly_quota = Rails.application.config.hunter_monthly_quota

    build_funnel(applications)
    build_response_rate(applications)

    @deadlines_this_week = Job.joins(:applications)
      .where(applications: { user_id: current_user.id })
      .where(expires_at: Date.current..7.days.from_now)
      .order(:expires_at)
      .distinct

    @recent_events = ApplicationEvent.joins(:application)
      .where(applications: { user_id: current_user.id })
      .includes(application: { job: :company })
      .limit(8)

    @onboarding = {
      template: current_user.cover_letter_templates.exists?,
      resume: current_user.resumes.attached?,
      keywords: current_user.user_preference&.keywords&.present? || false
    }
    @onboarding_complete = @onboarding.values.all?
  end

  private

  # "Reached interviewing" (or further) is read from the application_events
  # log (Track D) rather than current status, so an application that later
  # got rejected still counts toward having made it that far - current
  # status alone would undercount it once it moves past "interviewing".
  def build_funnel(applications)
    # .reorder(nil) drops ApplicationEvent's default_scope order (newest
    # first) - Postgres requires DISTINCT's ORDER BY columns to appear in
    # the SELECT list, which a bare .pluck(:application_id) doesn't satisfy.
    reached_interviewing_ids = ApplicationEvent.where(event_type: "status_change", to_status: %w[interviewing offered])
      .where(application_id: applications.select(:id)).reorder(nil).distinct.pluck(:application_id)
    reached_offered_ids = ApplicationEvent.where(event_type: "status_change", to_status: "offered")
      .where(application_id: applications.select(:id)).reorder(nil).distinct.pluck(:application_id)

    @funnel = {
      saved: applications.count,
      applied: applications.where.not(applied_at: nil).count,
      interviewing: reached_interviewing_ids.count,
      offered: reached_offered_ids.count
    }
  end

  # A rejection still counts as a response (someone read it and replied),
  # not just an interview invite - only genuine silence should look like
  # "no response."
  def build_response_rate(applications)
    sent = applications.where.not(applied_at: nil)
    @applications_sent_count = sent.count
    responded_count = sent.where(status: %w[interviewing offered rejected]).count
    @response_rate_percent = @applications_sent_count.zero? ? nil : (responded_count * 100.0 / @applications_sent_count).round
  end
end
