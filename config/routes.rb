# config/routes.rb
Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: 'users/omniauth_callbacks'
  }

  # Resources creates standard RESTful routes (index, create, destroy)
  resources :resumes, only: [:index, :create, :destroy]

  root "home#index"
end