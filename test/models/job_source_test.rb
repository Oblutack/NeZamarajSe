require "test_helper"

class JobSourceTest < ActiveSupport::TestCase
  test "requires a source_name" do
    source = JobSource.new(job: jobs(:one))
    assert_not source.valid?
    assert_includes source.errors[:source_name], "can't be blank"
  end

  test "source_name is unique per job" do
    job = jobs(:one)
    job.job_sources.create!(source_name: "Klix Posao")

    duplicate = JobSource.new(job: job, source_name: "Klix Posao")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_name], "has already been taken"
  end

  test "the same source_name can be used across different jobs" do
    jobs(:one).job_sources.create!(source_name: "Klix Posao")
    other = JobSource.new(job: jobs(:two), source_name: "Klix Posao")

    assert other.valid?
  end
end
