# frozen_string_literal: true

Rails.application.routes.draw do
  resource :rails_markup_test_session,
    only: %i[new create],
    controller: "rails_markup_test_sessions"

  mount RailsMarkup::Engine, at: "/feedback"

  # Host pages for system tests (toolbar overlay is injected here).
  get "/host", to: "pages#index"
  get "/other", to: "pages#other"

  # The browser auto-requests these; answer them so show_exceptions=:none
  # doesn't turn them into re-raised server errors during system tests.
  get "/favicon.ico", to: ->(_env) { [204, {}, []] }
end
