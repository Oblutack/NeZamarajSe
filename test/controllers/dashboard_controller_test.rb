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

  test "today's action list shows an unapplied wishlist job with a deadline inside 7 days" do
    users(:one).user_preference.update!(keywords: "")
    soon_job = Job.create!(company: companies(:one), title: "Wishlist Soon Deadline", url: "https://jobs.example.com/wishlist-soon", expires_at: 3.days.from_now)
    already_applied_job = Job.create!(company: companies(:one), title: "Already Applied Soon Deadline", url: "https://jobs.example.com/applied-soon", expires_at: 3.days.from_now)
    users(:one).applications.create!(job: soon_job, status: "wishlist")
    users(:one).applications.create!(job: already_applied_job, status: "applied", applied_at: Time.current)

    get dashboard_url

    assert_select "p:contains('Apply before these close') + ul" do |uls|
      list_text = uls.map(&:text).join
      assert_match soon_job.title, list_text
      assert_no_match(/#{Regexp.escape(already_applied_job.title)}/, list_text)
    end
  end

  test "today's action list shows an application whose follow-up is due" do
    users(:one).user_preference.update!(keywords: "")
    job = Job.create!(company: companies(:one), title: "Overdue Follow-up Role", url: "https://jobs.example.com/overdue-follow-up")
    users(:one).applications.create!(job: job, status: "applied", applied_at: 10.days.ago)

    get dashboard_url

    assert_select "p:contains('Follow-ups due')"
    assert_match job.title, response.body
    assert_select "a", text: "Send follow-up"
  end

  test "today's action list excludes an application that isn't due for a follow-up yet" do
    users(:one).user_preference.update!(keywords: "")
    job = Job.create!(company: companies(:one), title: "Fresh Application Role", url: "https://jobs.example.com/fresh-application")
    users(:one).applications.create!(job: job, status: "applied", applied_at: 1.day.ago)

    get dashboard_url

    assert_no_match(/#{Regexp.escape(job.title)}/, response.body)
  end

  test "today's action list shows an interview inside 7 days and excludes one further out" do
    users(:one).user_preference.update!(keywords: "")
    soon_job = Job.create!(company: companies(:one), title: "Soon Interview Role", url: "https://jobs.example.com/soon-interview")
    far_job = Job.create!(company: companies(:one), title: "Far Interview Role", url: "https://jobs.example.com/far-interview")
    users(:one).applications.create!(job: soon_job, status: "interviewing", interview_date: 2.days.from_now)
    users(:one).applications.create!(job: far_job, status: "interviewing", interview_date: 30.days.from_now)

    get dashboard_url

    assert_select "p:contains('Interviews coming up')"
    assert_match soon_job.title, response.body
    assert_no_match(/#{Regexp.escape(far_job.title)}/, response.body)
    assert_select "a", text: "Add to calendar"
  end

  test "today's action list shows a queued send with a cancel link" do
    users(:one).user_preference.update!(keywords: "")
    job = Job.create!(company: companies(:one), title: "Queued Send Role", url: "https://jobs.example.com/queued-send")
    users(:one).applications.create!(job: job, status: "queued", queued_at: Time.current)

    get dashboard_url

    assert_select "p:contains('Sending now')"
    assert_match job.title, response.body
    assert_select "a", text: "Cancel"
  end

  test "today's action list shows a new job matching the user's radar keywords" do
    users(:one).user_preference.update!(keywords: "Zephyrsoft")
    matching_job = Job.create!(company: companies(:one), title: "Zephyrsoft Engineer", url: "https://jobs.example.com/zephyrsoft-engineer")

    get dashboard_url

    assert_select "p:contains('New jobs matching your radar')"
    assert_match matching_job.title, response.body
  end

  test "today's action list excludes an already-saved job from new matching jobs" do
    users(:one).user_preference.update!(keywords: "Zephyrsoft")
    matching_job = Job.create!(company: companies(:one), title: "Zephyrsoft Engineer Already Saved", url: "https://jobs.example.com/zephyrsoft-saved")
    users(:one).applications.create!(job: matching_job, status: "wishlist")

    get dashboard_url

    # Scoped to <main>, not the whole response body: the navbar's
    # notification bell (outside <main>) legitimately surfaces this same
    # job's title too, since it *does* match the user's radar keyword - that
    # bell is a separate, correct signal from the dashboard's own
    # already-saved-exclusion this test is actually checking.
    main_html = Nokogiri::HTML(response.body).at_css("main").to_s
    assert_no_match(/#{Regexp.escape(matching_job.title)}/, main_html)
  end

  test "records the visit time so a job created before the first visit isn't 'new' on the next visit" do
    users(:one).user_preference.update!(keywords: "Zephyrsoft")
    assert_nil users(:one).last_dashboard_visit_at

    get dashboard_url
    assert users(:one).reload.last_dashboard_visit_at.present?

    old_job = Job.create!(company: companies(:one), title: "Zephyrsoft Pre-existing Role", url: "https://jobs.example.com/zephyrsoft-preexisting")
    old_job.update_column(:created_at, 10.days.ago)

    get dashboard_url

    # See the note above - scoped to <main> since the notification bell
    # (outside it) still correctly lists this job as a keyword match.
    main_html = Nokogiri::HTML(response.body).at_css("main").to_s
    assert_no_match(/#{Regexp.escape(old_job.title)}/, main_html)
  end

  test "shows a friendly empty state when nothing needs attention today" do
    users(:one).applications.destroy_all
    users(:one).user_preference.update!(keywords: "")

    get dashboard_url

    assert_select "p", text: "Nothing needs you today - you're all caught up."
  end
end
