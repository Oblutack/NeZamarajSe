class AddColdOutreachFieldsToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :industry_code, :string
    add_column :companies, :address, :string
    add_column :companies, :city, :string
    add_column :companies, :primary_email, :string

    # This helps us distinguish between Dzobs companies and CompanyWall companies
    add_column :companies, :is_cold_outreach, :boolean, default: false
  end
end
