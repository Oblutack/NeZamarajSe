# db/seeds.rb
puts "🌱 Seeding Scraper Configurations..."

ScraperConfig.destroy_all # Clear old configs to avoid duplicates

# 1. Dzobs IT Jobs
ScraperConfig.create!(
  site_name: "Dzobs IT",
  url: "https://dzobs.com/poslovi/it-software",
  card_selector: "a[href^='/posao/']",
  title_selector: "h4",
  company_selector: "p.text-sm",
  link_selector: "self",
  next_page_selector: "a[rel='next']" # Assuming this is their standard next button
)

# 2. Dzobs Management/Marketing Jobs
ScraperConfig.create!(
  site_name: "Dzobs Management",
  url: "https://dzobs.com/poslovi/menadzment-upravljanje",
  card_selector: "a[href^='/posao/']",
  title_selector: "h4",
  company_selector: "p.text-sm",
  link_selector: "self",
  next_page_selector: "a[rel='next']"
)

# 3. YOUR TURN: Add MojPosao.ba!
# ScraperConfig.create!(
#   site_name: "MojPosao IT",
#   url: "https://www.mojposao.ba/#!search/jobs?category=11",
#   card_selector: "???",
#   title_selector: "???",
#   company_selector: "???",
#   link_selector: "???",
#   next_page_selector: "???"
# )

puts "✅ Seeding complete!"
