class CreateApplications < ActiveRecord::Migration[7.1]
  def change
    create_table :applications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :job, null: false, foreign_key: true

      # Default state for a new application is 'wishlist'
      t.string :status, null: false, default: "wishlist"
      t.datetime :applied_at

      t.timestamps
    end

    # A user can only apply to a specific job once
    add_index :applications, [ :user_id, :job_id ], unique: true
  end
end
