require "test_helper"

class CompanyEmailSuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @company = companies(:one)
    sign_in @user
  end

  test "create saves a suggestion and redirects back" do
    assert_difference("CompanyEmailSuggestion.count", 1) do
      post company_email_suggestions_url(@company), params: { email: "hr@vertexsolutions.example" }, headers: { "HTTP_REFERER" => company_url(@company) }
    end

    suggestion = CompanyEmailSuggestion.last
    assert_equal @user, suggestion.user
    assert_equal @company, suggestion.company
    assert_redirected_to company_url(@company)
  end

  test "create falls back to the company page when there's no referer" do
    post company_email_suggestions_url(@company), params: { email: "hr@vertexsolutions.example" }

    assert_redirected_to company_url(@company)
  end

  test "create re-shows an error and does not save an invalid email" do
    assert_no_difference("CompanyEmailSuggestion.count") do
      post company_email_suggestions_url(@company), params: { email: "not an email" }
    end

    assert_redirected_to company_url(@company)
    follow_redirect!
    assert_match(/invalid/i, response.body)
  end

  test "create updates the user's own existing suggestion instead of duplicating it" do
    @company.email_suggestions.create!(user: @user, email: "wrong@vertexsolutions.example")

    assert_no_difference("CompanyEmailSuggestion.count") do
      post company_email_suggestions_url(@company), params: { email: "hr@vertexsolutions.example" }
    end

    assert_equal "hr@vertexsolutions.example", @company.email_suggestions.find_by(user: @user).email
  end

  test "a signed-out visitor cannot submit a suggestion" do
    sign_out @user

    assert_no_difference("CompanyEmailSuggestion.count") do
      post company_email_suggestions_url(@company), params: { email: "hr@vertexsolutions.example" }
    end

    assert_response :redirect
  end
end
