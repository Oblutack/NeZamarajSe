require "test_helper"

class ResumesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    sign_in users(:one)
    get resumes_url
    assert_response :success
  end
end
