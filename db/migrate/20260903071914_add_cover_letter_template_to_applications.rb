class AddCoverLetterTemplateToApplications < ActiveRecord::Migration[8.1]
  def change
    # Nullable and ON DELETE SET NULL, not cascade - sent_recipient/subject/
    # body already capture what was actually sent independent of whether the
    # template itself still exists, so deleting a template should orphan
    # this reference, not the application's own history.
    add_reference :applications, :cover_letter_template, null: true, foreign_key: { on_delete: :nullify }
  end
end
