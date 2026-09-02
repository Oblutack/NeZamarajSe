class AddSentDetailsToApplications < ActiveRecord::Migration[8.1]
  def change
    add_column :applications, :sent_recipient, :string
    add_column :applications, :sent_subject, :string
    add_column :applications, :sent_body, :text
    add_column :applications, :gmail_message_id, :string
  end
end
