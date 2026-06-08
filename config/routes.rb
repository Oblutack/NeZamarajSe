# config/routes.rb
Rails.application.routes.draw do
  devise_for :users
  # Defines the root path route ("/")
  root "home#index"
  
  # You can delete the get 'home/index' line that the generator made
end