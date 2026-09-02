class AddCrmDepthFieldsToApplications < ActiveRecord::Migration[8.1]
  def change
    add_column :applications, :contact_person, :string
    add_column :applications, :salary, :string
    add_column :applications, :interview_date, :datetime
    add_column :applications, :rejection_reason, :text
    add_column :applications, :last_followed_up_at, :datetime
    add_column :applications, :gmail_thread_id, :string
  end
end
