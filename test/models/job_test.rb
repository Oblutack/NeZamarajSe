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
end
