# app/mailers/radar_mailer.rb
#
# Only ever *renders* the digest - SendRadarDigestJob takes the finished message
# and sends it through the user's own Gmail (GmailSenderService). Nothing here
# is delivered by ActionMailer, and production has no delivery method set.
class RadarMailer < ApplicationMailer
  def daily_summary(user, matched_jobs)
    @user = user
    @jobs = matched_jobs
    count = matched_jobs.size

    mail(
      to: @user.email,
      # From the user's own account, not a made-up address on a domain this app
      # doesn't own: Gmail's API stamps the authenticated account as the sender
      # regardless, so claiming anything else would only be overwritten. Same
      # as JobApplicationMailer.
      from: email_address_with_name(@user.email, "NeZamarajSe Radar"),
      subject: "🎯 NeZamarajSe: #{count} new #{'job'.pluralize(count)} #{count == 1 ? 'matches' : 'match'} your radar!"
    )
  end
end
