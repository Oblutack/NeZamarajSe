require "test_helper"

class ResumesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get resumes_index_url
    assert_response :success
  end
end
