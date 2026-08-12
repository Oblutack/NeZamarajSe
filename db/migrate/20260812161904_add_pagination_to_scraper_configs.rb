class AddPaginationToScraperConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :scraper_configs, :next_page_selector, :string
  end
end
