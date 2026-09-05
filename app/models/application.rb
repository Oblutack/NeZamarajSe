# app/models/application.rb
class Application < ApplicationRecord
  belongs_to :user
  belongs_to :job
  belongs_to :cover_letter_template, optional: true
  has_many :application_events, dependent: :destroy

  # The Rails 8 Way to handle state machines / CRM lanes
  enum :status, {
    wishlist: "wishlist",
    queued: "queued",
    applied: "applied",
    interviewing: "interviewing",
    rejected: "rejected",
    offered: "offered"
  }

  # Statuses that mean an application has actually been submitted somewhere,
  # whether this app emailed it or the user applied on the company's own site.
  # "queued" is deliberately not in here - it means a send is *scheduled*,
  # not that anything has been submitted yet.
  SUBMITTED_STATUSES = %w[applied interviewing rejected offered].freeze

  # "Sending soon" is the one lane the machine owns rather than the user:
  # it means a real SendApplicationJob is scheduled right now. Entering it by
  # hand would fake that (no template, no resume, nothing enqueued) and
  # leaving it by hand strands queued_at while the scheduled job silently
  # no-ops - so both directions go through ApplicationsController's
  # dispatch_email/#cancel instead, which keep the queue and the daily cap
  # in sync. See #manually_movable_statuses for what the UI offers.
  MACHINE_OWNED_STATUS = "queued".freeze

  # Sorts a column so the most urgent deadline is at the top. A job with no
  # known deadline isn't more urgent than one that's actually expiring, so it
  # sorts last - via a sentinel date rather than Date::Infinity, which doesn't
  # compare against a plain Date in this Ruby version.
  NO_DEADLINE_SENTINEL = Date.new(9999, 12, 31)

  validates :user_id, uniqueness: { scope: :job_id, message: ->(_object, _data) { I18n.t("activerecord.errors.models.application.attributes.user_id.already_saved") } }

  before_save :sync_applied_at, if: :will_save_change_to_status?

  after_update_commit -> { broadcast_status_update }, if: :saved_change_to_status?
  after_update_commit -> { record_status_change_event }, if: :saved_change_to_status?

  # The statuses a card may be moved to by hand (drag-and-drop or the card's
  # "Move to…" menu). Empty for an application that's mid-send: its only exit
  # is Cancel send.
  def manually_movable_statuses
    return [] if queued?

    self.class.statuses.keys - [ status, MACHINE_OWNED_STATUS ]
  end

  # One definition of a column's ordering, shared by the board's initial
  # render and by the Turbo Stream that slots a moved card back in - so a
  # card lands in the same place either way.
  def deadline_sort_key
    job.expires_at || NO_DEADLINE_SENTINEL
  end

  # The real target this application would go to - shared by the compose
  # preview and the mailer, so they can never say different things about who
  # this is "for". Independent of dry_run_emails: this is who it's *for*,
  # not necessarily where the bytes go (see JobApplicationMailer#apply).
  def intended_recipient
    job.hr_email.presence || job.company.primary_email.presence
  end

  # Flags a silent "applied" card so the CRM can nudge the user to check in -
  # the clock resets on each follow-up sent, not just the original send, so
  # this fires again N days after the *last* contact, not just the first.
  def needs_follow_up?
    return false unless applied?

    last_contact = last_followed_up_at || applied_at
    last_contact.present? && last_contact <= Rails.application.config.follow_up_after_days.days.ago
  end

  # A plain RFC 5545 .ics file, hand-built rather than pulling in a gem for
  # one event - a 1-hour block starting at interview_date, since nothing on
  # the form captures an actual duration. CRLF line endings are required by
  # the spec, not just style.
  def interview_ics
    return nil if interview_date.blank?

    start_time = interview_date.utc
    end_time = start_time + 1.hour

    <<~ICS.gsub("\n", "\r\n")
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//NeZamarajSe//Interview//EN
      BEGIN:VEVENT
      UID:application-#{id}@nezamarajse.local
      DTSTAMP:#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}
      DTSTART:#{start_time.strftime('%Y%m%dT%H%M%SZ')}
      DTEND:#{end_time.strftime('%Y%m%dT%H%M%SZ')}
      SUMMARY:#{ics_escape("Interview: #{job.title} at #{job.company.name}")}
      DESCRIPTION:#{ics_escape("Interview for the #{job.title} position at #{job.company.name}.")}
      END:VEVENT
      END:VCALENDAR
    ICS
  end

  private

  # applied_at used to be written only by SendApplicationJob, so a card moved
  # to "Applied" by hand - the most common real action there is, "I applied on
  # their own website" - kept a nil applied_at and became invisible to the
  # half of the app that reads it: no follow-up reminder ever fired
  # (#needs_follow_up? returns false with no last contact to measure from),
  # and the dashboard's sent-this-month count, funnel, and response rate all
  # skipped it. Keeping this in sync with status here means every path gets it
  # right, including the job (which assigns applied_at itself in the same
  # update, so the ||= below is a no-op there).
  #
  # Moving back out clears it again so a mis-drag doesn't leave a phantom in
  # the funnel - but only when nothing was ever actually sent. A real send's
  # history (sent_recipient and friends) must survive being moved around the
  # board.
  def sync_applied_at
    if SUBMITTED_STATUSES.include?(status)
      self.applied_at ||= Time.current
    elsif sent_recipient.blank?
      self.applied_at = nil
    end
  end

  def ics_escape(text)
    text.to_s.gsub("\\", "\\\\\\\\").gsub(",", "\\,").gsub(";", "\\;")
  end

  # Used to be a bare replace of the card in place, which re-rendered its
  # contents but left it sitting in the column it moved *out of* on every
  # other open board, with both column counts stale. Renders the same set of
  # stream actions ApplicationsController#update responds with, so a move
  # looks identical whether this tab made it or another one did.
  def broadcast_status_update
    Turbo::StreamsChannel.broadcast_render_to(
      [ user, :crm ],
      partial: "applications/status_change_streams",
      locals: { app: self, from_status: status_before_last_save, to_status: status }
    )
  end

  def record_status_change_event
    application_events.create!(
      event_type: "status_change",
      from_status: status_before_last_save,
      to_status: status
    )
  end
end
