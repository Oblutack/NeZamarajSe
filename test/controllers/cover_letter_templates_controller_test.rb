require "test_helper"

class CoverLetterTemplatesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get cover_letter_templates_index_url
    assert_response :success
  end

  test "should get new" do
    get cover_letter_templates_new_url
    assert_response :success
  end

  test "should get edit" do
    get cover_letter_templates_edit_url
    assert_response :success
  end
end
