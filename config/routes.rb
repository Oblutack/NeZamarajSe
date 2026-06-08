# config/routes.rb
Rails.application.routes.draw do
  # Change the devise line to this:
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  root "home#index"
end
