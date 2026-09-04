require "test_helper"

class CompanyEmailSuggestionTest < ActiveSupport::TestCase
  test "requires something that looks like an email" do
    suggestion = CompanyEmailSuggestion.new(company: companies(:one), user: users(:one), email: "not an email")
    assert_not suggestion.valid?
    assert_includes suggestion.errors[:email], "is invalid"
  end

  test "accepts a free-mail address - deliberately not restricted to a company domain" do
    suggestion = CompanyEmailSuggestion.new(company: companies(:one), user: users(:one), email: "hr.vertex@gmail.com")
    assert suggestion.valid?
  end

  test "one suggestion per user per company" do
    CompanyEmailSuggestion.create!(company: companies(:one), user: users(:one), email: "hr@vertexsolutions.example")
    duplicate = CompanyEmailSuggestion.new(company: companies(:one), user: users(:one), email: "other@vertexsolutions.example")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "the same user can suggest for two different companies" do
    CompanyEmailSuggestion.create!(company: companies(:one), user: users(:one), email: "hr@vertexsolutions.example")
    second = CompanyEmailSuggestion.new(company: companies(:two), user: users(:one), email: "hr@northbridgesystems.example")

    assert second.valid?
  end

  test "promotes a single uncontested suggestion straight to the company's primary_email" do
    company = companies(:one)
    assert_nil company.primary_email

    CompanyEmailSuggestion.create!(company: company, user: users(:one), email: "hr@vertexsolutions.example")

    assert_equal "hr@vertexsolutions.example", company.reload.primary_email
  end

  test "does not promote once a second, different email is suggested - no longer uncontested" do
    company = companies(:one)
    CompanyEmailSuggestion.create!(company: company, user: users(:one), email: "hr@vertexsolutions.example")
    assert_equal "hr@vertexsolutions.example", company.reload.primary_email

    # A conflicting second guess shouldn't have been possible to promote in
    # the first place - simulate it by clearing primary_email back to blank
    # and confirming two *disagreeing* suggestions never auto-promote either.
    company.update!(primary_email: nil)
    CompanyEmailSuggestion.create!(company: company, user: users(:two), email: "office@vertexsolutions.example")

    assert_nil company.reload.primary_email
  end

  test "never overwrites an email a scraper or Hunter already found" do
    company = companies(:one)
    company.update!(primary_email: "hr@realcompany.example")

    CompanyEmailSuggestion.create!(company: company, user: users(:one), email: "someone-else@example.com")

    assert_equal "hr@realcompany.example", company.reload.primary_email
  end

  test "updating an existing suggestion re-evaluates promotion rather than creating a second row" do
    company = companies(:one)
    suggestion = CompanyEmailSuggestion.create!(company: company, user: users(:one), email: "wrong@vertexsolutions.example")
    assert_equal "wrong@vertexsolutions.example", company.reload.primary_email

    company.update!(primary_email: nil)
    assert_no_difference("CompanyEmailSuggestion.count") do
      suggestion.update!(email: "hr@vertexsolutions.example")
    end

    assert_equal "hr@vertexsolutions.example", company.reload.primary_email
  end
end
