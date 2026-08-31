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

    stub_gmail_sender(fake_sender) do
      SendApplicationJob.perform_now(@application.id, @template.id, @blob_id)
    end

    assert_equal 1, sent_messages.size
    @application.reload
    assert @application.applied?
    assert_not_nil @application.applied_at
  end

  test "leaves the application queued if the Gmail send fails" do
    stub_gmail_sender(->(*) { raise "Failed to refresh token" }) do
      assert_raises(RuntimeError) do
        SendApplicationJob.perform_now(@application.id, @template.id, @blob_id)
      end
    end

    @application.reload
    assert @application.queued?
    assert_nil @application.applied_at
  end

  private

  # Minitest's Mock/#stub live in the "minitest-mock" gem, which isn't part of
  # this app's bundle (Minitest 6 split it out) - so we stub GmailSenderService.new
  # by hand instead of pulling in a new dependency for two tests.
  def stub_gmail_sender(replacement)
    GmailSenderService.singleton_class.send(:alias_method, :__real_new, :new)
    GmailSenderService.define_singleton_method(:new) do |*args|
      replacement.respond_to?(:call) ? replacement.call(*args) : replacement
    end
    yield
  ensure
    GmailSenderService.singleton_class.send(:remove_method, :new)
    GmailSenderService.singleton_class.send(:alias_method, :new, :__real_new)
    GmailSenderService.singleton_class.send(:remove_method, :__real_new)
  end
end
