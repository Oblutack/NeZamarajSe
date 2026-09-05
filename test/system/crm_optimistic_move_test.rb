require "application_system_test_case"

# The board moves a card in the DOM before the server has answered, so these
# assert the two things unit tests can't reach: that the move survives the
# server's own reconciling stream, and that a refused move puts the card back
# instead of leaving it in a column the server never accepted.
class CrmOptimisticMoveTest < ApplicationSystemTestCase
  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "authenticated"
  end

  test "a card moved by the menu lands in the new column without a page reload" do
    user = users(:one)
    application = applications(:one) # wishlist
    sign_in_as user

    visit crm_path
    within "#application_#{application.id}" do
      find("button[aria-label='Move to…']").click
      find("button[data-status='interviewing']").click
    end

    # The card ends up in the destination column and the counts follow it -
    # both of which the server's stream is responsible for confirming.
    within "div[data-status='interviewing']" do
      assert_text application.job.title
      assert_selector "#crm_count_interviewing", text: "1"
    end
    assert_selector "#crm_count_wishlist", text: "0"

    # Still on the board, never navigated away.
    assert_current_path crm_path
    assert_equal "interviewing", application.reload.status
  end

  test "emptying a column brings its empty state back without a reload" do
    user = users(:one)
    application = applications(:one)
    sign_in_as user

    visit crm_path
    assert_no_selector "#crm_empty_wishlist"

    within "#application_#{application.id}" do
      find("button[aria-label='Move to…']").click
      find("button[data-status='applied']").click
    end

    assert_selector "#crm_empty_wishlist"
  end

  test "a refused move puts the card back where it came from" do
    user = users(:one)
    application = applications(:one)
    sign_in_as user

    visit crm_path

    # Force a move the server refuses: "Sending soon" is machine-owned, and
    # the UI never offers it, so drive the shared move-form directly the way
    # drag_controller does.
    page.execute_script(<<~JS, application.id)
      const id = arguments[0]
      const card = document.getElementById(`application_${id}`)
      document.getElementById("crm_list_queued").appendChild(card)
      const form = document.getElementById("move-form")
      form.action = `/applications/${id}`
      form.querySelector(".status-input").value = "queued"
      form.addEventListener("turbo:submit-end", (event) => {
        if (!event.detail.success) {
          document.getElementById("crm_list_wishlist").appendChild(card)
        }
      }, { once: true })
      form.requestSubmit()
    JS

    # The rollback returns it, and the server never accepted the change.
    within "div[data-status='wishlist']" do
      assert_text application.job.title
    end
    assert_equal "wishlist", application.reload.status
  end
end
