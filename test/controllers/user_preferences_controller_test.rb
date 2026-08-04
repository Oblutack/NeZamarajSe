require "test_helper"

class UserPreferencesControllerTest < ActionDispatch::IntegrationTest
  test "should get edit" do
    get user_preferences_edit_url
    assert_response :success
  end

  test "should get update" do
    get user_preferences_update_url
    assert_response :success
  end
end
