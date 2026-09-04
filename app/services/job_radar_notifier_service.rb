# app/services/job_radar_notifier_service.rb

# Persists a Notification the moment a newly-scraped job matches a user's
# radar keywords, then broadcasts it over Turbo Streams so it shows up in
# the navbar bell without a page refresh - for anyone with a tab open on a
# deployment where Action Cable actually spans processes (production's
# solid_cable, per config/cable.yml). In development, the `async` adapter
# only pub/subs within a single process, so a broadcast from a Sidekiq job
# never reaches a browser connected to the separate `bin/rails server`
# process - the Notification row itself is still created and read normally
# on the next page load/Turbo Drive navigation either way, so nothing is
# actually lost locally, just the live push.
class JobRadarNotifierService
  def self.call(job:, user:)
    new(job: job, user: user).call
  end

  def initialize(job:, user:)
    @job = job
    @user = user
  end

  def call
    notification = @user.notifications.create!(job: @job)
    broadcast(notification)
    notification
  end

  private

  def broadcast(notification)
    Turbo::StreamsChannel.broadcast_prepend_to(
      [ @user, :notifications ],
      target: "notification_list",
      partial: "notifications/notification",
      locals: { notification: notification }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      [ @user, :notifications ],
      target: "notification_badge",
      partial: "shared/notification_badge",
      locals: { count: @user.notifications.unread.count }
    )
  end
end
