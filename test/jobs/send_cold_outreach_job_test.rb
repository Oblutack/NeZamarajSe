require "test_helper"

class SendColdOutreachJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @company = companies(:two)
    @company.update!(primary_email: "hr@coldcompany.example")
    @template = cover_letter_templates(:one)

    @user.resumes.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_resume.pdf")),
      filename: "resume.pdf",
      content_type: "application/pdf"
    )
    @blob_id = @user.resumes.first.blob_id
  end

  def fake_sender(gmail_id: "gmail-msg-123")
    fake_response = Object.new
    fake_response.define_singleton_method(:id) { gmail_id }

    sender = Object.new
    sender.define_singleton_method(:send_email) { |raw| @raw = raw; fake_response }
    sender.define_singleton_method(:raw_sent) { @raw }
    sender
  end

  test "records last_contacted_at and last_contacted_by only after Gmail confirms the send" do
    sender = fake_sender

    stub_class_method(GmailSenderService, :new, sender) do
      SendColdOutreachJob.perform_now(@user.id, @company.id, @template.id, @blob_id)
    end

    assert_not_nil sender.raw_sent
    @company.reload
    assert_not_nil @company.last_contacted_at
    assert_equal @user, @company.last_contacted_by
  end

  test "leaves last_contacted_at untouched if the Gmail send fails" do
    stub_class_method(GmailSenderService, :new, ->(*) { raise "Failed to refresh token" }) do
      assert_raises(RuntimeError) do
        SendColdOutreachJob.perform_now(@user.id, @company.id, @template.id, @blob_id)
      end
    end

    @company.reload
    assert_nil @company.last_contacted_at
  end
end
