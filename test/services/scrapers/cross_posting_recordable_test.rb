require "test_helper"

class Scrapers::CrossPostingRecordableTest < ActiveSupport::TestCase
  class Dummy
    include Scrapers::CrossPostingRecordable
    public :record_or_skip_duplicate?, :record_job_source!
  end

  setup do
    @dummy = Dummy.new
    @company = companies(:one)
  end

  test "record_or_skip_duplicate? returns false and does nothing when no job matches" do
    result = @dummy.record_or_skip_duplicate?(@company, "Brand New Title", "Some Board", "https://example.com/x")

    assert_not result
  end

  test "record_or_skip_duplicate? returns true and records the source when a job with the same company+title exists" do
    existing = jobs(:one)
    existing.update!(company: @company, title: "Backend Engineer")

    result = @dummy.record_or_skip_duplicate?(@company, "Backend Engineer", "Klix Posao", "https://klix.example/job/1")

    assert result
    source = existing.job_sources.find_by(source_name: "Klix Posao")
    assert_not_nil source
    assert_equal "https://klix.example/job/1", source.url
  end

  test "record_or_skip_duplicate? is idempotent for the same job+source across repeated scrapes" do
    existing = jobs(:one)
    existing.update!(company: @company, title: "Backend Engineer")

    2.times { @dummy.record_or_skip_duplicate?(@company, "Backend Engineer", "Klix Posao", "https://klix.example/job/1") }

    assert_equal 1, existing.job_sources.where(source_name: "Klix Posao").count
  end

  test "record_job_source! adds a new source and is idempotent on repeat calls" do
    job = jobs(:one)

    assert_difference -> { job.job_sources.count }, 1 do
      2.times { @dummy.record_job_source!(job, "Dzobs IT", "https://dzobs.example/job/1") }
    end
  end

  test "record_job_source! allows the same job to accumulate multiple distinct sources" do
    job = jobs(:one)

    @dummy.record_job_source!(job, "Dzobs IT", "https://dzobs.example/job/1")
    @dummy.record_job_source!(job, "Klix Posao", "https://klix.example/job/1")

    assert_equal 2, job.job_sources.count
  end
end
