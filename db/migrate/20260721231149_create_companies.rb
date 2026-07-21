class CreateCompanies < ActiveRecord::Migration[7.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :website
      t.string :domain

      t.timestamps
    end
    # Ensure we don't scrape the same company twice
    add_index :companies, :name, unique: true
  end
end