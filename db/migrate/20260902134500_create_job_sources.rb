class CreateJobSources < ActiveRecord::Migration[8.1]
  def change
    create_table :job_sources do |t|
      t.references :job, null: false, foreign_key: true
      t.string :source_name, null: false
      t.string :url

      t.datetime :created_at, null: false
    end

    add_index :job_sources, [ :job_id, :source_name ], unique: true
  end
end
