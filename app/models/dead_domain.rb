# app/models/dead_domain.rb
#
# Tracks hosts that AiJobAnalyzerService has repeatedly failed to fetch a
# job posting from (connection refused, timeout, etc.), so it can stop
# spending its full connect/read timeout on a domain that's known to be
# down instead of re-learning that on every job hosted there.
class DeadDomain < ApplicationRecord
  validates :host, presence: true, uniqueness: true

  THRESHOLD = 3
  # After this long with no successful re-check, give the host one more
  # real attempt rather than skipping it forever - a domain that was down
  # for a week but has since recovered shouldn't stay blacklisted
  # permanently just because nothing ever probed it again.
  COOLDOWN = 7.days

  def self.dead?(host)
    return false if host.blank?

    domain = find_by(host: host)
    return false unless domain

    domain.failure_count >= THRESHOLD &&
      domain.last_failed_at.present? &&
      domain.last_failed_at > COOLDOWN.ago
  end

  def self.record_failure!(host)
    return if host.blank?

    domain = find_or_create_by!(host: host)
    domain.update!(failure_count: domain.failure_count + 1, last_failed_at: Time.current)
  end

  def self.record_success!(host)
    return if host.blank?

    find_by(host: host)&.update!(failure_count: 0)
  end
end
