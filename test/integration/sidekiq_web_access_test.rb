require "test_helper"

class SidekiqWebAccessTest < ActionDispatch::IntegrationTest
  test "a non-admin signed-in user cannot reach /sidekiq" do
    user = users(:one)
    assert_not user.admin?
    sign_in user

    get "/sidekiq"

    # The route constraint (authenticate :user, ->(user) { user.admin? })
    # simply doesn't match for a non-admin, same as if the route didn't
    # exist - a 404, not a redirect. Arguably the better failure mode here:
    # it doesn't confirm to a non-admin that an admin panel exists at all.
    assert_response :not_found
  end

  test "an admin can reach /sidekiq" do
    user = users(:one)
    user.update!(admin: true)
    sign_in user

    get "/sidekiq"

    assert_response :success
  end

  test "a signed-out visitor cannot reach /sidekiq" do
    get "/sidekiq"

    assert_response :redirect
  end
end
