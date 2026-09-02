class CreateHunterLookups < ActiveRecord::Migration[8.1]
  def change
    create_table :hunter_lookups do |t|
      t.references :company, null: false, foreign_key: true

      t.datetime :created_at, null: false
    end
  end
end
