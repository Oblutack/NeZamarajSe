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
end
