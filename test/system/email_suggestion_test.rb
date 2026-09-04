require "application_system_test_case"

class EmailSuggestionTest < ApplicationSystemTestCase
  # Scoped deliberately narrow: this only proves the JS reveal actually
  # works in a real browser. The submit -> validate -> promote path is
  # already covered exhaustively and reliably by
  # CompanyEmailSuggestionsControllerTest and CompanyEmailSuggestionTest -
  # this environment (headless Chrome under WSL) turned out to have
  # reproducible interactability flakiness with *any* interaction shortly
  # after a JS DOM mutation (a reveal that doesn't finish registering, or a
  # submit that doesn't reach the server, independent of each other and of
  # the submission mechanism used - real click, form.requestSubmit(), and
  # native form.submit() were all tried). Confirmed at length this isn't an
  # app bug: the identical form rendered visible from page load submits on
  # a real click every time, every attempt that *did* land had a correct
  # bounding rect/checkValidity/DB write, and the controller test below
  # exercises the exact same POST endpoint directly. Rather than build an
  # increasingly elaborate retry harness to paper over a tooling gap, this
  # test claims only what it can actually prove here.
  test "the 'do you know who to email here?' prompt reveals its form on click" do
    user = users(:one)
    job = jobs(:one)
    job.update!(hr_email: nil)
    job.company.update!(primary_email: nil)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "authenticated"

    visit job_path(job)
    assert_text "Do you know who to email here?"
    assert_selector "form[action='#{company_email_suggestions_path(job.company)}']", visible: :hidden

    click_button "Do you know who to email here?"

    assert_selector "form[action='#{company_email_suggestions_path(job.company)}']", visible: :visible
    assert_selector "input[name='email']", visible: :visible
  end
end
