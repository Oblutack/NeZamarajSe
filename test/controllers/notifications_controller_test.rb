require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "mark_read marks the notification read and redirects to the job" do
    notification = @user.notifications.create!(job: jobs(:one))

    patch mark_read_notification_url(notification)

    assert notification.reload.read?
    assert_redirected_to job_path(jobs(:one))
  end

  test "mark_read is scoped to the current user's own notifications" do
    other_notification = users(:two).notifications.create!(job: jobs(:one))

    patch mark_read_notification_url(other_notification)

    assert_response :not_found
    assert_not other_notification.reload.read?
  end

  test "mark_all_read marks every unread notification for the current user" do
    @user.notifications.create!(job: jobs(:one))
    @user.notifications.create!(job: jobs(:two))
    other_unread = users(:two).notifications.create!(job: jobs(:one))

    patch mark_all_read_notifications_url

    assert @user.notifications.unread.none?
    assert_not other_unread.reload.read?
  end
end
