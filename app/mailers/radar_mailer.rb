# app/mailers/radar_mailer.rb
class RadarMailer < ApplicationMailer
  def daily_summary(user, matched_jobs)
    @user = user
    @jobs = matched_jobs

    mail(
      to: @user.email,
      from: "radar@nezamarajse.com",
      subject: "🎯 NeZamarajSe: #{matched_jobs.count} new jobs match your radar!"
    )
  end
end
