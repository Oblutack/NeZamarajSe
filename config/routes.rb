# config/routes.rb
require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  # --- ADMIN / DASHBOARDS ---
  authenticate :user do
    mount Sidekiq::Web => "/sidekiq"
  end

  # --- ASSETS & TEMPLATES ---
  resources :resumes, only: [ :index, :create, :destroy ]
  resources :cover_letter_templates, except: [ :show ]

  # --- PHASE 4 ROUTES (The Job Market & CRM) ---
  resources :jobs, only: [ :index ]
  resources :applications, only: [ :create, :update, :destroy ]
  get "/crm", to: "applications#index", as: :crm

  root "home#index"
end
