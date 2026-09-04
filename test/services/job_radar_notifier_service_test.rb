require "test_helper"

class JobRadarNotifierServiceTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "creates a notification for the given user and job" do
    assert_difference("users(:one).notifications.count", 1) do
      JobRadarNotifierService.call(job: jobs(:one), user: users(:one))
    end

    notification = users(:one).notifications.last
    assert_equal jobs(:one), notification.job
    assert_not notification.read?
  end

  test "broadcasts a prepend and a badge update to the user's notifications stream" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, [ users(:one), :notifications ])

    assert_broadcasts(stream, 2) do
      JobRadarNotifierService.call(job: jobs(:one), user: users(:one))
    end
  end
end
