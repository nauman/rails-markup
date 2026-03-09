# frozen_string_literal: true

Rails.application.routes.draw do
  mount RailsMarkup::Engine, at: "/feedback"
end
