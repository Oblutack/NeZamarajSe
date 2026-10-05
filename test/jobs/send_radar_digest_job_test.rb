require "test_helper"

# One user's digest, sent through their own Gmail. Assertions are on the message
# a recipient would actually receive (parsed back out of the raw MIME handed to
# Gmail), not on how the job builds it.
class SendRadarDigestJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.update!(access_token: "access-token", refresh_token: "refresh-token", token_expires_at: 1.hour.from_now)
    @company = companies(:one)
    @job = Job.create!(company: @company, title: "Senior Software Architect", url: "https://jobs.example.com/radar-digest")
  end

  def fake_sender(failure: nil)
    sender = Object.new
    sender.define_singleton_method(:send_email) do |raw|
      raise failure if failure

      (@sent ||= []) << raw
      Object.new
    end
    sender.define_singleton_method(:sent) { @sent || [] }
    sender
  end

  def deliver(sender, user_id = @user.id, job_ids = [ @job.id ])
    stub_class_method(GmailSenderService, :new, sender) do
      SendRadarDigestJob.perform_now(user_id, job_ids)
    end
  end

  def parsed(sender)
    Mail.new(sender.sent.first)
  end

  test "sends the digest through the user's own Gmail" do
    sender = fake_sender
    built_for = nil

    stub_class_method(GmailSenderService, :new, ->(user) { built_for = user; sender }) do
      SendRadarDigestJob.perform_now(@user.id, [ @job.id ])
    end

    assert_equal @user, built_for, "the sender must be built from this user's own OAuth token"
    assert_equal 1, sender.sent.size
  end

  test "the message is addressed to the user, from the user, and says what it found" do
    sender = fake_sender
    deliver(sender)
    mail = parsed(sender)

    assert_equal [ @user.email ], mail.to
    assert_equal [ @user.email ], mail.from
    assert_equal "🎯 NeZamarajSe: 1 new job matches your radar!", mail.subject
    assert_includes mail.body.decoded, "Senior Software Architect"
    assert_includes mail.body.decoded, @company.name
  end

  test "each job links to its own page, never localhost" do
    sender = fake_sender
    deliver(sender)
    body = parsed(sender).body.decoded

    assert_includes body, "/jobs/#{@job.id}"
    assert_no_match(/localhost/, body)
  end

  test "a private job is left out even if its id is passed in" do
    private_job = Job.create!(
      company: @company, title: "Confidential Software Role",
      url: "https://jobs.example.com/radar-digest-private", added_by: users(:two)
    )
    sender = fake_sender

    deliver(sender, @user.id, [ @job.id, private_job.id ])
    body = parsed(sender).body.decoded

    assert_includes body, "Senior Software Architect"
    assert_no_match(/Confidential Software Role/, body)
    assert_match(/1 new job matches/, parsed(sender).subject)
  end

  test "nothing is sent when none of the ids is a shared job" do
    private_job = Job.create!(
      company: @company, title: "Confidential Software Role",
      url: "https://jobs.example.com/radar-digest-private-2", added_by: users(:two)
    )
    sender = fake_sender

    deliver(sender, @user.id, [ private_job.id, 0 ])

    assert_empty sender.sent
  end

  test "a user who isn't connected to Google is skipped without touching Gmail" do
    @user.update!(refresh_token: nil)

    stub_class_method(GmailSenderService, :new, ->(_user) { flunk "must not build a Gmail sender for an unconnected user" }) do
      assert_nothing_raised { SendRadarDigestJob.perform_now(@user.id, [ @job.id ]) }
    end
  end

  test "a user who has since been deleted is skipped quietly" do
    stub_class_method(GmailSenderService, :new, ->(_user) { flunk "must not send for a missing user" }) do
      assert_nothing_raised { SendRadarDigestJob.perform_now(0, [ @job.id ]) }
    end
  end

  test "a Gmail failure is reported with context and retried shortly" do
    notified = []
    sender = fake_sender(failure: RuntimeError.new("Failed to refresh token"))

    stub_class_method(Honeybadger, :notify, ->(*args) { notified << args }) do
      assert_enqueued_jobs 1, only: SendRadarDigestJob do
        deliver(sender)
      end
    end

    # Only this job's own report: under the :test adapter Honeybadger's ActiveJob
    # plugin also fires (it's switched off for the Sidekiq adapter, which has its
    # own), so filter on the context this job attaches. In production each failed
    # attempt produces exactly this one report - and it has to come from here,
    # because retry_on handles the failure inside ActiveJob and the final one is
    # swallowed, so Sidekiq's reporter never sees any of them.
    reports = notified.select { |args| args.last.is_a?(Hash) && args.last.dig(:context, :user_id) }

    assert_equal 1, reports.size
    assert_equal "Failed to refresh token", reports.first.first.message
    assert_equal({ user_id: @user.id, job_ids: [ @job.id ] }, reports.first.last[:context])
  end

  test "after three attempts it gives up instead of retrying for weeks" do
    sender = fake_sender(failure: RuntimeError.new("token revoked"))
    attempt = SendRadarDigestJob.new(@user.id, [ @job.id ])
    # retry_on counts per exception key in exception_executions - not in
    # job.executions - and the key is the array of exception classes it was given.
    attempt.exception_executions = { "[StandardError]" => 2 } # this run is the third

    stub_class_method(Honeybadger, :notify, ->(*) { }) do
      stub_class_method(GmailSenderService, :new, sender) do
        assert_nothing_raised { attempt.perform_now }
      end
    end

    assert_no_enqueued_jobs(only: SendRadarDigestJob)
  end
end
