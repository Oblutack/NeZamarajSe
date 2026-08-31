require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "should get index" do
    get jobs_url
    assert_response :success
  end

  test "falls back to the radar's saved keywords when q is blank" do
    matching_job = Job.create!(company: companies(:one), title: "Senior Developer", url: "https://jobs.example.com/senior-developer")

    get jobs_url

    assert_select "p", text: /Showing jobs matching:/
    assert_match matching_job.title, response.body
  end

  test "q searches by job title and overrides the saved keywords" do
    get jobs_url, params: { q: "Backend" }

    assert_match jobs(:one).title, response.body
    assert_no_match(/#{Regexp.escape(jobs(:two).title)}/, response.body)
  end

  test "q searches by company name" do
    get jobs_url, params: { q: "Northbridge" }

    assert_match jobs(:two).title, response.body
  end

  test "shows a dedicated empty state when the search has no matches" do
    get jobs_url, params: { q: "no-such-job-anywhere" }

    assert_select "h3", text: /No jobs match/
    assert_select "a", text: "Clear search"
  end
end
