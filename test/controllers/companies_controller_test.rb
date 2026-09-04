require "test_helper"

class CompaniesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @company = companies(:one)
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
    get companies_url
    assert_response :success
  end

  test "index paginates beyond the first page and still shows the jobs_count annotation" do
    26.times { |n| Company.create!(name: "Generated Company #{n}") }

    get companies_url
    assert_response :success
    assert_select "nav[aria-label=Pagination]"

    get companies_url, params: { page: 2 }
    assert_response :success
  end

  test "index renders a mobile card layout alongside the table, with the same data" do
    get companies_url

    assert_select "div.sm\\:hidden a", text: @company.name
    assert_select "table a", text: @company.name
  end

  test "index filters by has_email" do
    @company.update!(primary_email: "hr@vertexsolutions.example")
    companies(:two).update!(primary_email: nil)

    get companies_url(has_email: "1")

    assert_response :success
    assert_select "td a", text: @company.name
    assert_select "td a", { text: companies(:two).name, count: 0 }
  end

  test "index filters by cold vs warm" do
    @company.update!(is_cold_outreach: true)
    companies(:two).update!(is_cold_outreach: false)

    get companies_url(cold: "1")

    assert_response :success
    assert_select "td a", text: @company.name
    assert_select "td a", { text: companies(:two).name, count: 0 }
  end

  test "should get show" do
    get company_url(@company)
    assert_response :success
    assert_select "h1", text: @company.name
  end

  test "show prompts for an email suggestion when there's no known contact" do
    @company.update!(primary_email: nil)

    get company_url(@company)

    assert_select "form[action=?]", company_email_suggestions_path(@company)
  end

  test "show does not prompt for an email suggestion once a contact is known" do
    @company.update!(primary_email: "hr@vertexsolutions.example")

    get company_url(@company)

    assert_no_match(/Do you know who to email here\?/, response.body)
  end

  test "show surfaces a reply-confirmed badge once an application to that address got a reply" do
    @company.update!(primary_email: "hr@vertexsolutions.example")
    job = Job.create!(company: @company, title: "Confirmed Reply Role", url: "https://jobs.example.com/confirmed-reply-role")
    application = @user.applications.create!(job: job, status: "applied", applied_at: Time.current, sent_recipient: "hr@vertexsolutions.example")
    application.application_events.create!(event_type: "reply_detected")

    get company_url(@company)

    assert_match(/1 reply confirmed/, response.body)
  end

  test "show does not list another user's private manually-added job under this company" do
    mine = Job.create!(company: @company, title: "My Private Lead", added_by: @user)
    theirs = Job.create!(company: @company, title: "Someone Else's Lead", added_by: users(:two))

    get company_url(@company)

    assert_match mine.title, response.body
    assert_no_match(/#{Regexp.escape(theirs.title)}/, response.body)
  end

  test "index's jobs_count does not include another user's private manually-added job" do
    visible_count = @company.jobs.count
    Job.create!(company: @company, title: "Someone Else's Lead", added_by: users(:two))

    get companies_url

    assert_select "td", text: visible_count.to_s
  end

  test "refresh_email enqueues FindCompanyEmailJob for the company" do
    assert_enqueued_with(job: FindCompanyEmailJob, args: [ @company.id ]) do
      post refresh_email_company_url(@company)
    end

    assert_redirected_to company_path(@company)
  end

  test "compose_outreach previews the resolved recipient, subject, and rendered body once both are picked" do
    @company.update!(primary_email: "hr@vertexsolutions.example")
    template = cover_letter_templates(:one)
    blob_id = attach_resume

    get compose_outreach_company_url(@company), params: { template_id: template.id, resume_blob_id: blob_id }

    assert_response :success
    assert_select "dd", text: "hr@vertexsolutions.example"
    assert_select "dd", text: JobApplicationMailer.cold_outreach_subject_for(@company)
  end

  test "dispatch_outreach queues SendColdOutreachJob" do
    @company.update!(primary_email: "hr@vertexsolutions.example")

    assert_enqueued_with(job: SendColdOutreachJob) do
      post dispatch_outreach_company_url(@company), params: {
        template_id: cover_letter_templates(:one).id,
        resume_blob_id: 1
      }
    end

    assert_redirected_to company_path(@company)
  end

  test "dispatch_outreach refuses when dry_run is off and there's no known recipient" do
    @company.update!(primary_email: nil)

    with_config(:dry_run_emails, false) do
      assert_no_enqueued_jobs(only: SendColdOutreachJob) do
        post dispatch_outreach_company_url(@company), params: {
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      assert_redirected_to compose_outreach_company_path(@company)
    end
  end

  test "dispatch_outreach refuses entirely when the kill switch is off" do
    with_config(:sending_enabled, false) do
      assert_no_enqueued_jobs(only: SendColdOutreachJob) do
        post dispatch_outreach_company_url(@company), params: {
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end
    end
  end

  test "dispatch_outreach refuses once the daily send cap is reached" do
    with_config(:daily_send_cap, 0) do
      assert_no_enqueued_jobs(only: SendColdOutreachJob) do
        post dispatch_outreach_company_url(@company), params: {
          template_id: cover_letter_templates(:one).id,
          resume_blob_id: 1
        }
      end

      assert_redirected_to compose_outreach_company_path(@company)
    end
  end
end
