require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "should get show" do
    get dashboard_url
    assert_response :success
  end

  test "counts the current user's saved jobs and this month's sent applications" do
    other_job = Job.create!(company: companies(:one), title: "Another Role", url: "https://jobs.example.com/another-role")
    users(:one).applications.create!(job: other_job, status: "applied", applied_at: Time.current)

    get dashboard_url

    assert_select "p:contains('Jobs Saved') + p", text: "2"
    assert_select "p:contains('Applications Sent This Month') + p", text: "1"
  end

  test "shows the cold vs warm outreach split" do
    Company.create!(name: "Cold Target Co", is_cold_outreach: true)

    get dashboard_url

    assert_select "span", text: /Warm — posted a job/
    assert_select "span", text: /Cold — directory only/
  end
end
