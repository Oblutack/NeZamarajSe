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
