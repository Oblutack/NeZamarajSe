class AddAiFieldsToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :hr_email, :string
    add_column :jobs, :expires_at, :date
  end
end
