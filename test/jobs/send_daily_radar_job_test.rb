require "test_helper"

# The scheduled fan-out: decides which opted-in users get a digest and which new
# jobs go in it, then queues one SendRadarDigestJob per user. It sends nothing.
#
# Two things used to be wrong here and are pinned down below: the query had no
# visibility rule (one user's private hand-typed job was in everyone's digest),
# and the digest passed an ActiveRecord::Relation to deliver_later, which raised
# before any mail existed - so it had never been able to send a single message.
class SendDailyRadarJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one) # keywords "Developer, Software, IT", receive_daily_alerts: true
    connect_gmail(@user)
    @company = companies(:one)
  end

  def connect_gmail(user)
    user.update!(access_token: "access-token", refresh_token: "refresh-token", token_expires_at: 1.hour.from_now)
  end

  def with_config(key, value)
    original = Rails.application.config.public_send(key)
    Rails.application.config.public_send("#{key}=", value)
    yield
  ensure
    Rails.application.config.public_send("#{key}=", original)
  end

  def create_job(title, **attrs)
    Job.create!(company: @company, title: title, url: "https://jobs.example.com/#{SecureRandom.hex(6)}", **attrs)
  end

  test "a shared posting that matches the user's keywords is handed to a per-user digest job" do
    job = create_job("Senior Software Architect")

    assert_enqueued_with(job: SendRadarDigestJob, args: [ @user.id, [ job.id ] ], queue: "mailers") do
      SendDailyRadarJob.perform_now
    end
  end

  test "it queues one digest per user instead of sending anything itself" do
    create_job("Senior Software Architect")

    assert_enqueued_jobs 1, only: SendRadarDigestJob do
      SendDailyRadarJob.perform_now
    end
    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob)
  end

  test "newest matches come first" do
    older = create_job("Older Software Role", created_at: 5.hours.ago)
    newer = create_job("Newer Software Role", created_at: 1.hour.ago)

    assert_enqueued_with(job: SendRadarDigestJob, args: [ @user.id, [ newer.id, older.id ] ]) do
      SendDailyRadarJob.perform_now
    end
  end

  test "another user's private job never reaches a digest, even when its title matches" do
    shared = create_job("Senior Software Architect")
    create_job("Confidential Software Role", added_by: users(:two))

    # Exact args: the private job's id must be absent, not merely outnumbered.
    assert_enqueued_with(job: SendRadarDigestJob, args: [ @user.id, [ shared.id ] ]) do
      SendDailyRadarJob.perform_now
    end
    assert_enqueued_jobs 1, only: SendRadarDigestJob
  end

  test "no digest at all when the only match is someone else's private job" do
    create_job("Confidential Software Role", added_by: users(:two))

    assert_no_enqueued_jobs(only: SendRadarDigestJob) { SendDailyRadarJob.perform_now }
  end

  test "a user's own private job isn't echoed back to them - the digest is for new postings" do
    create_job("My Own Software Lead", added_by: @user)

    assert_no_enqueued_jobs(only: SendRadarDigestJob) { SendDailyRadarJob.perform_now }
  end

  test "jobs older than 24 hours are left out" do
    create_job("Stale Software Role", created_at: 2.days.ago)

    assert_no_enqueued_jobs(only: SendRadarDigestJob) { SendDailyRadarJob.perform_now }
  end

  test "a user who opted out gets nothing, and opting in is the only difference" do
    other = users(:two) # keywords "Ruby, Rails", receive_daily_alerts: false
    connect_gmail(other)
    create_job("Senior Rails Engineer")

    assert_no_enqueued_jobs(only: SendRadarDigestJob) { SendDailyRadarJob.perform_now }

    # Control: flipping only the opt-in produces a digest, so the line above
    # really was about the opt-out and not about the job failing to match.
    other.user_preference.update!(receive_daily_alerts: true)
    assert_enqueued_jobs 1, only: SendRadarDigestJob do
      SendDailyRadarJob.perform_now
    end
  end

  test "a user who hasn't connected Google is skipped, since the digest leaves through their Gmail" do
    @user.update!(refresh_token: nil)
    create_job("Senior Software Architect")

    assert_no_enqueued_jobs(only: SendRadarDigestJob) { SendDailyRadarJob.perform_now }
  end

  test "the global kill switch stops the digest too" do
    create_job("Senior Software Architect")

    with_config(:sending_enabled, false) do
      assert_no_enqueued_jobs(only: SendRadarDigestJob) { SendDailyRadarJob.perform_now }
    end
  end
end
