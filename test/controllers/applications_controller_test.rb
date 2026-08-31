require "test_helper"

class ApplicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @application = applications(:one)
    sign_in @user
  end

  test "should get index" do
    get crm_url
    assert_response :success
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
end
