class CreateApplicationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :application_events do |t|
      t.references :application, null: false, foreign_key: true
      t.string :event_type, null: false
      t.text :body
      t.string :from_status
      t.string :to_status

      t.datetime :created_at, null: false
    end
  end
end
