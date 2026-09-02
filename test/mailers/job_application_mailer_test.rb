require "test_helper"

class JobApplicationMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
    @job = jobs(:one)
    @job.update!(hr_email: "hr@realcompany.example")
    @template = cover_letter_templates(:one)
    @user.resumes.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_resume.pdf")),
      filename: "resume.pdf",
      content_type: "application/pdf"
    )
    @resume = @user.resumes.first
  end

  def with_dry_run(value)
    original = Rails.application.config.dry_run_emails
    Rails.application.config.dry_run_emails = value
    yield
  ensure
    Rails.application.config.dry_run_emails = original
  end

  test "while dry_run_emails is on, sends to the user's own inbox with a tagged subject" do
    with_dry_run(true) do
      mail = JobApplicationMailer.apply(@user, @job, @template, @resume)

      assert_equal [ @user.email ], mail.to
      assert_equal "[DRY RUN] Application: #{@job.title}", mail.subject
    end
  end

  test "with dry_run_emails off, sends to the job's real hr_email" do
    with_dry_run(false) do
      mail = JobApplicationMailer.apply(@user, @job, @template, @resume)

      assert_equal [ "hr@realcompany.example" ], mail.to
      assert_equal "Application: #{@job.title}", mail.subject
    end
  end

  test "with dry_run_emails off and no known recipient, refuses to send" do
    @job.update!(hr_email: nil)
    @job.company.update!(primary_email: nil)

    with_dry_run(false) do
      assert_raises(JobApplicationMailer::NoRecipientError) do
        # ActionMailer::MessageDelivery is lazy - .apply(...) alone doesn't
        # run the mailer method body. Force it, same as SendApplicationJob's
        # mail.message.to_s does for a real send.
        JobApplicationMailer.apply(@user, @job, @template, @resume).message
      end
    end
  end

  test "with dry_run_emails on and no known recipient, still sends (to the user's own inbox)" do
    @job.update!(hr_email: nil)
    @job.company.update!(primary_email: nil)

    with_dry_run(true) do
      mail = JobApplicationMailer.apply(@user, @job, @template, @resume)
      assert_equal [ @user.email ], mail.to
    end
  end
end
