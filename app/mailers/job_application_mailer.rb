# app/mailers/job_application_mailer.rb
class JobApplicationMailer < ApplicationMailer
  # This builds the email but DOES NOT send it (Google API will do the sending)
  def apply(user, job, template, resume)
    # Use our smart tags to dynamically render the text
    @body = template.render_content(job)

    # Active Storage Magic: Download the PDF from disk/S3 and attach it to the email
    attachments[resume.filename.to_s] = resume.download

    # Create the mail object.
    # For now, we'll send it to your OWN email address so we don't accidentally spam real companies while testing!
    mail(
      to: user.email, # TODO: Change to job.company.email in production
      from: user.email,
      subject: "Application: #{job.title}"
    )
  end
end
