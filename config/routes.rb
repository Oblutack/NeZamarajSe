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

  resource :user_preference, only: [ :edit, :update ]

  # --- PHASE 4 ROUTES (The Job Market & CRM) ---
  resources :jobs, only: [ :index ]
  resources :companies, only: [ :index, :show ] do
    member do
      get :compose_outreach
      post :dispatch_outreach
      post :refresh_email
    end
  end
  resources :applications, only: [ :create, :update, :destroy ] do
    # Member routes apply to ONE specific record (e.g. /applications/5/compose)
    member do
      get :compose
      post :dispatch_email
    end

    # Collection routes apply to MULTIPLE records (e.g. /applications/bulk_compose)
    collection do
      get :bulk_compose
      post :bulk_dispatch
    end
  end
  get "/crm", to: "applications#index", as: :crm
  get "/dashboard", to: "dashboard#show", as: :dashboard

  root "home#index"
end
