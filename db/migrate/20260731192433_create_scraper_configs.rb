class CreateScraperConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :scraper_configs do |t|
      t.string :site_name
      t.string :url
      t.string :card_selector
      t.string :title_selector
      t.string :company_selector
      t.string :link_selector
      t.boolean :active, default: true # Add this default!

      t.timestamps
    end
  end
end
