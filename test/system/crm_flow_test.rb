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
    assert_text "added to your wishlist"

    visit crm_path
    within "div[data-status='wishlist']" do
      assert_text job.title
      assert_text job.company.name
    end
  end

  test "moving a card via the 'Move to' menu works without dragging" do
    user = users(:one)
    application = applications(:one) # fixture: status wishlist, job: jobs(:one)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "authenticated"

    visit crm_path
    within "div[data-status='wishlist']" do
      assert_text application.job.title
      find("button[aria-label='Move to…']").click
      click_button "Interviewing"
    end

    assert_current_path crm_path
    within "div[data-status='interviewing']" do
      assert_text application.job.title
    end
    assert_equal "interviewing", application.reload.status
  end

  test "a card's 'Move to' menu stacks above the next card, not behind it" do
    user = users(:one)
    application = applications(:one) # fixture: status wishlist, job: jobs(:one)
    other_job = Job.create!(company: companies(:one), title: "Second Wishlist Job", url: "https://jobs.example.com/second-wishlist-job")
    user.applications.create!(job: other_job, status: "wishlist")

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "authenticated"

    visit crm_path
    within "div[data-status='wishlist']" do
      # Open the *first* card's menu - its "Applied" option would render
      # right over the top of the second card below it if the dropdown's
      # host card isn't lifted above its sibling (see dropdown_controller.js
      # #open/#close). A real Selenium click on an occluded element raises
      # instead of silently going through, so this fails loudly if the fix
      # regresses rather than passing by accident.
      within "#application_#{application.id}" do
        find("button[aria-label='Move to…']").click
        find("button[data-status='applied']").click
      end
    end

    within "div[data-status='applied']" do
      assert_text application.job.title
    end
    assert_equal "applied", application.reload.status
  end
end
