require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  # The filter/sort/pagination tests below want an unfiltered job list to
  # narrow down from a known baseline - clears the default seeded radar
  # keywords ("Developer, Software, IT", neither of which the fixture job
  # titles happen to contain) so the keyword-fallback branch in #index
  # doesn't silently exclude them before the filter under test even runs.
  def clear_radar_keywords
    users(:one).user_preference.update!(keywords: "")
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

  test "location filter narrows to jobs at that exact location" do
    clear_radar_keywords
    get jobs_url, params: { location: "Sarajevo" }

    assert_match jobs(:one).title, response.body
    assert_no_match(/#{Regexp.escape(jobs(:two).title)}/, response.body)
  end

  test "source filter narrows to jobs seen on that board" do
    clear_radar_keywords
    jobs(:one).job_sources.create!(source_name: "Klix Posao")

    get jobs_url, params: { source: "Klix Posao" }

    assert_match jobs(:one).title, response.body
    assert_no_match(/#{Regexp.escape(jobs(:two).title)}/, response.body)
  end

  test "has_contact filter narrows to jobs with a known hr_email" do
    clear_radar_keywords
    jobs(:one).update!(hr_email: "hr@realcompany.example")
    jobs(:two).update!(hr_email: nil)

    get jobs_url, params: { has_contact: "1" }

    assert_match jobs(:one).title, response.body
    assert_no_match(/#{Regexp.escape(jobs(:two).title)}/, response.body)
  end

  test "expiring_soon filter narrows to jobs whose deadline is within 14 days" do
    clear_radar_keywords
    jobs(:one).update!(expires_at: 5.days.from_now)
    jobs(:two).update!(expires_at: 60.days.from_now)

    get jobs_url, params: { expiring_soon: "1" }

    assert_match jobs(:one).title, response.body
    assert_no_match(/#{Regexp.escape(jobs(:two).title)}/, response.body)
  end

  test "posted_within filter excludes jobs older than the chosen window" do
    clear_radar_keywords
    jobs(:one).update!(created_at: 10.days.ago)
    jobs(:two).update!(created_at: 1.hour.ago)

    get jobs_url, params: { posted_within: "1" }

    assert_no_match(/#{Regexp.escape(jobs(:one).title)}/, response.body)
    assert_match jobs(:two).title, response.body
  end

  test "sort=company orders jobs by company name" do
    clear_radar_keywords
    get jobs_url, params: { sort: "company" }

    assert_response :success
    one_position = response.body.index(jobs(:one).company.name)
    two_position = response.body.index(jobs(:two).company.name)
    assert_operator one_position, :<, two_position if jobs(:one).company.name < jobs(:two).company.name
  end

  test "paginates beyond the first page" do
    clear_radar_keywords
    26.times do |n|
      Job.create!(company: companies(:one), title: "Generated Job #{n}", url: "https://jobs.example.com/generated-#{n}")
    end

    get jobs_url
    assert_response :success
    assert_select "nav[aria-label=Pagination]"

    get jobs_url, params: { page: 2 }
    assert_response :success
  end

  test "should get show" do
    job = jobs(:one)
    get job_url(job)

    assert_response :success
    assert_select "h1", text: job.title
  end

  test "show renders the description and cross-posting boards" do
    job = jobs(:one)
    job.job_sources.create!(source_name: "Dzobs IT")
    job.job_sources.create!(source_name: "Klix Posao")

    get job_url(job)

    assert_match job.description, response.body
    assert_match(/Posted on 2 boards/, response.body)
  end

  test "index shows a keyword match badge based on the user's radar keywords" do
    users(:one).user_preference.update!(keywords: "Ruby, React, Python")
    jobs(:one).update!(title: "Senior Ruby Developer", description: "You'll write Ruby and React.")

    get jobs_url, params: { q: jobs(:one).title }

    assert_match(/2\/3 keywords match/, response.body)
  end

  test "show shows a keyword match badge based on the user's radar keywords" do
    users(:one).user_preference.update!(keywords: "Ruby, React, Python")
    job = jobs(:one)
    job.update!(title: "Senior Ruby Developer", description: "You'll write Ruby and React.")

    get job_url(job)

    assert_match(/2\/3 keywords match/, response.body)
  end

  test "no keyword match badge when the user has no radar keywords set" do
    users(:one).user_preference.update!(keywords: "")

    get job_url(jobs(:one))

    assert_no_match(/keywords match/, response.body)
  end

  test "index prompts for an email suggestion on a job with no known contact" do
    jobs(:one).update!(hr_email: nil)
    companies(:one).update!(primary_email: nil)

    get jobs_url, params: { q: jobs(:one).title }

    assert_match(/Do you know who to email here\?/, response.body)
  end

  test "index does not prompt for an email suggestion once a contact is known" do
    jobs(:one).update!(hr_email: "hr@realcompany.example")

    get jobs_url, params: { q: jobs(:one).title }

    assert_no_match(/Do you know who to email here\?/, response.body)
  end

  test "show prompts for an email suggestion on a job with no known contact" do
    job = jobs(:one)
    job.update!(hr_email: nil)
    job.company.update!(primary_email: nil)

    get job_url(job)

    assert_select "form[action=?]", company_email_suggestions_path(job.company)
  end

  test "should get new" do
    get new_job_url
    assert_response :success
  end

  test "create adds a manually-entered job to the user's wishlist" do
    assert_difference([ "Job.count", "Application.count" ], 1) do
      post jobs_url, params: {
        job: {
          company_name: "Newco d.o.o.",
          title: "Found on LinkedIn",
          location: "Mostar"
        }
      }
    end

    job = Job.order(:created_at).last
    assert_equal "Newco d.o.o.", job.company.name
    assert_equal users(:one), job.added_by
    assert users(:one).applications.find_by(job: job).wishlist?
    assert_redirected_to crm_path
  end

  test "create reuses an existing company by name instead of duplicating it" do
    existing = companies(:one)

    assert_no_difference("Company.count") do
      post jobs_url, params: { job: { company_name: existing.name, title: "Another Role At The Same Place" } }
    end

    assert_equal existing, Job.order(:created_at).last.company
  end

  test "create requires a company name" do
    assert_no_difference("Job.count") do
      post jobs_url, params: { job: { title: "No Company Given" } }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: /Company/
  end

  test "create requires a title" do
    assert_no_difference("Job.count") do
      post jobs_url, params: { job: { company_name: "Some Co" } }
    end

    assert_response :unprocessable_entity
  end

  test "create enqueues AI analysis only when a url is given and no description was written" do
    assert_enqueued_with(job: AnalyzeJob) do
      post jobs_url, params: { job: { company_name: "Newco", title: "With URL", url: "https://example.com/job" } }
    end
  end

  test "create does not enqueue AI analysis when the user already wrote a description" do
    assert_no_enqueued_jobs(only: AnalyzeJob) do
      post jobs_url, params: {
        job: { company_name: "Newco", title: "With URL And Description", url: "https://example.com/job", description: "My own words." }
      }
    end
  end

  test "create does not enqueue AI analysis when there is no url" do
    assert_no_enqueued_jobs(only: AnalyzeJob) do
      post jobs_url, params: { job: { company_name: "Newco", title: "No URL" } }
    end
  end

  test "a manually-added job is private to whoever added it" do
    other_job = Job.create!(company: companies(:one), title: "Someone Else's Lead", added_by: users(:two))

    get jobs_url
    assert_no_match(/#{Regexp.escape(other_job.title)}/, response.body)

    get job_url(other_job)
    assert_response :not_found
  end
end
