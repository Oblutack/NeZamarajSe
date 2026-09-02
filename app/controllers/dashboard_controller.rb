# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    @jobs_saved_count = current_user.applications.count
    @applications_sent_this_month_count = current_user.applications.where(applied_at: Time.current.all_month).count

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
  end
end
