class CreateCoverLetterTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :cover_letter_templates do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :body, null: false

      t.timestamps
    end
    
    # A user shouldn't have two templates with the exact same name
    add_index :cover_letter_templates, [:user_id, :name], unique: true
  end
end