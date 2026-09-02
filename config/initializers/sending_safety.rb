# config/initializers/sending_safety.rb
#
# The permanent safety rails around outgoing application emails - not
# temporary hacks, meant to stay in the product. See ROADMAP.md Track B.

# When true (the default), every outgoing application email is redirected to
# the sending user's own inbox instead of the real recipient, subject tagged
# "[DRY RUN]". Flip it off (DRY_RUN_EMAILS=false) only once you're ready for
# JobApplicationMailer to actually reach real companies.
Rails.application.config.dry_run_emails =
  ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN_EMAILS", "true"))

# The global kill switch: false blocks every dispatch (single or bulk),
# dry-run or not, before anything is even queued - independent of
# dry_run_emails, for "stop everything right now" rather than "stop it from
# reaching real companies."
Rails.application.config.sending_enabled =
  ActiveModel::Type::Boolean.new.cast(ENV.fetch("SENDING_ENABLED", "true"))

# How many applications a single user can queue in a rolling day. Checked
# against Application#queued_at in ApplicationsController - see #sendable?
# and #remaining_daily_sends.
Rails.application.config.daily_send_cap =
  ENV.fetch("DAILY_SEND_CAP", "50").to_i
