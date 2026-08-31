require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  test "requires a name" do
    company = Company.new(website: "https://example.com")
    assert_not company.valid?
    assert_includes company.errors[:name], "can't be blank"
  end

  test "requires a unique name" do
    duplicate = Company.new(name: companies(:one).name)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "destroying a company destroys its jobs" do
    company = companies(:one)

    assert_difference("Job.count", -1) do
      company.destroy
    end
  end
end
