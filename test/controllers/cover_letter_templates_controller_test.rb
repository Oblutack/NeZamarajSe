require "test_helper"

class CoverLetterTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "should get index" do
    get cover_letter_templates_url
    assert_response :success
  end

  test "index shows 'not sent yet' for a template with no sends" do
    get cover_letter_templates_url
    assert_match(/Not sent yet/, response.body)
  end

  test "index shows the reply rate once a template has been sent" do
    user = users(:one)
    template = cover_letter_templates(:one)
    job = Job.create!(company: companies(:one), title: "Sent Role", url: "https://jobs.example.com/sent-role")
    application = user.applications.create!(job: job, status: "applied", applied_at: Time.current, cover_letter_template: template)
    application.application_events.create!(event_type: "reply_detected")

    get cover_letter_templates_url

    assert_match(/1 sent.*1 replies.*100%/, response.body)
  end

  test "should get new" do
    get new_cover_letter_template_url
    assert_response :success
  end

  test "should get edit" do
    get edit_cover_letter_template_url(cover_letter_templates(:one))
    assert_response :success
  end
end
