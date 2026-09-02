require "test_helper"

class ApplicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @application = applications(:one)
    sign_in @user
  end

  def attach_resume
    @user.resumes.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_resume.pdf")),
      filename: "resume.pdf",
      content_type: "application/pdf"
    )
    @user.resumes.first.blob_id
  end

  def with_config(key, value)
    original = Rails.application.config.public_send(key)
    Rails.application.config.public_send("#{key}=", value)
    yield
  ensure
    Rails.application.config.public_send("#{key}=", original)
  end

  test "should get index" do
    get crm_url
    assert_response :success
  end

  test "index sorts each column by soonest deadline first, with no-deadline jobs last" do
    urgent_job = jobs(:two)
    urgent_job.update!(expires_at: 2.days.from_now)
    @application.job.update!(expires_at: nil)
    @user.applications.create!(job: urgent_job, status: "wishlist")

    get crm_url

    urgent_position = response.body.index(urgent_job.title)
    no_deadline_position = response.body.index(@application.job.title)
    assert_operator urgent_position, :<, no_deadline_position
  end

  test "should get create" do
    other_job = jobs(:two)
    assert_difference("Application.count") do
      post applications_url, params: { job_id: other_job.id }
    end
    assert_redirected_to jobs_path
  end

  test "should get update" do
    patch application_url(@application), params: { application: { status: "interviewing" } }
    assert_redirected_to crm_path
    assert_equal "interviewing", @application.reload.status
  end

  test "should get destroy" do
    assert_difference("Application.count", -1) do
      delete application_url(@application)
    end
    assert_redirected_to crm_path
  end

  test "dispatch_email queues the send instead of marking it applied immediately" do
    assert_enqueued_with(job: SendApplicationJob) do
      post dispatch_email_application_url(@application), params: {
        template_id: cover_letter_templates(:one).id,
        resume_blob_id: 1
      }
    end

    assert_redirected_to crm_path
    assert @application.reload.queued?
    assert_nil @application.applied_at
  end

  test "compose shows no preview until both a template and a resume are picked" do
    get compose_application_url(@application)

    assert_response :success
    assert_select "p", text: "Pick a template and a resume above to see a preview."
  end

  test "compose previews the resolved recipient, subject, and rendered body once both are picked" do
    @application.job.update!(hr_email: "hr@realcompany.example")
    template = cover_letter_templates(:one)
    blob_id = attach_resume

    get compose_application_url(@application), params: { template_id: template.id, resume_blob_id: blob_id }

    assert_response :success
    assert_select "dd", text: "hr@realcompany.example"
    assert_select "dd", text: JobApplicationMailer.subject_for(@application.job)
  end

  test "compose warns when the job has no known contact email" do
    @application.job.update!(hr_email: nil)
    @application.job.company.update!(primary_email: nil)
    template = cover_letter_templates(:one)
    blob_id = attach_resume

    get compose_application_url(@application), params: { template_id: template.id, resume_blob_id: blob_id }

    assert_select "dd", text: /No email found for this company yet/
  end

  test "dispatch_email refuses to enqueue when dry_run is off and there's no known recipient" do
    @application.job.update!(hr_email: nil)
    @application.job.company.update!(primary_email: nil)

    with_config(:dry_run_emails, false) do
      assert_no_enqueued_jobs(only: SendApplicationJob) do
        post dispatch_email_application_url(@application), params: {
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      assert_redirected_to compose_application_path(@application)
      assert_not @application.reload.queued?
    end
  end

  test "bulk_dispatch skips applications with no known recipient when dry_run is off, and sends the rest" do
    sendable_job = jobs(:two)
    sendable_job.update!(hr_email: "hr@realcompany.example")
    sendable_application = @user.applications.create!(job: sendable_job, status: "wishlist")

    @application.job.update!(hr_email: nil)
    @application.job.company.update!(primary_email: nil)

    with_config(:dry_run_emails, false) do
      assert_enqueued_jobs(1, only: SendApplicationJob) do
        post bulk_dispatch_applications_url, params: {
          application_ids: [ @application.id, sendable_application.id ],
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      assert_not @application.reload.queued?
      assert sendable_application.reload.queued?
    end
  end

  test "dispatch_email refuses entirely when the kill switch is off" do
    with_config(:sending_enabled, false) do
      assert_no_enqueued_jobs(only: SendApplicationJob) do
        post dispatch_email_application_url(@application), params: {
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      assert_redirected_to compose_application_path(@application)
      assert_not @application.reload.queued?
    end
  end

  test "bulk_dispatch refuses entirely when the kill switch is off" do
    with_config(:sending_enabled, false) do
      assert_no_enqueued_jobs(only: SendApplicationJob) do
        post bulk_dispatch_applications_url, params: {
          application_ids: [ @application.id ],
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      assert_not @application.reload.queued?
    end
  end

  test "dispatch_email refuses once the daily send cap is reached" do
    with_config(:daily_send_cap, 0) do
      assert_no_enqueued_jobs(only: SendApplicationJob) do
        post dispatch_email_application_url(@application), params: {
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      assert_redirected_to compose_application_path(@application)
      assert_not @application.reload.queued?
    end
  end

  test "bulk_dispatch only queues up to the remaining daily allowance" do
    second_application = @user.applications.create!(job: jobs(:two), status: "wishlist")

    with_config(:daily_send_cap, 1) do
      assert_enqueued_jobs(1, only: SendApplicationJob) do
        post bulk_dispatch_applications_url, params: {
          application_ids: [ @application.id, second_application.id ],
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      queued_count = [ @application, second_application ].count { |a| a.reload.queued? }
      assert_equal 1, queued_count
    end
  end

  test "dispatch_email sets queued_at, which counts toward the daily cap" do
    post dispatch_email_application_url(@application), params: {
      template_id: cover_letter_templates(:one).id,
      resume_blob_id: 1
    }

    assert_not_nil @application.reload.queued_at
  end

  test "should get show" do
    get application_url(@application)
    assert_response :success
    assert_select "h1", text: @application.job.title
  end

  test "updating status redirects to the CRM board" do
    patch application_url(@application), params: { application: { status: "interviewing" } }
    assert_redirected_to crm_path
  end

  test "updating CRM-depth fields redirects to the application's own detail page" do
    patch application_url(@application), params: { application: { contact_person: "Amila Hodžić", salary: "2500-3000 BAM" } }

    assert_redirected_to application_path(@application)
    @application.reload
    assert_equal "Amila Hodžić", @application.contact_person
    assert_equal "2500-3000 BAM", @application.salary
  end

  test "add_note creates a note event and redirects to the detail page" do
    assert_difference("@application.application_events.count", 1) do
      post add_note_application_url(@application), params: { body: "Called to check in, no answer." }
    end

    assert_redirected_to application_path(@application)
    assert_equal "note", @application.application_events.first.event_type
    assert_equal "Called to check in, no answer.", @application.application_events.first.body
  end

  test "add_note ignores a blank body" do
    assert_no_difference("@application.application_events.count") do
      post add_note_application_url(@application), params: { body: "   " }
    end
  end

  test "compose_follow_up previews the resolved recipient, subject, and rendered body once both are picked" do
    @application.job.update!(hr_email: "hr@realcompany.example")
    template = cover_letter_templates(:one)
    blob_id = attach_resume

    get compose_follow_up_application_url(@application), params: { template_id: template.id, resume_blob_id: blob_id }

    assert_response :success
    assert_select "dd", text: "hr@realcompany.example"
    assert_select "dd", text: JobApplicationMailer.follow_up_subject_for(@application.job)
  end

  test "dispatch_follow_up queues SendFollowUpJob without changing status" do
    @application.update!(status: "applied", applied_at: 10.days.ago)

    assert_enqueued_with(job: SendFollowUpJob) do
      post dispatch_follow_up_application_url(@application), params: {
        template_id: cover_letter_templates(:one).id,
        resume_blob_id: 1
      }
    end

    assert_redirected_to application_path(@application)
    assert @application.reload.applied?
  end

  test "dispatch_follow_up refuses once the daily send cap is reached" do
    @application.update!(status: "applied", applied_at: 10.days.ago)

    with_config(:daily_send_cap, 0) do
      assert_no_enqueued_jobs(only: SendFollowUpJob) do
        post dispatch_follow_up_application_url(@application), params: {
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      assert_redirected_to compose_follow_up_application_path(@application)
    end
  end
end
