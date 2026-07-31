# db/seeds.rb

puts "🌱 Seeding Scraper Configurations..."

ScraperConfig.find_or_create_by!(site_name: "Dzobs IT") do |config|
  config.url = "https://dzobs.com/poslovi/it-software"
  config.card_selector = "a[href^='/posao/']"
  config.title_selector = "h4"
  config.company_selector = "p.text-sm"
  # Dzobs card is the link itself, so we use a special keyword 'self'
  config.link_selector = "self"
end

puts "✅ Seeding complete!"
