require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "sends a real CSP header, not the stock commented-out no-op" do
    sign_in users(:one)
    get dashboard_url

    header = response.headers["Content-Security-Policy"]
    assert header.present?

    assert_match(/script-src 'self' 'nonce-[^']+'/, header)
    assert_match(/style-src 'self' 'unsafe-inline' https:\/\/fonts\.googleapis\.com/, header)
    assert_match(/object-src 'none'/, header)
    assert_match(/frame-ancestors 'none'/, header)
  end

  test "the dark-mode anti-flash inline script carries a valid nonce" do
    sign_in users(:one)
    get dashboard_url

    header = response.headers["Content-Security-Policy"]
    nonce = header[/script-src 'self' 'nonce-([^']+)'/, 1]
    assert_select "script[nonce='#{nonce}']", text: /localStorage\.getItem\("theme"\)/
  end

  test "each request gets its own nonce, not a session-wide constant one" do
    sign_in users(:one)

    get dashboard_url
    first_nonce = response.headers["Content-Security-Policy"][/nonce-([^']+)/, 1]

    get dashboard_url
    second_nonce = response.headers["Content-Security-Policy"][/nonce-([^']+)/, 1]

    assert_not_equal first_nonce, second_nonce
  end
end
