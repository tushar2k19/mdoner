Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "refresh#index"
  # get '/debug/cookies', to: 'debug#cookies_info'
  # get '/debug/request', to: 'debug#request_info'
  #
  # controller :refresh do
  #   post 'refresh' => 'refresh#create'
  # end
  #
  # controller :signin do
  #   post 'signin' => 'signin#create'
  #   delete 'signout' => 'signin#destroy'
  # end
  # controller :dashboard do
  #   get 'metrics' => 'dashboard#metrics'
  #   get 'blocks' => 'dashboard#blocks'
  #   get 'villages' => 'dashboard#villages'
  #   get 'agents' => 'dashboard#agents'
  #   get 'filtered_data' => 'dashboard#filtered_data'
  #   get 'farmers_data' => 'dashboard#farmers_data'
  #   get 'fetch_farmer_data' => 'dashboard#fetch_farmer_data'
  # end
  #
  # resources :location, only: [:index] do
  #   collection do
  #     get 'last_location'
  #     post 'update_last_location'
  #   end
  # end
  # resources :farmers, only: [:create, :update, :destroy] do
  #   member do
  #     get 'signed_url'
  #     get 'images'
  #     get 'display_images'
  #     post 'images', to: 'farmers#create_image'
  #     get 'images/:image_id/view', to: 'farmers#view_image'
  #     get 'images/:image_id/download', to: 'farmers#download_image'
  #     delete 'images/:image_id', to: 'farmers#delete_image'
  #   end
  # end


end
