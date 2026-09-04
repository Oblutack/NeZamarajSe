# app/models/job.rb
class Job < ApplicationRecord
  belongs_to :company
  belongs_to :added_by, class_name: "User", optional: true
  has_many :applications, dependent: :destroy
  has_many :job_sources, dependent: :destroy
  has_many :notifications, dependent: :destroy

  after_create_commit :notify_matching_users

  # Only used by the manual-entry form (JobsController#new/#create) - scrapers
  # resolve/assign `company` directly instead of going through this. Kept on
  # the model (not a controller-only local) so validation errors on it
  # (see #create) render through the same `.errors.full_messages` list as
  # every other field on the form.
  attr_accessor :company_name

  EMPLOYMENT_TYPES = %w[full_time part_time contract internship].freeze
  WORK_MODES = %w[on_site hybrid remote].freeze

  validates :title, presence: true
  # A scraped job always has a url (and always did - this was `presence:
  # true` before manual entry existed); one entered by hand often doesn't
  # (found via LinkedIn, a careers page, or word of mouth, not a URL).
  # `allow_nil` also means multiple manual jobs with no url don't collide
  # with each other under the uniqueness check.
  validates :url, uniqueness: true, allow_nil: true
  # Manual-entry-only fields (nothing populates these from a scraper yet) -
  # optional, but constrained to a fixed vocabulary when given, same reason
  # Application's status enum is a fixed set rather than free text.
  validates :employment_type, inclusion: { in: EMPLOYMENT_TYPES }, allow_nil: true
  validates :work_mode, inclusion: { in: WORK_MODES }, allow_nil: true

  scope :expiring_soon, -> { where(expires_at: Date.current..14.days.from_now) }

  # nil `added_by_id` means scraped/shared (every job before manual entry
  # existed, and every future scraped one) - visible to everyone, same as
  # today. A real `added_by_id` means it was entered by hand and is private
  # to whoever added it - Jobs/Companies are otherwise fully shared/global
  # (see CLAUDE.md's Multi-tenancy note), so this is the one exception and
  # every controller reading Job outside a user's own applications must
  # filter through this.
  scope :visible_to, ->(user) { where(added_by_id: nil).or(where(added_by_id: user.id)) }

  # How many of the user's own radar keywords show up in this posting's
  # title/description - a plain substring count, not a ranked search
  # relevance score. Deliberately reuses whatever's already in `description`
  # as-is (a freshly-scraped job's placeholder text, or blank for a manual
  # entry with none written) rather than treating that as a special case -
  # the score just improves on its own once AI analysis fills in the real
  # text, same job either way.
  def keyword_match_count(keywords)
    return 0 if keywords.blank?

    haystack = "#{title} #{description}".downcase
    keywords.count { |keyword| haystack.include?(keyword.downcase) }
  end

  def shared?
    share_token.present?
  end

  # A 128-bit random token, not a sequential id or anything derived from the
  # job itself - GET /j/:token (PublicJobsController) skips authentication
  # entirely, so this needs to be unguessable, not just "not obvious".
  def share!
    update!(share_token: SecureRandom.urlsafe_base64(16)) unless shared?
    share_token
  end

  def unshare!
    update!(share_token: nil)
  end

  private

  # Fires once per genuinely new job (cross-posting dedup in
  # Scrapers::CrossPostingRecordable skips `create` entirely for a repeat
  # posting, so this never double-fires for the same listing). Reuses
  # #keyword_match_count rather than a separate SQL-based check like
  # JobsController#index/SendDailyRadarJob - this runs once per new job
  # against every user's keyword list, the cheap direction for a plain-Ruby
  # substring check, whereas those two filter the whole jobs table and need
  # SQL to stay fast.
  def notify_matching_users
    UserPreference.where.not(keywords: [ nil, "" ]).find_each do |preference|
      next unless keyword_match_count(preference.keyword_array).positive?

      JobRadarNotifierService.call(job: self, user: preference.user)
    end
  end
end
