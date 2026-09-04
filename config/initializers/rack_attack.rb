# config/initializers/rack_attack.rb
class Rack::Attack
  # 1. Block suspicious requests immediately
  # e.g., Hackers looking for PHP admin panels on our Ruby app
  blocklist("block php/wp/admin paths") do |req|
    req.path.include?(".php") || req.path.include?("wp-admin")
  end

  # 2. Limit general traffic to 300 requests per 5 minutes per IP
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # 3. Strictly limit Login/OAuth attempts (Prevent brute-force & credential stuffing)
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.ip
    end
  end

  # 4. Strictly limit Email Dispatching (Prevent users from spamming the "Send" button)
  throttle("emails/ip", limit: 10, period: 1.minute) do |req|
    if req.path.include?("/dispatch_email") && req.post?
      req.ip
    end
  end

  # 5. Limit crowdsourced email suggestions - this is the app's first
  # write endpoint any signed-in user can hit against a *shared* record
  # (Company), not just their own data, so it's worth a dedicated cap
  # independent of the general request throttle above.
  throttle("email_suggestions/ip", limit: 10, period: 1.minute) do |req|
    if req.path.include?("/email_suggestions") && req.post?
      req.ip
    end
  end

  # 6. Limit hits on shared job links - the app's first *unauthenticated*
  # surface (no Devise session at all). share_token is 128 bits of random
  # entropy, so brute-forcing another user's link isn't realistically
  # feasible regardless of rate limiting, but a tighter cap than the
  # general request throttle still guards against scraping/enumeration
  # traffic hitting a page nothing else here requires a login for.
  throttle("public_jobs/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/j/")
  end
end
