# frozen_string_literal: true

Rails.application.routes.draw do
  resources :posts, only: %i[create update destroy]

  namespace :api do
    resources :posts, only: %i[create]
  end

  post "admin/posts" => "admin_posts#create"
end
