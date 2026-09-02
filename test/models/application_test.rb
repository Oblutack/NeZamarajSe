require "test_helper"

class ApplicationTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "a user cannot save the same job twice" do
    duplicate = Application.new(user: users(:one), job: jobs(:one), status: "wishlist")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already saved this job"
  end

  test "different users can each save the same job" do
    application = Application.new(user: users(:two), job: jobs(:one), status: "wishlist")
    assert application.valid?
  end

  test "exposes the CRM lane enum in kanban column order" do
    assert_equal %w[wishlist queued applied interviewing rejected offered], Application.statuses.keys
  end

  test "broadcasts a card replace to the owner's CRM stream when status changes" do
    application = applications(:one)
    # `stream_name_from` (private) is what ActionCable.server.broadcast actually
    # publishes to - the public `broadcasting_for` helper builds a differently
    # prefixed name meant for generic ActionCable channels, not Turbo Streams.
    stream = Turbo::StreamsChannel.send(:stream_name_from, [ application.user, :crm ])

    assert_broadcasts(stream, 1) do
      application.update!(status: "queued")
    end
  end

  test "does not broadcast when status is unchanged" do
    application = applications(:one)
    stream = Turbo::StreamsChannel.send(:stream_name_from, [ application.user, :crm ])

    assert_no_broadcasts(stream) do
      application.update!(applied_at: Time.current)
    end
  end

  test "records a status_change event with the from/to status whenever status changes" do
    application = applications(:one)
    application.update!(status: "queued")

    event = application.application_events.first
    assert_equal "status_change", event.event_type
    assert_equal "wishlist", event.from_status
    assert_equal "queued", event.to_status
  end

  test "does not record an event when a non-status field changes" do
    application = applications(:one)

    assert_no_difference -> { application.application_events.count } do
      application.update!(contact_person: "Amila")
    end
  end

  def with_follow_up_after_days(value)
    original = Rails.application.config.follow_up_after_days
    Rails.application.config.follow_up_after_days = value
    yield
  ensure
    Rails.application.config.follow_up_after_days = original
  end

  test "needs_follow_up? is false for anything other than applied" do
    application = applications(:one)
    application.update!(status: "wishlist")
    assert_not application.needs_follow_up?
  end

  test "needs_follow_up? is true once applied_at is older than the threshold with no follow-up sent" do
    application = applications(:one)
    application.update!(status: "applied", applied_at: 10.days.ago)

    with_follow_up_after_days(7) do
      assert application.needs_follow_up?
    end
  end

  test "needs_follow_up? resets the clock after a follow-up was already sent" do
    application = applications(:one)
    application.update!(status: "applied", applied_at: 10.days.ago, last_followed_up_at: 1.day.ago)

    with_follow_up_after_days(7) do
      assert_not application.needs_follow_up?
    end
  end
end
