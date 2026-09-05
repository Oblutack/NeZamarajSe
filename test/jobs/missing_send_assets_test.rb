require "test_helper"

# A resume or template deleted between enqueue and run is a permanent
# failure. The send jobs must stop cleanly instead of raising - re-raising
# would burn every Sidekiq retry on something that can never succeed and
# strand the application in "queued" forever.
class MissingSendAssetsTest < ActiveSupport::TestCase
  setup do
    @application = applications(:one)
    @user = @application.user
    @template = cover_letter_templates(:one)
    @application.update!(status: "queued", queued_at: Time.current)
  end

  test "a deleted resume aborts the send and hands the card back to wishlist" do
    assert_nothing_raised do
      SendApplicationJob.new.perform(@application.id, @template.id, 999_999)
    end

    @application.reload
    assert_equal "wishlist", @application.status, "the card should return to wishlist, not sit in queued"
    assert_nil @application.queued_at, "queued_at must be cleared so the daily allowance is handed back"
    assert_nil @application.applied_at, "nothing was sent, so it must not look applied"
  end

  test "a deleted template aborts the send the same way" do
    assert_nothing_raised do
      SendApplicationJob.new.perform(@application.id, 999_999, 999_999)
    end

    @application.reload
    assert_equal "wishlist", @application.status
    assert_nil @application.queued_at
  end

  test "another user's template is treated as missing, not used" do
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    foreign = other.cover_letter_templates.create!(name: "Theirs", body: "Hello {{company_name}}")

    assert_nothing_raised do
      SendApplicationJob.new.perform(@application.id, foreign.id, 999_999)
    end

    @application.reload
    assert_equal "wishlist", @application.status
    assert_nil @application.applied_at, "a foreign template must never result in a send"
  end

  test "follow-up aborts cleanly without touching the application" do
    @application.update!(status: "applied", applied_at: 10.days.ago, last_followed_up_at: nil)

    assert_nothing_raised do
      SendFollowUpJob.new.perform(@application.id, @template.id, 999_999)
    end

    @application.reload
    assert_equal "applied", @application.status
    assert_nil @application.last_followed_up_at, "the follow-up clock must not reset when nothing was sent"
  end

  test "cold outreach aborts cleanly without marking the company contacted" do
    company = companies(:one)
    company.update!(last_contacted_at: nil, last_contacted_by: nil)

    assert_nothing_raised do
      SendColdOutreachJob.new.perform(@user.id, company.id, @template.id, 999_999)
    end

    assert_nil company.reload.last_contacted_at, "the company must not look contacted when nothing was sent"
  end

  test "a cancelled application is still skipped before any asset lookup" do
    @application.update!(status: "wishlist", queued_at: nil)

    assert_nothing_raised do
      SendApplicationJob.new.perform(@application.id, @template.id, 999_999)
    end

    assert_equal "wishlist", @application.reload.status
  end
end
