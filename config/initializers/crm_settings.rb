# config/initializers/crm_settings.rb
#
# Permanent CRM-behavior config, same env-driven pattern as
# sending_safety.rb - not a temporary hack. See ROADMAP.md Track D.

# How many days of silence after applying before Application#needs_follow_up?
# starts flagging a card. Read fresh on every check, not memoized.
Rails.application.config.follow_up_after_days =
  ENV.fetch("FOLLOW_UP_AFTER_DAYS", "7").to_i
