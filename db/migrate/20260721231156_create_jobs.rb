class CreateJobs < ActiveRecord::Migration[7.1]
  def change
    create_table :jobs do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.string :location
      t.text :description
      t.string :external_id

      t.timestamps
    end
    # Ensure the scraper doesn't create duplicate jobs based on URL or External ID
    add_index :jobs, :url, unique: true
    add_index :jobs, :external_id, unique: true
  end
end
