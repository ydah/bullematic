# frozen_string_literal: true

Rails.application.routes.draw do
  resources :posts, only: %i[index show] do
    resources :comments, only: [:index]
  end
  resources :users, only: %i[index show]
end
