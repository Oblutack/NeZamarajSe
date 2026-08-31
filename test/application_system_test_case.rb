require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # --no-sandbox/--disable-dev-shm-usage: same flags the Ferrum scraper
  # already needs for headless Chrome on Linux CI runners (see CLAUDE.md) -
  # without them Chrome fails to launch under GitHub Actions' root/container
  # environment even though it launches fine on a local dev machine.
  # goog:loggingPrefs turns on browser-console log capture (see teardown
  # below) - without it Selenium can't retrieve any console/JS output at all.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
    driver_option.add_argument("--no-sandbox")
    driver_option.add_argument("--disable-dev-shm-usage")
    driver_option.add_option("goog:loggingPrefs", { browser: "ALL" })
  end

  # A page repeatedly showed its pre-click state on GitHub Actions (not
  # locally) even after bumping the wait time - print the browser's own
  # console log on failure so the next occurrence shows the real JS error
  # instead of another guess from the page snapshot alone.
  Capybara.default_max_wait_time = 5

  teardown do
    next if passed?

    puts "\n--- Failure diagnostics (#{self.class}##{name}) ---"

    begin
      puts "current_url: #{page.current_url}"
      puts "Application.count: #{Application.count}"
    rescue StandardError => e
      puts "(couldn't read page/DB state: #{e.message})"
    end

    begin
      logs = page.driver.browser.logs.get(:browser)
      if logs.present?
        puts "browser console logs:"
        logs.each { |entry| puts "  [#{entry.level}] #{entry.message}" }
      else
        puts "browser console logs: (none)"
      end
    rescue StandardError => e
      puts "(couldn't retrieve browser console logs: #{e.message})"
    end

    puts "--- end failure diagnostics ---\n"
  end
end
