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

  test "allows a valid employment_type and work_mode" do
    job = Job.new(company: companies(:one), title: "Role", employment_type: "full_time", work_mode: "remote")
    assert job.valid?
  end

  test "rejects an employment_type outside the fixed vocabulary" do
    job = Job.new(company: companies(:one), title: "Role", employment_type: "freelance")
    assert_not job.valid?
    assert_includes job.errors[:employment_type], "is not included in the list"
  end

  test "rejects a work_mode outside the fixed vocabulary" do
    job = Job.new(company: companies(:one), title: "Role", work_mode: "space")
    assert_not job.valid?
    assert_includes job.errors[:work_mode], "is not included in the list"
  end

  test "employment_type and work_mode are optional" do
    job = Job.new(company: companies(:one), title: "Role")
    assert job.valid?
  end

  test "share! sets an unguessable token and returns it" do
    job = jobs(:one)
    assert_not job.shared?

    token = job.share!

    assert job.shared?
    assert_equal job.share_token, token
    assert token.length >= 20
  end

  test "share! is idempotent - calling it again keeps the same token" do
    job = jobs(:one)
    first_token = job.share!
    second_token = job.share!

    assert_equal first_token, second_token
  end

  test "unshare! clears the token" do
    job = jobs(:one)
    job.share!
    job.unshare!

    assert_not job.shared?
    assert_nil job.share_token
  end

  test "notifies a user whose radar keyword appears in the new job's title" do
    assert_difference("users(:one).notifications.count", 1) do
      Job.create!(company: companies(:one), title: "Senior Software Architect", url: "https://jobs.example.com/senior-software-architect")
    end

    assert_no_difference("users(:two).notifications.count") do
      Job.create!(company: companies(:one), title: "Another Software Role", url: "https://jobs.example.com/another-software-role")
    end
  end

  test "does not notify anyone when the new job matches no one's keywords" do
    assert_no_difference("Notification.count") do
      Job.create!(company: companies(:one), title: "Marketing Coordinator", url: "https://jobs.example.com/marketing-coordinator")
    end
  end

  test "skips a user with blank radar keywords" do
    # User#create_default_preferences already gives every new user real
    # keywords on signup - this simulates one who cleared them, not a user
    # with no UserPreference row at all.
    blank_user = User.create!(email: "blank-keywords@example.com", password: "password123")
    blank_user.user_preference.update!(keywords: "")

    assert_no_difference("blank_user.notifications.count") do
      Job.create!(company: companies(:one), title: "Senior Software Architect", url: "https://jobs.example.com/senior-software-architect-2")
    end
  end
end
