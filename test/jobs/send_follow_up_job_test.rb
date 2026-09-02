require "test_helper"

class SendFollowUpJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @application = applications(:one)
    @application.update!(status: "applied", applied_at: 10.days.ago)
    @application.job.update!(hr_email: "hr@realcompany.example")
    @template = cover_letter_templates(:one)

    @user.resumes.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_resume.pdf")),
      filename: "resume.pdf",
      content_type: "application/pdf"
    )
    @blob_id = @user.resumes.first.blob_id
  end

  def fake_sender
    fake_response = Object.new
    fake_response.define_singleton_method(:id) { "gmail-msg-789" }
    fake_response.define_singleton_method(:thread_id) { "gmail-thread-789" }

    sender = Object.new
    sender.define_singleton_method(:send_email) { |raw| @raw = raw; fake_response }
    sender.define_singleton_method(:raw_sent) { @raw }
    sender
  end

  test "sets last_followed_up_at and logs a follow_up_sent event, without touching status" do
    sender = fake_sender

    stub_class_method(GmailSenderService, :new, sender) do
      SendFollowUpJob.perform_now(@application.id, @template.id, @blob_id)
    end

    assert_not_nil sender.raw_sent
    @application.reload
    assert @application.applied?
    assert_not_nil @application.last_followed_up_at
    assert_equal "follow_up_sent", @application.application_events.first.event_type
  end

  test "leaves last_followed_up_at untouched if the Gmail send fails" do
    stub_class_method(GmailSenderService, :new, ->(*) { raise "Failed to refresh token" }) do
      assert_raises(RuntimeError) do
        SendFollowUpJob.perform_now(@application.id, @template.id, @blob_id)
      end
    end

    @application.reload
    assert_nil @application.last_followed_up_at
  end
end
