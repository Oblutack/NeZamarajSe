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
  end
end
