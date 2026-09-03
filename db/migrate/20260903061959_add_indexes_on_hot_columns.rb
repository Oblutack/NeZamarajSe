class AddIndexesOnHotColumns < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Every FK/uniqueness constraint already had an index; none of the
    # columns the app actually filters and sorts by hot paths on did. Fine
    # at hundreds of rows (a sequential scan is basically free), not fine at
    # 10k+ - see ROADMAP.md Track L for which query each one backs.
    add_index :jobs, :created_at, algorithm: :concurrently         # default sort + posted_within filter
    add_index :jobs, :expires_at, algorithm: :concurrently         # sort=deadline, expiring_soon
    add_index :applications, :status, algorithm: :concurrently     # Kanban-adjacent status filters + CheckForRepliesJob's global .applied scan
    add_index :applications, :queued_at, algorithm: :concurrently  # User#remaining_daily_sends, runs on every dispatch
    add_index :companies, :is_cold_outreach, algorithm: :concurrently # dashboard cold/warm split + /companies filter
    add_index :application_events, :created_at, algorithm: :concurrently # dashboard funnel/recent-activity + the model's own default_scope order
  end
end
