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
end
