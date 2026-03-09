# frozen_string_literal: true

module RailsMarkup
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    private

    def authorize!
      return if RailsMarkup.config.auth_check.call(self)

      head :forbidden
    end
  end
end
