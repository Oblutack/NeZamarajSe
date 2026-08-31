require "application_system_test_case"

class CrmFlowTest < ApplicationSystemTestCase
  test "saving a job from the Job Market puts it on the CRM wishlist" do
    user = users(:one)
    # user one's radar keywords include "Developer" - give them a matching job
    # to find on Job Market, since the fixture jobs (Backend/Frontend Engineer)
    # don't match those keywords.
    job = Job.create!(company: companies(:one), title: "Senior Ruby Developer", url: "https://jobs.example.com/senior-ruby-developer")

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "authenticated"

    visit jobs_path
    assert_text job.title

    click_button "Save to Wishlist"
    assert_current_path jobs_path
    assert_text "added to your CRM Wishlist"

    visit crm_path
    within "div[data-status='wishlist']" do
      assert_text job.title
      assert_text job.company.name
    end
  end
end
