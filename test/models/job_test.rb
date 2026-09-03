require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "requires a title" do
    job = Job.new(company: companies(:one), url: "https://jobs.example.com/new-role")
    assert_not job.valid?
    assert_includes job.errors[:title], "can't be blank"
  end

  test "requires a unique url" do
    duplicate = Job.new(company: companies(:one), title: "Duplicate Role", url: jobs(:one).url)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:url], "has already been taken"
  end

  test "does not require a url - a manually-added job often has none" do
    job = Job.new(company: companies(:one), title: "Found via LinkedIn")
    assert job.valid?
  end

  test "allows more than one job with no url" do
    Job.create!(company: companies(:one), title: "Manual Role One")
    second = Job.new(company: companies(:one), title: "Manual Role Two")

    assert second.valid?
  end

  test "visible_to includes every scraped job and only the current user's own manual jobs" do
    scraped = jobs(:one)
    mine = Job.create!(company: companies(:one), title: "Mine", added_by: users(:one))
    theirs = Job.create!(company: companies(:one), title: "Theirs", added_by: users(:two))

    visible = Job.visible_to(users(:one))

    assert_includes visible, scraped
    assert_includes visible, mine
    assert_not_includes visible, theirs
  end

  test "destroying a job destroys its applications" do
    application = applications(:one)
    job = application.job

    assert_difference("Application.count", -1) do
      job.destroy
    end
  end

  test "destroying a job destroys its job_sources" do
    job = jobs(:one)
    job.job_sources.create!(source_name: "Klix Posao")

    assert_difference("JobSource.count", -1) do
      job.destroy
    end
  end

  test "expiring_soon includes a job expiring within 14 days" do
    job = jobs(:one)
    job.update!(expires_at: 5.days.from_now)

    assert_includes Job.expiring_soon, job
  end

  test "expiring_soon excludes a job with no deadline or one further out" do
    job = jobs(:one)
    job.update!(expires_at: nil)
    assert_not_includes Job.expiring_soon, job

    job.update!(expires_at: 30.days.from_now)
    assert_not_includes Job.expiring_soon, job
  end

  test "keyword_match_count counts case-insensitive matches across title and description" do
    job = jobs(:one)
    job.update!(title: "Senior Ruby Developer", description: "We use React on the frontend.")

    assert_equal 2, job.keyword_match_count(%w[ruby react python])
  end

  test "keyword_match_count is 0 with no keywords" do
    job = jobs(:one)
    assert_equal 0, job.keyword_match_count([])
    assert_equal 0, job.keyword_match_count(nil)
  end
end
