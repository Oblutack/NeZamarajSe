require "test_helper"

class SendApplicationJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @application = applications(:one)
    @application.update!(status: "queued")
    @template = cover_letter_templates(:one)

    @user.resumes.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_resume.pdf")),
      filename: "resume.pdf",
      content_type: "application/pdf"
    )
    @blob_id = @user.resumes.first.blob_id
  end

  test "marks the application applied only after Gmail confirms the send" do
    sent_messages = []
    fake_sender = Object.new
    fake_sender.define_singleton_method(:send_email) { |raw| sent_messages << raw }

    stub_class_method(GmailSenderService, :new, fake_sender) do
      SendApplicationJob.perform_now(@application.id, @template.id, @blob_id)
    end

    assert_equal 1, sent_messages.size
    @application.reload
    assert @application.applied?
    assert_not_nil @application.applied_at
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
  end
end
