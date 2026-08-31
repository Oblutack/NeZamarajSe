require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "creates default radar preferences after signup" do
    user = User.create!(email: "new-user@example.com", password: "password123")

    preference = user.user_preference
    assert_not_nil preference
    assert_equal "Developer, Software, IT", preference.keywords
    assert preference.receive_daily_alerts
  end

  test "rejects a resume that is not a PDF" do
    user = users(:one)
    user.resumes.attach(
      io: StringIO.new("not a pdf"),
      filename: "resume.txt",
      content_type: "text/plain"
    )

    assert_not user.valid?
    assert_includes user.errors[:resumes], "must be a valid PDF format"
  end

  test "from_omniauth creates a new user from a Google auth payload" do
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "brand-new-uid",
      info: { email: "fresh@example.com" },
      credentials: { token: "access-token", refresh_token: "refresh-token", expires_at: 1.hour.from_now.to_i }
    )

    user = User.from_omniauth(auth)

    assert user.persisted?
    assert_equal "fresh@example.com", user.email
    assert_equal "access-token", user.access_token
    assert_equal "refresh-token", user.refresh_token
  end

  test "from_omniauth keeps the existing refresh token when Google doesn't resend one" do
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "returning-uid",
      info: { email: "returning@example.com" },
      credentials: { token: "first-token", refresh_token: "first-refresh-token", expires_at: 1.hour.from_now.to_i }
    )
    existing_user = User.from_omniauth(auth)

    silent_reauth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "returning-uid",
      info: { email: "returning@example.com" },
      credentials: { token: "second-token", refresh_token: nil, expires_at: 2.hours.from_now.to_i }
    )
    returning_user = User.from_omniauth(silent_reauth)

    assert_equal existing_user.id, returning_user.id
    assert_equal "second-token", returning_user.access_token
    assert_equal "first-refresh-token", returning_user.refresh_token
  end
end
