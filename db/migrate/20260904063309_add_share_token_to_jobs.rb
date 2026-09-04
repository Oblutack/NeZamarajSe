class AddShareTokenToJobs < ActiveRecord::Migration[8.1]
  def change
    # nil means not shared (every job, including every scraped one, stays
    # this way unless a user explicitly turns sharing on for their own
    # manual entry). A real value is an unguessable public token - GET
    # /j/:token skips authentication entirely, so this needs to be looked
    # up efficiently and never collide.
    add_column :jobs, :share_token, :string
    add_index :jobs, :share_token, unique: true
  end
end
