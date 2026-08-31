require "test_helper"

class UserPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "should get edit" do
    get edit_user_preference_url
    assert_response :success
  end

  test "should update" do
    patch user_preference_url, params: { user_preference: { keywords: "Ruby, Rails" } }
    assert_redirected_to edit_user_preference_path
    assert_equal "Ruby, Rails", users(:one).user_preference.reload.keywords
  end
end
