# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    applications = current_user.applications

    build_action_list(applications)

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

  # The dashboard used to only report what already happened (funnel, response
  # rate, recent activity) - this builds the short, prioritized "what to do
  # now" list above all of that. Every piece here is a filter over data that
  # already exists (Track L's indexes on jobs.expires_at/applications.status/
  # applications.queued_at are exactly what these queries lean on) - this is
  # composition, not new plumbing.
  def build_action_list(applications)
    @deadlines_to_apply = applications.wishlist.joins(:job).includes(job: :company)
      .where(jobs: { expires_at: Date.current..7.days.from_now })
      .order("jobs.expires_at asc")

    # needs_follow_up? stays a plain Ruby method (Application#needs_follow_up?)
    # rather than being duplicated as a second SQL scope - a user's own
    # "applied" list is small enough that filtering in Ruby is fine, and it
    # guarantees this list can never drift from what the CRM card itself
    # flags.
    @follow_ups_due = applications.applied.includes(job: :company)
      .select(&:needs_follow_up?)
      .sort_by { |app| app.last_followed_up_at || app.applied_at }

    @upcoming_interviews = applications.where(interview_date: Time.current..7.days.from_now.end_of_day)
      .includes(job: :company).order(:interview_date)

    # queued_at is always set alongside status by the controllers that queue a
    # send (dispatch_email/bulk_dispatch) - excluding a nil here is a defensive
    # guard against an application put into "queued" some other way (e.g.
    # directly in a test or a console), not a case the normal flow produces.
    @sends_in_flight = applications.queued.where.not(queued_at: nil).includes(job: :company).order(:queued_at)

    @new_matching_jobs = new_matching_jobs_since_last_visit(applications)

    @action_item_count = @deadlines_to_apply.size + @follow_ups_due.size +
      @upcoming_interviews.size + @sends_in_flight.size + @new_matching_jobs.size

    # Recorded last (after every query above reads the *previous* value) and
    # via update_column specifically - this is visit tracking, not a change
    # worth running full validation/callbacks for on every dashboard load.
    current_user.update_column(:last_dashboard_visit_at, Time.current)
  end

  # New jobs since the user's last visit that match their own radar
  # keywords - already-saved jobs are excluded, since flagging a job the
  # user has already acted on isn't "new" in any useful sense. Falls back to
  # a 7-day window on someone's very first visit (last_dashboard_visit_at is
  # nil) rather than surfacing the entire jobs table as "new".
  def new_matching_jobs_since_last_visit(applications)
    keywords = current_user.user_preference&.keyword_array
    return [] if keywords.blank?

    since = current_user.last_dashboard_visit_at || 7.days.ago
    saved_job_ids = applications.select(:job_id)

    Job.visible_to(current_user)
      .where(created_at: since..)
      .where.not(id: saved_job_ids)
      .select { |job| job.keyword_match_count(keywords).positive? }
      .sort_by(&:created_at)
      .reverse
      .first(10)
  end

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
