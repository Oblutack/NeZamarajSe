require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "should get show" do
    get dashboard_url
    assert_response :success
  end

  test "shows this month's Hunter.io lookup count against the quota" do
    HunterLookup.create!(company: companies(:one))
    HunterLookup.create!(company: companies(:two))

    get dashboard_url

    assert_match(/Hunter\.io: 2 \/ 25 this month/, response.body)
  end

  test "Hunter.io lookups from a previous month don't count toward this month's total" do
    HunterLookup.create!(company: companies(:one), created_at: 2.months.ago)

    get dashboard_url

    assert_match(/Hunter\.io: 0 \/ 25 this month/, response.body)
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

    assert_select "span", text: /Warm/
    assert_select "span", text: /Cold/
  end

  test "funnel counts an application that later got rejected as having reached interviewing" do
    job = Job.create!(company: companies(:one), title: "Funnel Role", url: "https://jobs.example.com/funnel-role")
    application = users(:one).applications.create!(job: job, status: "applied", applied_at: Time.current)
    application.update!(status: "interviewing")
    application.update!(status: "rejected")

    get dashboard_url

    assert_select "span:contains('Interviewing') + span", text: "1"
  end

  test "response rate counts a rejection as a response, not silence" do
    job = Job.create!(company: companies(:one), title: "Response Role", url: "https://jobs.example.com/response-role")
    application = users(:one).applications.create!(job: job, status: "applied", applied_at: Time.current)
    application.update!(status: "rejected")

    get dashboard_url

    assert_select "p", text: "100%"
  end

  test "response rate shows a dash with no applications sent yet" do
    get dashboard_url

    assert_select "p", text: "—"
  end

  test "deadlines this week lists a job expiring within 7 days and excludes one further out" do
    soon_job = Job.create!(company: companies(:one), title: "Soon Deadline", url: "https://jobs.example.com/soon-deadline", expires_at: 3.days.from_now)
    far_job = Job.create!(company: companies(:one), title: "Far Deadline", url: "https://jobs.example.com/far-deadline", expires_at: 60.days.from_now)
    users(:one).applications.create!(job: soon_job, status: "wishlist")
    users(:one).applications.create!(job: far_job, status: "wishlist")

    get dashboard_url

    assert_match soon_job.title, response.body
    assert_no_match(/#{Regexp.escape(far_job.title)}/, response.body)
  end

  test "recent activity feed shows a status change event" do
    application = applications(:one)
    application.update!(status: "queued")

    get dashboard_url

    assert_match(/Moved from Wishlist to Sending soon/, response.body)
  end

  test "onboarding checklist appears when template, resume, and keywords are all missing" do
    user = users(:one)
    user.cover_letter_templates.destroy_all
    user.user_preference.update!(keywords: "")

    get dashboard_url

    assert_match "Finish setting up", response.body
    assert_select "a", text: "Create a cover letter template"
  end

  test "onboarding checklist is hidden once template, resume, and keywords are all present" do
    user = users(:one)
    user.resumes.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_resume.pdf")),
      filename: "resume.pdf",
      content_type: "application/pdf"
    )
    user.user_preference.update!(keywords: "Ruby")

    get dashboard_url

    assert_no_match "Finish setting up", response.body
  end
end
