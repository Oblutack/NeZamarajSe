require "test_helper"

class SendApplicationJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @application = applications(:one)
    @application.update!(status: "queued")
    @application.job.update!(hr_email: "hr@realcompany.example")
    @template = cover_letter_templates(:one)

    @user.resumes.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_resume.pdf")),
      filename: "resume.pdf",
      content_type: "application/pdf"
    )
    @blob_id = @user.resumes.first.blob_id
  end

  def fake_sender(gmail_id: "gmail-msg-123", thread_id: "gmail-thread-123")
    fake_response = Object.new
    fake_response.define_singleton_method(:id) { gmail_id }
    fake_response.define_singleton_method(:thread_id) { thread_id }

    sender = Object.new
    sender.define_singleton_method(:send_email) { |raw| @raw = raw; fake_response }
    sender.define_singleton_method(:raw_sent) { @raw }
    sender
  end

  test "marks the application applied only after Gmail confirms the send" do
    sender = fake_sender

    stub_class_method(GmailSenderService, :new, sender) do
      SendApplicationJob.perform_now(@application.id, @template.id, @blob_id)
    end

    assert_not_nil sender.raw_sent
    @application.reload
    assert @application.applied?
    assert_not_nil @application.applied_at
  end

  test "records the intended recipient, subject, body, and Gmail message/thread id" do
    sender = fake_sender(gmail_id: "gmail-msg-456", thread_id: "gmail-thread-456")

    stub_class_method(GmailSenderService, :new, sender) do
      SendApplicationJob.perform_now(@application.id, @template.id, @blob_id)
    end

    @application.reload
    assert_equal "hr@realcompany.example", @application.sent_recipient
    assert_includes @application.sent_subject, @application.job.title
    assert_equal @template.render_content(@application.job), @application.sent_body
    assert_equal "gmail-msg-456", @application.gmail_message_id
    assert_equal "gmail-thread-456", @application.gmail_thread_id
  end

  test "leaves the application queued if the Gmail send fails" do
    stub_class_method(GmailSenderService, :new, ->(*) { raise "Failed to refresh token" }) do
      assert_raises(RuntimeError) do
        SendApplicationJob.perform_now(@application.id, @template.id, @blob_id)
      end
    end

    @application.reload
    assert @application.queued?
    assert_nil @application.applied_at
    assert_nil @application.gmail_message_id
  end
end
