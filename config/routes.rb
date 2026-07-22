# config/routes.rb
require "sidekiq/web"
require "sidekiq/cron/web" # This adds the "Cron" tab to the UI

Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  resources :resumes, only: [ :index, :create, :destroy ]
  resources :cover_letter_templates, except: [ :show ]

  # --- ADMIN / DASHBOARDS ---
  # Only logged-in users can access the Sidekiq dashboard
  authenticate :user do
    mount Sidekiq::Web => "/sidekiq"
  end

  root "home#index"
end
