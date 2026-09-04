class AddLastDashboardVisitAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_dashboard_visit_at, :datetime
  end
end
