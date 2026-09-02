class AddQueuedAtToApplications < ActiveRecord::Migration[8.1]
  def change
    add_column :applications, :queued_at, :datetime
  end
end
