require "test_helper"

class UserPreferenceTest < ActiveSupport::TestCase
  test "keyword_array splits, downcases, and trims comma-separated keywords" do
    preference = UserPreference.new(keywords: " Ruby, Rails ,  DEVELOPER")
    assert_equal %w[ruby rails developer], preference.keyword_array
  end

  test "keyword_array drops blank entries from stray commas" do
    preference = UserPreference.new(keywords: "Ruby,, Rails,")
    assert_equal %w[ruby rails], preference.keyword_array
  end

  test "keyword_array returns an empty array when keywords is blank" do
    assert_equal [], UserPreference.new(keywords: nil).keyword_array
    assert_equal [], UserPreference.new(keywords: "").keyword_array
  end
end
