require "test_helper"

class HunterLookupTest < ActiveSupport::TestCase
  test "requires a company" do
    lookup = HunterLookup.new
    assert_not lookup.valid?
  end

  test "belongs to the company it looked up" do
    lookup = HunterLookup.create!(company: companies(:one))
    assert_equal companies(:one), lookup.company
  end
end
