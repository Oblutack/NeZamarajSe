require "test_helper"

class AnalyzeJobTest < ActiveJob::TestCase
  test "runs AiJobAnalyzerService for the job" do
    job = jobs(:one)
    called_with = []

    stub_class_method(AiJobAnalyzerService, :call, ->(j, *) { called_with << j.id }) do
      AnalyzeJob.perform_now(job.id)
    end

    assert_equal [ job.id ], called_with
  end

  test "forwards skip_email_lookup to AiJobAnalyzerService" do
    called_with = nil

    # stub_class_method only splats *args through, so a keyword call arrives
    # here as a trailing positional Hash, not real keywords - capture it with
    # a plain positional param rather than **kwargs to avoid Ruby 3's strict
    # positional/keyword separation.
    stub_class_method(AiJobAnalyzerService, :call, ->(j, opts = {}) { called_with = opts[:skip_email_lookup] }) do
      AnalyzeJob.perform_now(jobs(:one).id, skip_email_lookup: true)
    end

    assert_equal true, called_with
  end

  test "does nothing if the job no longer exists" do
    called = false

    stub_class_method(AiJobAnalyzerService, :call, ->(*) { called = true }) do
      AnalyzeJob.perform_now(-1)
    end

    assert_not called
  end

  test "re-raises so Sidekiq can retry when analysis blows up" do
    stub_class_method(AiJobAnalyzerService, :call, ->(*) { raise "Groq is down" }) do
      assert_raises(RuntimeError) do
        AnalyzeJob.perform_now(jobs(:one).id)
      end
    end
  end
end
