require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "read? is false until read_at is set" do
    notification = Notification.create!(user: users(:one), job: jobs(:one))
    assert_not notification.read?

    notification.update!(read_at: Time.current)
    assert notification.read?
  end

  test "unread scope only returns notifications with no read_at" do
    read = Notification.create!(user: users(:one), job: jobs(:one), read_at: Time.current)
    unread = Notification.create!(user: users(:one), job: jobs(:two))

    assert_includes users(:one).notifications.unread, unread
    assert_not_includes users(:one).notifications.unread, read
  end

  test "orders newest first" do
    older = Notification.create!(user: users(:one), job: jobs(:one), created_at: 1.day.ago)
    newer = Notification.create!(user: users(:one), job: jobs(:two), created_at: 1.hour.ago)

    assert_equal [ newer, older ], users(:one).notifications.to_a
  end
end
