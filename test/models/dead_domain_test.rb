require "test_helper"

class DeadDomainTest < ActiveSupport::TestCase
  test "dead? is false for a host with no record at all" do
    assert_not DeadDomain.dead?("never-seen.example")
  end

  test "dead? is false below the failure threshold" do
    DeadDomain.create!(host: "flaky.example", failure_count: DeadDomain::THRESHOLD - 1, last_failed_at: Time.current)
    assert_not DeadDomain.dead?("flaky.example")
  end

  test "dead? is true at the failure threshold within the cooldown window" do
    DeadDomain.create!(host: "down.example", failure_count: DeadDomain::THRESHOLD, last_failed_at: Time.current)
    assert DeadDomain.dead?("down.example")
  end

  test "dead? is false again once the cooldown window has passed, even with enough failures" do
    DeadDomain.create!(host: "maybe-recovered.example", failure_count: DeadDomain::THRESHOLD, last_failed_at: (DeadDomain::COOLDOWN + 1.day).ago)
    assert_not DeadDomain.dead?("maybe-recovered.example")
  end

  test "record_failure! creates a row on the first failure and increments on repeats" do
    DeadDomain.record_failure!("new-failure.example")
    assert_equal 1, DeadDomain.find_by(host: "new-failure.example").failure_count

    DeadDomain.record_failure!("new-failure.example")
    assert_equal 2, DeadDomain.find_by(host: "new-failure.example").failure_count
  end

  test "record_success! resets an existing failure count to zero" do
    DeadDomain.create!(host: "recovering.example", failure_count: 5, last_failed_at: Time.current)
    DeadDomain.record_success!("recovering.example")
    assert_equal 0, DeadDomain.find_by(host: "recovering.example").failure_count
  end

  test "record_success! is a no-op when the host has no record" do
    assert_nothing_raised { DeadDomain.record_success!("unknown.example") }
    assert_nil DeadDomain.find_by(host: "unknown.example")
  end
end
