require "test_helper"

# Moving a card by hand on the Kanban board has to leave the record in the
# same shape a real send would - otherwise the dashboard, the funnel and the
# follow-up reminder all quietly disagree with what the board shows.
class ApplicationStatusMoveTest < ActiveSupport::TestCase
  setup do
    @application = applications(:one) # wishlist, applied_at nil
  end

  test "moving to applied by hand stamps applied_at" do
    assert_nil @application.applied_at

    @application.update!(status: "applied")

    assert_not_nil @application.reload.applied_at,
      "a manually applied card must record when it was applied, or it's invisible to the dashboard"
  end

  test "a manually applied card still gets a follow-up reminder" do
    @application.update!(status: "applied")
    @application.update_column(:applied_at, 10.days.ago)

    assert @application.reload.needs_follow_up?,
      "the whole point of tracking an application applied elsewhere is being nudged to follow up"
  end

  test "skipping straight to interviewing still stamps applied_at so the funnel stays monotonic" do
    @application.update!(status: "interviewing")

    assert_not_nil @application.reload.applied_at,
      "you cannot be interviewing without having applied - the funnel would show more interviews than applications"
  end

  test "rejected and offered also count as submitted" do
    %w[rejected offered].each do |status|
      application = users(:one).applications.create!(
        job: Job.create!(company: companies(:one), title: "Role #{status}", url: "https://ex.test/#{status}-#{SecureRandom.hex(4)}"),
        status: status
      )
      assert_not_nil application.applied_at, "#{status} implies an application was submitted"
    end
  end

  test "moving back to wishlist clears applied_at when nothing was ever sent" do
    @application.update!(status: "applied")
    assert_not_nil @application.applied_at

    @application.update!(status: "wishlist")

    assert_nil @application.reload.applied_at,
      "a mis-drag undone must not leave a phantom in the funnel"
  end

  test "moving back to wishlist keeps applied_at when a real send happened" do
    @application.update!(status: "applied", sent_recipient: "hr@example.com", sent_subject: "Application")
    sent_at = @application.applied_at
    assert_not_nil sent_at

    @application.update!(status: "wishlist")

    assert_equal sent_at, @application.reload.applied_at,
      "a real send's history must survive being moved around the board"
  end

  test "queueing does not stamp applied_at - nothing has been submitted yet" do
    @application.update!(status: "queued", queued_at: Time.current)

    assert_nil @application.reload.applied_at
  end

  test "an explicit applied_at is never overwritten" do
    original = 3.days.ago.change(usec: 0)

    @application.update!(status: "applied", applied_at: original)

    assert_equal original, @application.reload.applied_at
  end

  test "manually_movable_statuses never offers the machine-owned lane" do
    assert_not_includes @application.manually_movable_statuses, "queued"
    assert_not_includes @application.manually_movable_statuses, @application.status
    assert_includes @application.manually_movable_statuses, "applied"
  end

  test "manually_movable_statuses is empty while a send is in flight" do
    @application.update!(status: "queued", queued_at: Time.current)

    assert_empty @application.manually_movable_statuses,
      "a sending card's only exit is Cancel send"
  end
end
