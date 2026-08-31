require "test_helper"

class GmailSenderServiceTest < ActiveSupport::TestCase
  def fake_gmail_client(sent_messages)
    client = Object.new
    client.define_singleton_method(:authorization=) { |_| }
    client.define_singleton_method(:send_user_message) do |user_id, message|
      sent_messages << { user_id: user_id, raw: message.raw }
    end
    client
  end

  test "sends the raw message through the Gmail API without refreshing a still-valid token" do
    user = users(:one)
    user.update!(access_token: "valid-token", token_expires_at: 1.hour.from_now)
    sent_messages = []

    refresh_called = false
    stub_class_method(Net::HTTP, :post_form, ->(*) { refresh_called = true }) do
      stub_class_method(Google::Apis::GmailV1::GmailService, :new, fake_gmail_client(sent_messages)) do
        GmailSenderService.new(user).send_email("raw-mime-string")
      end
    end

    assert_not refresh_called
    assert_equal [ { user_id: "me", raw: "raw-mime-string" } ], sent_messages
  end

  test "refreshes an expired token before sending" do
    user = users(:one)
    user.update!(access_token: "stale-token", refresh_token: "a-refresh-token", token_expires_at: 1.minute.ago)
    sent_messages = []

    refresh_response = Struct.new(:body).new({ access_token: "brand-new-token", expires_in: 3600 }.to_json)
    stub_class_method(Net::HTTP, :post_form, ->(*) { refresh_response }) do
      stub_class_method(Google::Apis::GmailV1::GmailService, :new, fake_gmail_client(sent_messages)) do
        GmailSenderService.new(user).send_email("raw-mime-string")
      end
    end

    assert_equal "brand-new-token", user.reload.access_token
    assert_equal 1, sent_messages.size
  end

  test "raises when Google refuses to refresh the token" do
    user = users(:one)
    user.update!(access_token: "stale-token", refresh_token: "a-bad-refresh-token", token_expires_at: 1.minute.ago)

    refresh_response = Struct.new(:body).new({ error: "invalid_grant" }.to_json)
    stub_class_method(Net::HTTP, :post_form, ->(*) { refresh_response }) do
      assert_raises(RuntimeError) { GmailSenderService.new(user) }
    end
  end
end
