require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    sign_in users(:one)
    get jobs_url
    assert_response :success
  end
end
