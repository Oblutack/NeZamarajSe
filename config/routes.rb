# config/routes.rb
require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  # --- ADMIN / DASHBOARDS ---
  authenticate :user, ->(user) { user.admin? } do
    mount Sidekiq::Web => "/sidekiq"
  end

  # --- ASSETS & TEMPLATES ---
  resources :resumes, only: [ :index, :create, :destroy ]
  resources :cover_letter_templates, except: [ :show ]

  resource :user_preference, only: [ :edit, :update ]

  # --- PHASE 4 ROUTES (The Job Market & CRM) ---
  resources :jobs, only: [ :index, :show, :new, :create ] do
    member do
      post :share
      post :unshare
    end
  end
  # Deliberately outside the authenticated jobs/ namespace - the app's first
  # unauthenticated, non-Devise surface (see ROADMAP.md Track N).
  get "/j/:token", to: "public_jobs#show", as: :public_job
  resources :companies, only: [ :index, :show ] do
    member do
      get :compose_outreach
      post :dispatch_outreach
      post :refresh_email
    end
    resources :email_suggestions, only: [ :create ], controller: "company_email_suggestions"
  end
  resources :applications, only: [ :create, :show, :update, :destroy ] do
    # Member routes apply to ONE specific record (e.g. /applications/5/compose)
    member do
      get :compose
      post :dispatch_email
      post :cancel
      get :interview_ics
      post :add_note
      get :compose_follow_up
      post :dispatch_follow_up
    end

    # Collection routes apply to MULTIPLE records (e.g. /applications/bulk_compose)
    collection do
      get :bulk_compose
      post :bulk_dispatch
    end
  end
  get "/crm", to: "applications#index", as: :crm
  get "/dashboard", to: "dashboard#show", as: :dashboard
  get "/locale/:locale", to: "locales#update", as: :set_locale, constraints: { locale: /en|bs/ }

  root "home#index"
end
