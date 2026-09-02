class AddLocationAndDateSelectorsToScraperConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :scraper_configs, :location_selector, :string
    add_column :scraper_configs, :date_selector, :string
  end
end
