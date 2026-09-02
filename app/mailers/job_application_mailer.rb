# app/mailers/job_application_mailer.rb
class JobApplicationMailer < ApplicationMailer
  # A job with no known hr_email/company email can still be sent while
  # dry_run_emails is on (it just goes to your own inbox regardless, so
  # nothing is actually lost by trying) - but never for a real send. Raised
  # from #apply, not checked ahead of time by the caller, so this can never
  # drift out of sync with what #apply actually does.
  class NoRecipientError < StandardError; end

  def self.subject_for(job)
    "Application: #{job.title}"
  end

  def self.cold_outreach_subject_for(company)
    "Interested in opportunities at #{company.name}"
  end

  def apply(user, job, template, resume)
    @body = template.render_content(job)
    attachments[resume.filename.to_s] = resume.download

    recipient = job.hr_email.presence || job.company.primary_email.presence
    dry_run = Rails.application.config.dry_run_emails

    if recipient.blank? && !dry_run
      raise NoRecipientError, "Job ##{job.id} has no hr_email and #{job.company.name} has no primary_email"
    end

    to_address = dry_run ? user.email : recipient
    subject = self.class.subject_for(job)
    subject = "[DRY RUN] #{subject}" if dry_run

    mail(to: to_address, from: user.email, subject: subject)
  end

  def cold_outreach(user, company, template, resume)
    @body = template.render_content_for_company(company)
    attachments[resume.filename.to_s] = resume.download

    recipient = company.primary_email.presence
    dry_run = Rails.application.config.dry_run_emails

    if recipient.blank? && !dry_run
      raise NoRecipientError, "#{company.name} has no primary_email"
    end

    to_address = dry_run ? user.email : recipient
    subject = self.class.cold_outreach_subject_for(company)
    subject = "[DRY RUN] #{subject}" if dry_run

    mail(to: to_address, from: user.email, subject: subject)
  end
end
