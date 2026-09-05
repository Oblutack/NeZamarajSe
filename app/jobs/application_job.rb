class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  private

  # The template or resume a queued send was going to use, or nil if either
  # has since been deleted.
  #
  # A bulk campaign staggers up to 45 minutes out (see
  # ApplicationsController#bulk_dispatch), so "the user deleted that resume
  # while sends were still pending" is a real window, not a tampering-only
  # case. Both lookups are also the ownership check for the ids the
  # controller passes straight through from params - `find_by`/`find` on the
  # user's own association, never a global lookup.
  #
  # Returned rather than raised because a deleted asset is a *permanent*
  # failure: re-raising would burn all of Sidekiq's retries over ~21 days on
  # something that can never succeed, and the mailer would only crash on
  # `resume.filename` anyway. Callers report it and stop.
  def send_assets_for(user, template_id, resume_blob_id)
    template = user.cover_letter_templates.find_by(id: template_id)
    resume = user.resumes.find { |r| r.blob_id == resume_blob_id.to_i }
    [ template, resume ]
  end

  def report_missing_send_assets(label, template, resume, context)
    missing = []
    missing << "template" if template.nil?
    missing << "resume" if resume.nil?

    message = "#{label} aborted - #{missing.join(' and ')} no longer exists"
    Rails.logger.error("#{message} (#{context.inspect})")
    Honeybadger.notify(message, context: context)
  end
end
