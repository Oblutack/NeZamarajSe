require "test_helper"

class FindCompanyEmailJobTest < ActiveJob::TestCase
  test "runs EmailFinderService for the company" do
    company = companies(:one)
    called_with = []

    stub_class_method(EmailFinderService, :call, ->(c) { called_with << c.id }) do
      FindCompanyEmailJob.perform_now(company.id)
    end

    assert_equal [ company.id ], called_with
  end

  test "does nothing if the company no longer exists" do
    called = false

    stub_class_method(EmailFinderService, :call, ->(*) { called = true }) do
      FindCompanyEmailJob.perform_now(-1)
    end

    assert_not called
  end
end
