# db/migrate/20240806XXXXXX_devise_create_users.rb
# (Your timestamp in the filename will be different)

class DeviseCreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## OAUTH COLUMNS (Add these!)
      t.string :provider
      t.string :uid
      t.string :access_token
      t.string :refresh_token
      t.datetime :token_expires_at

      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    
    # Add a composite index to ensure a Google user is unique
    add_index :users, [:provider, :uid], unique: true
  end
end