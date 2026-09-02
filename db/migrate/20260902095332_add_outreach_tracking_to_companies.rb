class AddOutreachTrackingToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :last_contacted_at, :datetime
    add_reference :companies, :last_contacted_by, null: true, foreign_key: { to_table: :users }
  end
end
