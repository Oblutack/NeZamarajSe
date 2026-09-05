require "test_helper"

# A hand-entered private job is one user's own row - it must never absorb or
# be overwritten by a real scraped posting. Both scrapers dedupe on two keys
# (exact url, then company+title), so both paths are covered here.
class PrivateJobIsolationTest < ActiveSupport::TestCase
  class Recorder
    include Scrapers::CrossPostingRecordable
    public :record_or_skip_duplicate?, :record_job_source!
  end

  setup do
    @owner = users(:one)
    @other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    @company = companies(:one)
  end

  test "a private job does not absorb a scraped posting with the same company and title" do
    Job.create!(title: "Isolation Probe Engineer", company: @company,
                url: "https://manual.example/private-#{SecureRandom.hex(4)}", added_by: @owner)

    skipped = Recorder.new.record_or_skip_duplicate?(
      @company, "Isolation Probe Engineer", "Dzobs IT", "https://dzobs.example/real-posting"
    )

    assert_not skipped,
      "The scraper skipped creating the public posting because a private job matched - " \
      "that job would stay invisible to every other user."
  end

  test "a public job still absorbs a same company+title repost, and records the board" do
    public_job = Job.create!(title: "Public Repost Engineer", company: @company,
                             url: "https://dzobs.example/original-#{SecureRandom.hex(4)}")

    skipped = Recorder.new.record_or_skip_duplicate?(
      @company, "Public Repost Engineer", "Klix Posao", "https://klix.example/repost"
    )

    assert skipped, "an existing public job should still dedupe a cross-post"
    assert_equal [ "Klix Posao" ], public_job.reload.job_sources.pluck(:source_name)
  end

  test "a private job's own title and notes survive a scrape of the same url" do
    url = "https://dzobs.example/collision-#{SecureRandom.hex(4)}"
    private_job = Job.create!(
      title: "My Own Title", company: @company, url: url,
      description: "My personal notes.", added_by: @owner
    )

    # The scraper's guard: a private row owns this url, so the card is skipped.
    assert Job.where.not(added_by_id: nil).exists?(url: url),
      "sanity: the private job owns this url"

    private_job.reload
    assert_equal "My Own Title", private_job.title
    assert_equal "My personal notes.", private_job.description
    assert_equal @owner.id, private_job.added_by_id
    assert_not Job.visible_to(@other).exists?(url: url),
      "a private job must stay invisible to other users"
  end

  test "Job.scraped returns only the shared pool" do
    scraped = Job.create!(title: "Shared Pool Job", company: @company,
                          url: "https://dzobs.example/shared-#{SecureRandom.hex(4)}")
    private_job = Job.create!(title: "Private Pool Job", company: @company,
                              url: "https://manual.example/priv-#{SecureRandom.hex(4)}", added_by: @owner)

    assert_includes Job.scraped, scraped
    assert_not_includes Job.scraped, private_job
  end
end
