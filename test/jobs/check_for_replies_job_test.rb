require "test_helper"

class CheckForRepliesJobTest < ActiveJob::TestCase
  setup do
    @application = applications(:one)
    @application.update!(status: "applied", applied_at: 5.days.ago, gmail_thread_id: "thread-abc")
  end

  def fake_sender(has_reply:)
    sender = Object.new
    sender.define_singleton_method(:thread_has_reply?) { |_thread_id| has_reply }
    sender
  end

  test "advances applied -> interviewing and logs a reply_detected event when a reply is found" do
    stub_class_method(GmailSenderService, :new, fake_sender(has_reply: true)) do
      CheckForRepliesJob.perform_now
    end

    @application.reload
    assert @application.interviewing?
    assert_equal "reply_detected", @application.application_events.first.event_type
  end

  test "leaves the application untouched when no reply is found" do
    assert_no_difference -> { @application.application_events.count } do
      stub_class_method(GmailSenderService, :new, fake_sender(has_reply: false)) do
        CheckForRepliesJob.perform_now
      end
    end

    assert @application.reload.applied?
  end

  test "skips applications with no gmail_thread_id" do
    @application.update!(gmail_thread_id: nil)

    stub_class_method(GmailSenderService, :new, fake_sender(has_reply: true)) do
      CheckForRepliesJob.perform_now
    end

    @application.reload
    assert @application.applied?
  end

  test "one application's failure doesn't stop the rest of the batch from being checked" do
    other_application = applications(:two)
    other_application.update!(status: "applied", applied_at: 5.days.ago, gmail_thread_id: "thread-def")

    call_count = 0
    sender_factory = lambda do |user|
      call_count += 1
      raise "token refresh failed" if user == @application.user

      fake_sender(has_reply: true)
    end

    stub_class_method(GmailSenderService, :new, sender_factory) do
      CheckForRepliesJob.perform_now
    end

    assert_equal 2, call_count
    other_application.reload
    assert other_application.interviewing?
  end
end
