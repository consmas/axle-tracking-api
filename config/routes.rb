Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    post "auth/register", to: "auth#register"
    post "auth/login", to: "auth#login"

    namespace :v1 do
      post "cms/login", to: "cms_sessions#login"
      post "cms/login_diagnostic", to: "cms_sessions#login_diagnostic"
      get "cms/actions", to: "cms_actions#index"
      match "cms/actions/:action_name", to: "cms_actions#execute", via: [ :get, :post ]
      get "stream_proxy", to: "streams#show"
      get "map_feed", to: "vehicles#map_feed"

      resources :vehicles, only: [ :index ] do
        member do
          get :status
          get :track
          get :live_stream
          get :playback_files
        end
      end

      get "alarms", to: "alarms#index"
    end
  end
end
