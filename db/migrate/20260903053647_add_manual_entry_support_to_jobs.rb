class AddManualEntrySupportToJobs < ActiveRecord::Migration[8.1]
  def change
    # nil means "scraped/shared" (every job before this migration, and every
    # future scraped job) - a real user id means "manually added, private to
    # that user". See Job.visible_to and JobsController.
    add_reference :jobs, :added_by, null: true, foreign_key: { to_table: :users }

    # Scraped jobs always have a URL; a job entered by hand (found via
    # LinkedIn, a company careers page, or word of mouth) often doesn't.
    # Postgres unique indexes already allow multiple NULLs, so the existing
    # index_jobs_on_url index needs no change.
    change_column_null :jobs, :url, true
  end
end
