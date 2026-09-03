# app/models/job.rb
class Job < ApplicationRecord
  belongs_to :company
  belongs_to :added_by, class_name: "User", optional: true
  has_many :applications, dependent: :destroy
  has_many :job_sources, dependent: :destroy

  # Only used by the manual-entry form (JobsController#new/#create) - scrapers
  # resolve/assign `company` directly instead of going through this. Kept on
  # the model (not a controller-only local) so validation errors on it
  # (see #create) render through the same `.errors.full_messages` list as
  # every other field on the form.
  attr_accessor :company_name

  validates :title, presence: true
  # A scraped job always has a url (and always did - this was `presence:
  # true` before manual entry existed); one entered by hand often doesn't
  # (found via LinkedIn, a careers page, or word of mouth, not a URL).
  # `allow_nil` also means multiple manual jobs with no url don't collide
  # with each other under the uniqueness check.
  validates :url, uniqueness: true, allow_nil: true

  scope :expiring_soon, -> { where(expires_at: Date.current..14.days.from_now) }

  # nil `added_by_id` means scraped/shared (every job before manual entry
  # existed, and every future scraped one) - visible to everyone, same as
  # today. A real `added_by_id` means it was entered by hand and is private
  # to whoever added it - Jobs/Companies are otherwise fully shared/global
  # (see CLAUDE.md's Multi-tenancy note), so this is the one exception and
  # every controller reading Job outside a user's own applications must
  # filter through this.
  scope :visible_to, ->(user) { where(added_by_id: nil).or(where(added_by_id: user.id)) }
end
