require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # --no-sandbox/--disable-dev-shm-usage: same flags the Ferrum scraper
  # already needs for headless Chrome on Linux CI runners (see CLAUDE.md) -
  # without them Chrome fails to launch under GitHub Actions' root/container
  # environment even though it launches fine on a local dev machine.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
    driver_option.add_argument("--no-sandbox")
    driver_option.add_argument("--disable-dev-shm-usage")
  end

  # The default 2s wait is fine on a local machine but too tight on a colder/
  # shared GitHub Actions runner - confirmed by a CI failure where a page
  # still showed its pre-click state (the redirect just hadn't landed yet
  # when Capybara re-checked), not any real app bug.
  Capybara.default_max_wait_time = 5
end
