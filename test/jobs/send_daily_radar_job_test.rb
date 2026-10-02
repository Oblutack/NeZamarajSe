require "test_helper"

# Asserts on the mail a recipient would actually read, not on how the job
# arrives at it - the digest used to pass an ActiveRecord::Relation straight to
# deliver_later (unserialisable, so it raised before any mail existed), and used
# to select jobs with no visibility rule at all (so one user's private entry was
# emailed to everyone whose keywords happened to match).
class SendDailyRadarJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one) # keywords "Developer, Software, IT", receive_daily_alerts: true
    @company = companies(:one)
    ActionMailer::Base.deliveries.clear
  end

  # The text of a mail, whether it's single-part or multipart.
  def text_of(mail)
    (mail.parts.presence || [ mail ]).map { |part| part.body.decoded }.join("\n")
  end

  def digests_sent
    perform_enqueued_jobs { SendDailyRadarJob.perform_now }
    ActionMailer::Base.deliveries
  end

  test "a shared posting that matches the user's keywords is in their digest" do
    Job.create!(company: @company, title: "Senior Software Architect", url: "https://jobs.example.com/radar-public")

    mails = digests_sent

    assert_equal 1, mails.size
    assert_equal [ @user.email ], mails.first.to
    assert_includes text_of(mails.first), "Senior Software Architect"
  end

  test "the digest is really enqueued as a mail delivery" do
    Job.create!(company: @company, title: "Senior Software Architect", url: "https://jobs.example.com/radar-real")

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      SendDailyRadarJob.perform_now
    end
  end

  test "another user's private job never appears in a digest, even when its title matches" do
    Job.create!(
      company: @company, title: "Confidential Software Role",
      url: "https://jobs.example.com/radar-private", added_by: users(:two)
    )
    Job.create!(company: @company, title: "Senior Software Architect", url: "https://jobs.example.com/radar-shared")

    mails = digests_sent

    assert_equal 1, mails.size, "the shared posting still produces a digest"
    assert_no_match(/Confidential Software Role/, text_of(mails.first),
      "a job one user typed in by hand must not be emailed to everyone whose keywords happen to match")
  end

  test "no digest at all when the only match is someone else's private job" do
    Job.create!(
      company: @company, title: "Confidential Software Role",
      url: "https://jobs.example.com/radar-private-only", added_by: users(:two)
    )

    assert_empty digests_sent
  end

  test "a user's own private job isn't echoed back to them - the digest is for new postings" do
    Job.create!(
      company: @company, title: "My Own Software Lead",
      url: "https://jobs.example.com/radar-own", added_by: @user
    )

    assert_empty digests_sent
  end
end
