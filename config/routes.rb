# frozen_string_literal: true

RailsMarkup::Engine.routes.draw do
  # Dashboard
  root to: "dashboard#index"
  resources :annotations, only: [:show, :update], controller: "dashboard", constraints: { id: /\d+/ }
  post "dismiss_all", to: "dashboard#dismiss_all"
  get "board", to: "dashboard#board"
  get "export.csv", to: "dashboard#export_csv", as: :export_csv
  get "export.json", to: "dashboard#export_json", as: :export_json

  # Toolbar API (same-origin, used by browser toolbar)
  scope :api, defaults: { format: :json } do
    post "sessions", to: "annotations#create_session"
    post "sessions/:session_id/annotations", to: "annotations#create"
    get "health", to: "annotations#health"

    scope "annotations/:id", constraints: { id: /\d+/ } do
      post "acknowledge", to: "annotations#acknowledge"
      post "resolve", to: "annotations#resolve"
      post "dismiss", to: "annotations#dismiss"
      post "reply", to: "annotations#reply"
    end
  end

  # External API (token-authenticated, used by MCP production tools)
  namespace :external, defaults: { format: :json } do
    get "annotations/pending", to: "annotations#pending"
    get "annotations/:id", to: "annotations#show", constraints: { id: /\d+/ }

    scope "annotations/:id", constraints: { id: /\d+/ } do
      patch "acknowledge", to: "annotations#acknowledge"
      patch "resolve", to: "annotations#resolve"
      patch "dismiss", to: "annotations#dismiss"
      patch "reply", to: "annotations#reply"
    end
  end
end
