# app/mailers/job_application_mailer.rb
class JobApplicationMailer < ApplicationMailer
  def apply(user, job, template, resume)
    @body = template.render_content(job)
    attachments[resume.filename.to_s] = resume.download

    # Figure out who we *want* to email
    intended_target = job.hr_email || job.company.primary_email || "NO_EMAIL_FOUND"

    # TRAINING WHEELS: Force the email to go to YOU, but tag the subject line
    # so you can see who it was supposed to go to.
    safe_to_address = user.email

    mail(
      to: safe_to_address, 
      from: user.email,
      subject: "[TEST: Intended for #{intended_target}] Application: #{job.title}"
    )
  end
end