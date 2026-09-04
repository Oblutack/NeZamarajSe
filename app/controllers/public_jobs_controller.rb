# app/controllers/public_jobs_controller.rb
#
# The app's first unauthenticated, non-Devise surface - GET /j/:token, no
# authenticate_user! before_action. Deliberately renders a narrow
# projection (see the view), not jobs#show minus the auth check: a
# manually-added job's hr_email is frequently a personal contact the user
# typed in, and sharing a posting must never expose it, nor who added it.
class PublicJobsController < ApplicationController
  def show
    @job = Job.includes(:company).find_by!(share_token: params[:token])

    # "Unlisted" should mean unlisted - keep this out of search results even
    # though it's a real, reachable page.
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
