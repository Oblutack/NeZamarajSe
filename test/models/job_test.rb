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
end
