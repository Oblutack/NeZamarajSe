# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def mark_read
    notification = current_user.notifications.find(params[:id])
    notification.update!(read_at: Time.current) unless notification.read?
    redirect_to job_path(notification.job)
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_back fallback_location: root_path
  end
end
