class AddApplyDetailsToJobs < ActiveRecord::Migration[8.1]
  def change
    # All nullable and manual-entry-only for now (nothing populates these
    # from a scraper yet) - a real posting typed by hand wants more than
    # company/title/url/location/email/deadline/description.
    add_column :jobs, :employment_type, :string
    add_column :jobs, :work_mode, :string
    add_column :jobs, :salary_range, :string

    # Distinct from the existing `url` (the posting itself, used for "View
    # Original Posting") - this is specifically where to *submit* an
    # application when that's a web form rather than email. Plenty of
    # postings are apply-by-form; before this, a job with no known email
    # was a dead end in the CRM regardless of whether it listed its own
    # application link.
    add_column :jobs, :apply_url, :string
  end
end
