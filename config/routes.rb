# config/routes.rb
Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  resources :resumes, only: [ :index, :create, :destroy ]
  resources :cover_letter_templates, except: [ :show ]

  root "home#index"
end
