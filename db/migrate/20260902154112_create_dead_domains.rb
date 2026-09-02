class CreateDeadDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :dead_domains do |t|
      t.string :host, null: false
      t.integer :failure_count, default: 0, null: false
      t.datetime :last_failed_at

      t.timestamps
    end

    add_index :dead_domains, :host, unique: true
  end
end
