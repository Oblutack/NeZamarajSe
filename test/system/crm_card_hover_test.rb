require "application_system_test_case"

class CrmCardHoverTest < ApplicationSystemTestCase
  # Cards lift 2px on hover (hover:-translate-y-0.5) inside an overflow-y-auto
  # list. Without top padding on that list the topmost card has zero clearance,
  # so the lift crosses the container's edge, gets clipped, and its top border
  # reads as merging into the column header above it.
  test "the top card has room to lift on hover without clipping into the header" do
    user = users(:one)
    application = applications(:one)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "authenticated"

    visit crm_path
    assert_text application.job.title

    clearance = page.evaluate_script(<<~JS)
      (() => {
        const list = document.getElementById("crm_list_wishlist")
        const card = list.querySelector("turbo-frame")
        return card.getBoundingClientRect().top - list.getBoundingClientRect().top
      })()
    JS

    # 2px is exactly what the hover translate consumes; anything less and the
    # lifted card crosses the container's top edge.
    assert_operator clearance, :>=, 2,
      "the top card has #{clearance}px above it - a hover lift would clip into the column header"
  end
end
