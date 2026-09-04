class CreateCompanyEmailSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :company_email_suggestions do |t|
      t.references :company, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :email, null: false

      t.timestamps
    end

    # One suggestion per user per company - a second submission updates their
    # existing one (find_or_initialize_by in the controller) rather than
    # letting a single user stack up multiple guesses to fake "uncontested".
    add_index :company_email_suggestions, [ :company_id, :user_id ], unique: true
  end
end
