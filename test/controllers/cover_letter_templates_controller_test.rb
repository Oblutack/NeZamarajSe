require "test_helper"

class CoverLetterTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "should get index" do
    get cover_letter_templates_url
    assert_response :success
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
