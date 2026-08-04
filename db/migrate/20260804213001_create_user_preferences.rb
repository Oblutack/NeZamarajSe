class CreateUserPreferences < ActiveRecord::Migration[7.1]
  def change
    create_table :user_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :keywords # e.g., "Developer, Ruby, React"
      t.string :location # e.g., "Sarajevo, Remote"
      t.boolean :receive_daily_alerts, default: true

      t.timestamps
    end
  end
end
