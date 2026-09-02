require "test_helper"

class ApplicationEventTest < ActiveSupport::TestCase
  test "requires a body when event_type is note" do
    event = ApplicationEvent.new(application: applications(:one), event_type: "note")
    assert_not event.valid?
    assert_includes event.errors[:body], "can't be blank"
  end

  test "does not require a body for a status_change event" do
    event = ApplicationEvent.new(
      application: applications(:one), event_type: "status_change", from_status: "wishlist", to_status: "queued"
    )
    assert event.valid?
  end

  test "rejects an unrecognized event_type" do
    event = ApplicationEvent.new(application: applications(:one), event_type: "bogus")
    assert_not event.valid?
    assert_includes event.errors[:event_type], "is not included in the list"
  end

  test "orders newest first" do
    application = applications(:one)
    older = application.application_events.create!(event_type: "note", body: "first", created_at: 2.days.ago)
    newer = application.application_events.create!(event_type: "note", body: "second", created_at: 1.day.ago)

    assert_equal [ newer, older ], application.application_events.to_a
  end
end
