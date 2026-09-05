require "test_helper"

class CoverLetterTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
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

  def stub_ai_response(content)
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) do |*|
      { "choices" => [ { "message" => { "content" => content } } ] }
    end
    fake_client
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

  test "generate creates an AI template and redirects into its edit page" do
    blob_id = attach_resume
    fake_client = stub_ai_response("Dear {{company_name}},\n\nI'd love to join.")

    assert_difference("@user.cover_letter_templates.count", 1) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        post generate_cover_letter_templates_url, params: { resume_blob_id: blob_id, language: "bs" }
      end
    end

    template = @user.cover_letter_templates.order(:created_at).last
    assert template.ai_generated?
    assert_equal "bs", template.language
    assert_redirected_to edit_cover_letter_template_path(template)
  end

  test "generating twice back-to-back both succeed even with the same auto-generated name" do
    blob_id = attach_resume
    fake_client = stub_ai_response("Dear {{company_name}},\n\nI'd love to join.")

    # Reproduces the reported bug: two generations landing in the same
    # clock-second used to collide on CoverLetterTemplate's per-user unique
    # name and raise on the second one, surfacing as a generic
    # "couldn't generate" alert that looked like a cooldown.
    assert_difference("@user.cover_letter_templates.count", 2) do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        travel_to Time.zone.local(2026, 9, 5, 7, 48, 25) do
          post generate_cover_letter_templates_url, params: { resume_blob_id: blob_id, language: "en" }
          post generate_cover_letter_templates_url, params: { resume_blob_id: blob_id, language: "en" }
        end
      end
    end

    names = @user.cover_letter_templates.order(:created_at).last(2).map(&:name)
    assert_equal names.uniq.size, names.size, "both generated templates must have distinct names"
    assert_nil flash[:alert]
  end

  test "generate redirects back to new without generating when no resume is selected" do
    assert_no_difference("@user.cover_letter_templates.count") do
      post generate_cover_letter_templates_url, params: { resume_blob_id: "" }
    end

    assert_redirected_to new_cover_letter_template_path
    assert_not_nil flash[:alert]
  end

  test "generate rescues a service failure and redirects with an alert" do
    blob_id = attach_resume
    fake_client = stub_ai_response("")

    assert_no_difference("@user.cover_letter_templates.count") do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        post generate_cover_letter_templates_url, params: { resume_blob_id: blob_id, language: "en" }
      end
    end

    assert_redirected_to new_cover_letter_template_path
    assert_not_nil flash[:alert]
  end

  test "translate updates the template body and language in place" do
    template = @user.cover_letter_templates.create!(name: "AI Draft", body: "Dear {{company_name}}.", ai_generated: true, language: "en")
    fake_client = stub_ai_response("Poštovani {{company_name}}.")

    assert_no_difference("@user.cover_letter_templates.count") do
      stub_class_method(OpenAI::Client, :new, fake_client) do
        post translate_cover_letter_template_url(template), params: { language: "bs" }
      end
    end

    template.reload
    assert_equal "bs", template.language
    assert_includes template.body.to_plain_text, "Poštovani"
    assert_redirected_to edit_cover_letter_template_path(template)
  end

  test "translate rescues a service failure and redirects with an alert" do
    template = @user.cover_letter_templates.create!(name: "AI Draft", body: "Dear {{company_name}}.", ai_generated: true, language: "en")
    fake_client = stub_ai_response("")

    stub_class_method(OpenAI::Client, :new, fake_client) do
      post translate_cover_letter_template_url(template), params: { language: "bs" }
    end

    assert_redirected_to edit_cover_letter_template_path(template)
    assert_not_nil flash[:alert]
    assert_equal "en", template.reload.language
  end
end
